local _, addon = ...
local S = addon.Sync
local window, edit, scroll, status, syncButton, launcher
local function Message(text) print("WoWSync: " .. text) end

local function Sync()
    if not window then S.InitializeUI() end
    if not window then Message(S.error or "Character is not ready yet."); return end
    window:Show()
    syncButton:Disable()
    status:SetText("Refreshing accessible sections...")
    local ok, err = S.Export(function(text)
        edit:SetText(text)
        scroll:SetVerticalScroll(0)
        -- Do not reopen a dismissed window or steal focus after it was closed.
        if window:IsShown() then edit:SetFocus(); edit:HighlightText() end
        status:SetText("Ctrl+C to copy. Bank/trainer freshness is shown in the export.")
        syncButton:Enable()
    end)
    if not ok then status:SetText(err); syncButton:Enable() end
end

function S.InitializeUI()
    if not S.Initialize() then return end
    if window then return end
    window = CreateFrame("Frame", "WoWSyncExportFrame", UIParent)
    window:SetSize(760, 560); window:SetPoint("CENTER")
    window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    local bg = window:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.94)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14); title:SetText("WoWSync - Character handoff")
    scroll = CreateFrame("ScrollFrame", "WoWSyncExportScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -44); scroll:SetPoint("BOTTOMRIGHT", -40, 68)
    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(690); edit:SetHeight(420); edit:SetMaxLetters(0)
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetScript("OnTextChanged", function(self) self:SetHeight(math.max(420, (self:GetNumLines() or 1) * 14 + 16)) end)
    edit:SetScript("OnEscapePressed", function() window:Hide() end)
    scroll:SetScrollChild(edit)
    status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 18, 47)
    syncButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    syncButton:SetSize(100, 24); syncButton:SetPoint("BOTTOMLEFT", 18, 14); syncButton:SetText("SYNC")
    syncButton:SetScript("OnClick", Sync)
    local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    close:SetSize(80, 24); close:SetPoint("BOTTOMRIGHT", -18, 14); close:SetText("Close")
    close:SetScript("OnClick", function() window:Hide() end)
    window:Hide()
    table.insert(UISpecialFrames, "WoWSyncExportFrame")

    launcher = CreateFrame("Button", "WoWSyncButton", UIParent, "UIPanelButtonTemplate")
    launcher:SetSize(52, 20); launcher:SetPoint("TOPRIGHT", -180, -20); launcher:SetText("SYNC")
    launcher:SetAlpha(0.65); launcher:SetMovable(true); launcher:RegisterForDrag("LeftButton")
    launcher:SetScript("OnClick", Sync)
    launcher:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    launcher:SetScript("OnLeave", function(self) self:SetAlpha(0.65) end)
    launcher:SetScript("OnDragStart", launcher.StartMoving)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        S.settings.buttonPosition = { point, relative, x, y }
    end)
    local position = S.settings.buttonPosition
    if type(position) == "table" and #position == 4 then
        launcher:ClearAllPoints()
        local ok = pcall(launcher.SetPoint, launcher, position[1], UIParent, position[2], position[3], position[4])
        if not ok then launcher:SetPoint("TOPRIGHT", -180, -20) end
    end
    if not S.settings.showButton then launcher:Hide() end
end

function S.SlashExport() Sync() end
function S.SlashButton()
    S.InitializeUI()
    if not launcher then Message(S.error or "Not ready"); return end
    S.settings.showButton = not S.settings.showButton
    if S.settings.showButton then launcher:Show() else launcher:Hide() end
end

SLASH_WOWSYNC1 = "/wowsync"
SlashCmdList.WOWSYNC = function(argument)
    local command = (argument or ""):match("^%s*(.-)%s*$"):lower()
    if command == "" or command == "export" then Sync()
    elseif command == "button" then
        S.InitializeUI()
        if not launcher then Message(S.error or "Not ready"); return end
        S.settings.showButton = not S.settings.showButton
        if S.settings.showButton then launcher:Show() else launcher:Hide() end
    elseif command == "status" then
        local snapshot = S.GetSnapshot()
        if not snapshot then Message(S.error or "Not ready"); return end
        for _, key in ipairs(S.order) do
            local section = key == "accountBank" and snapshot.accountSections and snapshot.accountSections.bank
                or key == "guildBank" and snapshot.guildSections and snapshot.guildSections.bank
                or snapshot.sections[key]
            Message(key .. ": " .. (section and section.completeness or "unknown")
                .. ", observed=" .. tostring(section and section.observedAt or "never")
                .. (snapshot.pending[key] and ", pending" or "")
                .. (section and section.lastAttemptError and ", " .. section.lastAttemptError or ""))
        end
        local latest = S.record and S.record.latestExport
        Message("latestExport: generatedAt=" .. tostring(latest and latest.generatedAt or "none")
            .. (S.autoExportPending and ", autoRefreshPending" or "")
            .. (S.lastRenderError and (", renderError=" .. S.lastRenderError) or ""))
    else
        Message("/wowsync [export] - refresh and copy one handoff. /wowsync status - freshness. /wowsync button - toggle movable SYNC button. No reload needed for copying; /reload flushes SavedVariables for disk readers.")
    end
end
