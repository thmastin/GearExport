-- Assisted Bank Cleanup v1.
-- Every transfer is authorized by one explicit Execute Next Move click. Event
-- callbacks below only observe and verify that already-authorized transfer.

local PLAN_HEADER = "GEARX_BANK_PLAN_V1"
local PREFIX = "|cff66ccffGearExport Bank:|r "
local BANK = BANK_CONTAINER or -1
local BAG_LAST = NUM_BAG_SLOTS or 4
local BANK_BAG_LAST = BAG_LAST + (NUM_BANKBAGSLOTS or 7)
local SETTLE_SECONDS = 1.0
local TIMEOUT_SECONDS = 8
local api = C_Container

local plan
local currentIndex
local verification
local frame
local importBox
local previewBox
local statusText
local importButton
local executeButton
local skipButton
local cancelButton

local function BankOpen()
    return BankFrame and BankFrame:IsShown()
end

local function Chat(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(message))
end

local function SetStatus(message, isError)
    statusText:SetText((isError and "|cffff6666" or "|cff66ff99") .. tostring(message) .. "|r")
    if isError then Chat(message) end
end

local function SlotCount(container)
    return api and api.GetContainerNumSlots and (api.GetContainerNumSlots(container) or 0) or 0
end

local function ItemAt(container, slot)
    if not api or type(api.GetContainerItemInfo) ~= "function" then return nil end
    local info = api.GetContainerItemInfo(container, slot)
    if not info then return nil end
    local link = info.hyperlink
    if not link and api.GetContainerItemLink then link = api.GetContainerItemLink(container, slot) end
    local itemID = info.itemID or (link and tonumber(link:match("item:(%d+)")))
    return {
        itemID = itemID,
        link = link,
        count = info.stackCount or 1,
        locked = info.isLocked and true or false,
    }
end

local function ForEachLocation(bankSide, callback)
    local first = bankSide and BANK or 0
    local last = bankSide and BANK_BAG_LAST or BAG_LAST
    for container = first, last do
        if not bankSide or container == BANK or container > BAG_LAST then
            for slot = 1, SlotCount(container) do
                if callback(container, slot) then return true end
            end
        end
    end
end

local function LocationQuantity(itemID, bankSide)
    if bankSide and not BankOpen() then return nil end
    local total = 0
    ForEachLocation(bankSide, function(container, slot)
        local item = ItemAt(container, slot)
        if item and item.itemID == itemID then total = total + item.count end
    end)
    return total
end

local function ItemName(itemID)
    local name = GetItemInfo and GetItemInfo(itemID)
    return name or ("Item " .. itemID .. " (name not cached)")
end

local function FindSource(move)
    local bankSide = move.verb == "WITHDRAW"
    local total = 0
    local unlockedSource
    local qualifyingLocked = false
    ForEachLocation(bankSide, function(container, slot)
        local item = ItemAt(container, slot)
        if item and item.itemID == move.itemID then
            total = total + item.count
            if item.count >= move.quantity then
                if item.locked then
                    qualifyingLocked = true
                elseif not unlockedSource then
                    unlockedSource = { container = container, slot = slot, item = item }
                end
            end
        end
    end)
    if unlockedSource then return unlockedSource, total end
    if qualifyingLocked then return nil, total, "A suitable source stack is currently locked." end
    if total >= move.quantity then
        return nil, total, "Requested quantity spans multiple stacks. Split the plan into multiple moves."
    end
    return nil, total, string.format("Requested %d; currently available: %d.", move.quantity, total)
end

local function CompatibleWithContainer(itemLink, container)
    if not api or type(api.GetContainerNumFreeSlots) ~= "function" then return false end
    local _, bagFamily = api.GetContainerNumFreeSlots(container)
    bagFamily = bagFamily or 0
    if bagFamily == 0 then return true end
    local itemFamily = GetItemFamily and (GetItemFamily(itemLink) or 0) or 0
    return bit and bit.band and bit.band(itemFamily, bagFamily) ~= 0
end

local function FindEmptyDestination(bankSide, itemLink)
    local foundContainer, foundSlot
    ForEachLocation(bankSide, function(container, slot)
        if CompatibleWithContainer(itemLink, container) and not ItemAt(container, slot) then
            foundContainer, foundSlot = container, slot
            return true
        end
    end)
    return foundContainer, foundSlot
end

local function HasExistingStackCapacity(itemID, quantity, bankSide)
    local sufficient = false
    ForEachLocation(bankSide, function(container, slot)
        local item = ItemAt(container, slot)
        if item and item.itemID == itemID and not item.locked then
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(item.link or itemID)
            maxStack = tonumber(maxStack) or item.count
            if maxStack - item.count >= quantity then sufficient = true; return true end
        end
    end)
    return sufficient
end

local function HasAutomaticDestination(move, source)
    local destinationBank = move.verb == "DEPOSIT"
    if HasExistingStackCapacity(move.itemID, move.quantity, destinationBank) then return true end
    return FindEmptyDestination(destinationBank, source.item.link) ~= nil
end

local function ParsePlan(text)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end
    if lines[1] ~= PLAN_HEADER then
        return nil, "Line 1 must exactly match " .. PLAN_HEADER .. "."
    end

    local moves = {}
    for lineNumber = 2, #lines do
        -- Clipboard sources can add harmless whitespace at line boundaries.
        -- Fields and separators remain strict; whitespace inside a move is rejected.
        local line = lines[lineNumber]:match("^%s*(.-)%s*$")
        if line:match("%S") then
            -- WoW edit boxes may store a pasted literal pipe as || while drawing
            -- it as a single pipe. Normalize only the exact three-field form.
            local escapedVerb, escapedItem, escapedQuantity = line:match("^([^|]+)||([^|]+)||([^|]+)$")
            if escapedVerb then
                line = escapedVerb .. "|" .. escapedItem .. "|" .. escapedQuantity
            end
            local verb, itemText, quantityText = line:match("^([^|]*)|([^|]*)|([^|]*)$")
            if not verb then
                return nil, string.format("Malformed plan line %d. Stored text: %q", lineNumber, line)
            end
            if verb ~= "DEPOSIT" and verb ~= "WITHDRAW" then
                return nil, "Unsupported verb on line " .. lineNumber .. ": " .. verb
            end
            if not itemText:match("^%d+$") then
                return nil, "Item ID must be a positive integer on line " .. lineNumber .. "."
            end
            if not quantityText:match("^%d+$") then
                return nil, "Quantity must be a positive integer on line " .. lineNumber .. "."
            end
            local itemID = tonumber(itemText)
            local quantity = tonumber(quantityText)
            if not itemID or itemID <= 0 or itemID > 2147483647 then
                return nil, "Item ID must be a positive integer on line " .. lineNumber .. "."
            end
            if not quantity or quantity <= 0 or quantity > 2147483647 then
                return nil, "Quantity must be a positive integer on line " .. lineNumber .. "."
            end
            table.insert(moves, {
                verb = verb, itemID = itemID, quantity = quantity,
                state = "Pending", lineNumber = lineNumber,
            })
        end
    end
    if #moves == 0 then return nil, "The plan contains no moves." end
    moves[1].state = "Current"
    return moves
end

local function Counts()
    local counts = { Complete = 0, Skipped = 0, Failed = 0, Pending = 0, Current = 0 }
    for _, move in ipairs(plan or {}) do counts[move.state] = (counts[move.state] or 0) + 1 end
    return counts
end

local function PlanFinished()
    if not plan then return false end
    for _, move in ipairs(plan) do
        if move.state ~= "Complete" and move.state ~= "Skipped" then return false end
    end
    return true
end

local function PlanFailed()
    for _, move in ipairs(plan or {}) do
        if move.state == "Failed" then return true end
    end
    return false
end

local function SourceContext(move)
    if move.verb == "WITHDRAW" and not BankOpen() then return "bank closed" end
    local available = LocationQuantity(move.itemID, move.verb == "WITHDRAW")
    return tostring(available or 0) .. " available in " .. (move.verb == "DEPOSIT" and "bags" or "bank")
end

local function RefreshButtons()
    local move = plan and currentIndex and plan[currentIndex]
    local canProgress = move and move.state == "Current" and not verification
    if canProgress and BankOpen() then executeButton:Enable() else executeButton:Disable() end
    if canProgress then skipButton:Enable() else skipButton:Disable() end
    if plan and not verification then cancelButton:Enable() else cancelButton:Disable() end
end

local function RefreshPreview()
    if not plan then
        previewBox:SetText("No plan imported.")
        RefreshButtons()
        return
    end
    local output = { "Bank Cleanup Plan", "" }
    for index, move in ipairs(plan) do
        local marker = move.state == "Current" and ">>> " or ""
        table.insert(output, string.format("%s%d. [%s] %s", marker, index, move.state, move.verb))
        table.insert(output, string.format("    %d %s", move.quantity, ItemName(move.itemID)))
        table.insert(output, string.format("    Item ID %d; %s", move.itemID, SourceContext(move)))
        if move.message then table.insert(output, "    " .. move.message) end
        table.insert(output, "")
    end
    local counts = Counts()
    if PlanFinished() then
        table.insert(output, "Bank Cleanup Plan Complete")
        table.insert(output, string.format("Completed: %d   Skipped: %d   Failed: %d",
            counts.Complete, counts.Skipped, counts.Failed))
    elseif PlanFailed() then
        table.insert(output, "Bank Cleanup Plan Stopped")
        table.insert(output, string.format("Completed: %d   Skipped: %d   Failed: %d",
            counts.Complete, counts.Skipped, counts.Failed))
    else
        table.insert(output, string.format("Completed: %d   Skipped: %d   Failed: %d",
            counts.Complete, counts.Skipped, counts.Failed))
    end
    previewBox:SetText(table.concat(output, "\n"))
    RefreshButtons()
end

local function Advance()
    currentIndex = nil
    for index, move in ipairs(plan) do
        if move.state == "Pending" then
            move.state = "Current"
            currentIndex = index
            break
        end
    end
    RefreshPreview()
    if not currentIndex then SetStatus("Bank Cleanup Plan Complete", false) end
end

local function FailCurrent(message)
    local move = plan and currentIndex and plan[currentIndex]
    if move then
        move.state = "Failed"
        move.message = message
    end
    verification = nil
    SetStatus(message .. " Plan progression stopped.", true)
    RefreshPreview()
end

local function BuildFrame()
    frame = CreateFrame("Frame", "GearExportBankCleanupFrame", UIParent)
    frame:SetSize(700, 620)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.94)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("GearExport: Assisted Bank Cleanup")

    local importLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importLabel:SetPoint("TOPLEFT", 18, -42)
    importLabel:SetText("Paste GEARX_BANK_PLAN_V1 plan (importing never moves items):")

    local importScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    importScroll:SetPoint("TOPLEFT", 18, -62)
    importScroll:SetSize(648, 120)
    importBox = CreateFrame("EditBox", nil, importScroll)
    importBox:SetMultiLine(true)
    importBox:SetAutoFocus(false)
    importBox:SetFontObject(ChatFontNormal)
    importBox:SetWidth(628)
    importBox:SetHeight(116)
    importBox:SetTextInsets(4, 4, 4, 4)
    importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    importScroll:SetScrollChild(importBox)

    importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(130, 24)
    importButton:SetPoint("TOPLEFT", 18, -190)
    importButton:SetText("Import / Validate")

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("LEFT", importButton, "RIGHT", 12, 0)
    statusText:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Paste a plan, then import and review it.")

    local previewScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    previewScroll:SetPoint("TOPLEFT", 18, -224)
    previewScroll:SetPoint("BOTTOMRIGHT", -42, 58)
    previewBox = CreateFrame("EditBox", nil, previewScroll)
    previewBox:SetMultiLine(true)
    previewBox:SetAutoFocus(false)
    previewBox:SetFontObject(ChatFontNormal)
    previewBox:SetWidth(628)
    previewBox:SetHeight(330)
    previewBox:SetTextInsets(4, 4, 4, 4)
    previewBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    previewBox:SetScript("OnTextChanged", function(self)
        self:SetHeight(math.max(330, (self:GetNumLines() or 1) * 14 + 16))
    end)
    previewScroll:SetScrollChild(previewBox)

    executeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    executeButton:SetSize(150, 26)
    executeButton:SetPoint("BOTTOMLEFT", 18, 18)
    executeButton:SetText("Execute Next Move")

    skipButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    skipButton:SetSize(100, 26)
    skipButton:SetPoint("LEFT", executeButton, "RIGHT", 8, 0)
    skipButton:SetText("Skip Move")

    cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 26)
    cancelButton:SetPoint("LEFT", skipButton, "RIGHT", 8, 0)
    cancelButton:SetText("Cancel Plan")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 26)
    closeButton:SetPoint("BOTTOMRIGHT", -18, 18)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() frame:Hide() end)
end

BuildFrame()

importButton:SetScript("OnClick", function()
    if verification then SetStatus("Wait for the current move verification to finish.", true); return end
    local parsed, errorMessage = ParsePlan(importBox:GetText())
    if not parsed then
        plan, currentIndex = nil, nil
        SetStatus(errorMessage, true)
        previewBox:SetText("Plan Import Error\n\n" .. errorMessage
            .. "\n\nClick this area, press Ctrl+A, then Ctrl+C to copy the error.")
        RefreshButtons()
        return
    end
    plan, currentIndex = parsed, 1
    SetStatus(BankOpen() and "Plan validated. Review it before executing."
        or "Plan validated. Open the normal character bank to execute.", false)
    RefreshPreview()
end)

skipButton:SetScript("OnClick", function()
    if verification then SetStatus("Cannot skip while a move is being verified.", true); return end
    local move = plan and currentIndex and plan[currentIndex]
    if not move or move.state ~= "Current" then return end
    move.state = "Skipped"
    move.message = "Skipped by player; no inventory action performed."
    SetStatus(string.format("Skipped move %d. No item was moved.", currentIndex), false)
    Advance()
end)

cancelButton:SetScript("OnClick", function()
    if verification then SetStatus("Cannot cancel while an initiated move is awaiting verification.", true); return end
    plan, currentIndex = nil, nil
    SetStatus("Plan cancelled. No inventory action was performed by cancellation.", false)
    RefreshPreview()
end)

executeButton:SetScript("OnClick", function()
    if verification then SetStatus("Wait for current move verification.", true); return end
    local move = plan and currentIndex and plan[currentIndex]
    if not move or move.state ~= "Current" then SetStatus("There is no current move to execute.", true); return end
    if not BankOpen() then SetStatus("Open the normal character bank before executing.", true); RefreshButtons(); return end
    if not api or type(api.UseContainerItem) ~= "function"
        or type(api.SplitContainerItem) ~= "function" or type(api.PickupContainerItem) ~= "function" then
        SetStatus("Required C_Container APIs are unavailable.", true); return
    end
    if GetCursorInfo() then SetStatus("Cannot execute: the cursor is not empty. Resolve it manually first.", true); return end

    local source, available, sourceError = FindSource(move)
    if not source then
        FailCurrent(string.format("Cannot execute %s %d %s. %s Available in %s: %d.",
            move.verb, move.quantity, ItemName(move.itemID), sourceError or "No suitable source stack.",
            move.verb == "DEPOSIT" and "bags" or "bank", available or 0))
        return
    end
    if source.item.itemID ~= move.itemID or source.item.locked then
        FailCurrent("Live source identity or lock state changed before execution.")
        return
    end

    local partial = source.item.count > move.quantity
    local destinationBank = move.verb == "DEPOSIT"
    local destinationContainer, destinationSlot
    if partial then
        destinationContainer, destinationSlot = FindEmptyDestination(destinationBank, source.item.link)
        if not destinationContainer then
            FailCurrent("No safe compatible empty destination slot is available for this partial-stack move.")
            return
        end
        if ItemAt(destinationContainer, destinationSlot) then
            FailCurrent("Destination changed before execution; no item was moved.")
            return
        end
    elseif not HasAutomaticDestination(move, source) then
        FailCurrent("No safe destination capacity is available for this full-stack move.")
        return
    end

    verification = {
        move = move,
        index = currentIndex,
        sourceContainer = source.container,
        sourceSlot = source.slot,
        sourceCount = source.item.count,
        beforeBags = LocationQuantity(move.itemID, false),
        beforeBank = LocationQuantity(move.itemID, true),
        destinationContainer = destinationContainer,
        destinationSlot = destinationSlot,
        started = GetTime(),
        lastEvent = GetTime(),
    }
    SetStatus(string.format("Executing one move: %s %d %s. Waiting for verification...",
        move.verb, move.quantity, ItemName(move.itemID)), false)
    RefreshButtons()

    local ok, errorMessage
    if partial then
        ok, errorMessage = pcall(api.SplitContainerItem, source.container, source.slot, move.quantity)
        local cursorKind, cursorItemID = GetCursorInfo()
        if not ok or cursorKind ~= "item" or (cursorItemID and cursorItemID ~= move.itemID) then
            FailCurrent("Partial-stack split failed: " .. tostring(errorMessage or "expected item was not placed on cursor"))
            return
        end
        if ItemAt(destinationContainer, destinationSlot) then
            FailCurrent("Destination changed after split. Cursor was left untouched for manual resolution.")
            return
        end
        ok, errorMessage = pcall(api.PickupContainerItem, destinationContainer, destinationSlot)
        if not ok then
            FailCurrent("Partial-stack placement raised a Lua error: " .. tostring(errorMessage)
                .. " Cursor was left untouched for manual resolution.")
            return
        end
    else
        ok, errorMessage = pcall(api.UseContainerItem, source.container, source.slot)
        if not ok then FailCurrent("Full-stack transfer raised a Lua error: " .. tostring(errorMessage)); return end
    end
end)

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYERBANKSLOTS_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GET_ITEM_INFO_RECEIVED", "UI_ERROR_MESSAGE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do pcall(eventFrame.RegisterEvent, eventFrame, event) end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "BANKFRAME_OPENED" then
        RefreshPreview()
        if plan and not verification then SetStatus("Bank open. Review the current move before executing.", false) end
        return
    elseif event == "BANKFRAME_CLOSED" then
        if verification then
            FailCurrent("Bank closed while the initiated move was awaiting verification; exact result could not be confirmed.")
        else
            SetStatus(plan and "Bank closed. Reopen it before executing." or "Bank closed.", false)
            RefreshPreview()
        end
        return
    end
    if verification then
        if event == "UI_ERROR_MESSAGE" or event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            local argumentCount = select("#", ...)
            local lastArgument = argumentCount > 0 and select(argumentCount, ...) or "unknown error"
            verification.reportedError = event .. ": " .. tostring(lastArgument)
        end
        verification.lastEvent = GetTime()
    elseif plan then
        RefreshPreview()
    end
end)

eventFrame:SetScript("OnUpdate", function()
    if not verification then return end
    local now = GetTime()
    if now - verification.started >= TIMEOUT_SECONDS then
        FailCurrent("Timed out waiting for exact inventory confirmation. Do not continue this plan.")
        return
    end
    if now - verification.lastEvent < SETTLE_SECONDS then return end

    local check = verification
    local afterBags = LocationQuantity(check.move.itemID, false)
    local afterBank = LocationQuantity(check.move.itemID, true)
    local expectedBags = check.beforeBags + (check.move.verb == "WITHDRAW" and check.move.quantity or -check.move.quantity)
    local expectedBank = check.beforeBank + (check.move.verb == "WITHDRAW" and -check.move.quantity or check.move.quantity)
    local source = ItemAt(check.sourceContainer, check.sourceSlot)
    local expectedSourceCount = check.sourceCount - check.move.quantity
    local sourceCorrect = expectedSourceCount == 0 and source == nil
        or source and source.itemID == check.move.itemID and source.count == expectedSourceCount and not source.locked
    local cursorEmpty = not GetCursorInfo()
    local exact = afterBags == expectedBags and afterBank == expectedBank and sourceCorrect and cursorEmpty

    if exact then
        check.move.state = "Complete"
        check.move.message = string.format("Verified exactly: bags %d, bank %d.", afterBags, afterBank)
        verification = nil
        SetStatus(string.format("Move %d complete and exactly verified. No next move will run automatically.", check.index), false)
        Advance()
    else
        local detail = string.format("Verification failed. Expected bags=%d bank=%d; observed bags=%s bank=%s; source correct=%s; cursor empty=%s",
            expectedBags, expectedBank, tostring(afterBags), tostring(afterBank), tostring(sourceCorrect), tostring(cursorEmpty))
        if check.reportedError then detail = detail .. "; client error: " .. check.reportedError end
        FailCurrent(detail)
    end
end)

SLASH_GEARBANKCLEANUP1 = "/bankx"
SlashCmdList.GEARBANKCLEANUP = function()
    frame:Show()
    RefreshPreview()
    if plan then
        SetStatus(BankOpen() and "Review the current move before executing."
            or "Open the normal character bank before executing.", false)
    else
        SetStatus("Paste a plan, then import and review it. Importing never moves items.", false)
    end
end

table.insert(UISpecialFrames, "GearExportBankCleanupFrame")
