local _, addon = ...
local S = addon.Sync
local window, edit, scroll, status, syncButton, launcher, minimapButton
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

local function EnsureReloadPopup()
    if StaticPopupDialogs["WOWSYNC_RELOAD_UI"] then return end
    StaticPopupDialogs["WOWSYNC_RELOAD_UI"] = {
        text = "Reload the UI so WoW flushes WoWSync SavedVariables to disk?\n\nRequired for the Dashboard watcher. Does not run automatically.",
        button1 = YES,
        button2 = NO,
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

local function ConfirmReloadUI()
    EnsureReloadPopup()
    StaticPopup_Show("WOWSYNC_RELOAD_UI")
end

local function MinimapAngle()
    local angle = S.settings.minimapAngle
    if type(angle) ~= "number" then angle = 220 end
    return angle
end

local function PlaceMinimapButton()
    if not minimapButton or not Minimap then return end
    local angle = math.rad(MinimapAngle())
    local radius = 80
    local ok, width = pcall(function() return Minimap:GetWidth() end)
    if ok and type(width) == "number" and width > 0 then
        radius = (width / 2) + 5
    end
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    local button = CreateFrame("Button", "WoWSyncMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\GearExport\\WoWSyncIcon.tga")
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("WoWSync")
        GameTooltip:AddLine("Left-click: open / refresh handoff", 1, 1, 1)
        GameTooltip:AddLine("Right-click: reload UI (flush SavedVariables)", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ConfirmReloadUI()
        else
            Sync()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(btn)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            S.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            PlaceMinimapButton()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    minimapButton = button
    PlaceMinimapButton()
    if S.settings.showMinimap == false then
        button:Hide()
    else
        -- Default on when unset.
        if S.settings.showMinimap == nil then S.settings.showMinimap = true end
        button:Show()
    end
end

function S.InitializeUI()
    if not S.Initialize() then return end
    if window then
        CreateMinimapButton()
        return
    end
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
    local reload = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    reload:SetSize(100, 24); reload:SetPoint("LEFT", syncButton, "RIGHT", 8, 0); reload:SetText("Reload UI")
    reload:SetScript("OnClick", ConfirmReloadUI)
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

    CreateMinimapButton()
end

function S.SlashExport() Sync() end
function S.SlashButton()
    S.InitializeUI()
    if not launcher then Message(S.error or "Not ready"); return end
    S.settings.showButton = not S.settings.showButton
    if S.settings.showButton then launcher:Show() else launcher:Hide() end
    Message(S.settings.showButton and "Floating SYNC button shown." or "Floating SYNC button hidden.")
end
function S.SlashMinimap()
    S.InitializeUI()
    CreateMinimapButton()
    if not minimapButton then Message("Minimap not available yet."); return end
    if minimapButton:IsShown() then
        S.settings.showMinimap = false
        minimapButton:Hide()
        Message("Minimap button hidden. /wowsync minimap to show.")
    else
        S.settings.showMinimap = true
        PlaceMinimapButton()
        minimapButton:Show()
        Message("Minimap button shown. Left=sync, Right=reload UI.")
    end
end