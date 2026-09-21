-- Bounded Retail Guild Bank support diagnostic. It never collects, persists, or
-- exports Guild Bank data; it reports API and collector state only when invoked.
local _, addon = ...
local Compat = WoWSyncCompat
if not (Compat and Compat.IsRetail and Compat.IsRetail()) then return end

local frame = CreateFrame("Frame")
local activeUntil = 0
local MAX_TABS, MAX_SLOTS = 8, 98 -- Blizzard's Mainline GuildBankFrame constants.
local rawEvents, rawRegistered, frameHooksInstalled = {}, {}, false

local function Say(text) print("WoWSync GuildBank: " .. text) end
local function Value(value) return value == nil and "nil" or tostring(value) end
local function Fields(detail)
    if not detail then return "nil" end
    return "texture=" .. Value(detail.texture) .. " count=" .. Value(detail.count)
        .. " locked=" .. Value(detail.locked) .. " filtered=" .. Value(detail.filtered)
        .. " quality=" .. Value(detail.quality) .. " link=" .. Value(detail.link)
end
local function IsOpen()
    return GuildBankFrame and GuildBankFrame.IsShown and GuildBankFrame:IsShown() or false
end

local function CountRaw(event)
    rawEvents[event] = (rawEvents[event] or 0) + 1
end

local function InstallFrameHooks()
    if frameHooksInstalled or not GuildBankFrame or type(GuildBankFrame.HookScript) ~= "function" then return end
    local ok = pcall(function()
        GuildBankFrame:HookScript("OnShow", function()
            CountRaw("FRAME_ONSHOW")
            if GetTime() <= activeUntil then Say("frame-hook=OnShow") end
        end)
        GuildBankFrame:HookScript("OnHide", function()
            CountRaw("FRAME_ONHIDE")
            if GetTime() <= activeUntil then Say("frame-hook=OnHide") end
        end)
    end)
    frameHooksInstalled = ok
end

local function TabInfo(tab)
    if type(GetGuildBankTabInfo) ~= "function" then return nil end
    local name, icon, canView, canDeposit, withdrawals, remaining, filtered = GetGuildBankTabInfo(tab)
    return name, icon, canView, canDeposit, withdrawals, remaining, filtered
end

local function Scan(tab, prefix)
    local name, icon, canView, canDeposit, withdrawals, remaining, filtered = TabInfo(tab)
    local populated, infoSignals, links, examples = 0, 0, 0, {}
    if type(GetGuildBankItemInfo) == "function" then
        for slot = 1, MAX_SLOTS do
            local texture, count, locked, isFiltered, quality = GetGuildBankItemInfo(tab, slot)
            local link = type(GetGuildBankItemLink) == "function" and GetGuildBankItemLink(tab, slot) or nil
            if texture ~= nil or count ~= nil or locked ~= nil or isFiltered ~= nil or quality ~= nil then infoSignals = infoSignals + 1 end
            if link then
                populated, links = populated + 1, links + 1
                if #examples < 3 then examples[#examples + 1] = slot .. "=" .. link .. " x" .. Value(count) end
            end
        end
    end
    Say(string.format("%s tab=%d name=%s icon=%s view=%s deposit=%s withdrawals=%s remaining=%s filtered=%s slots(info=%d links=%d populated=%d%s)%s",
        prefix, tab, Value(name), Value(icon), Value(canView), Value(canDeposit), Value(withdrawals), Value(remaining),
        Value(filtered), infoSignals, links, populated, infoSignals == 0 and " EMPTY_OR_UNLOADED" or "",
        #examples > 0 and " examples=" .. table.concat(examples, "; ") or ""))
end

local function Status()
    -- Keep event logging on briefly after an explicit status request so opening,
    -- tab metadata, and user-driven tab changes can be correlated without noise.
    activeUntil = GetTime() + 8
    InstallFrameHooks()
    local enabled = C_GuildBank and type(C_GuildBank.IsGuildBankEnabled) == "function"
        and C_GuildBank.IsGuildBankEnabled() or nil
    local tabCount = type(GetNumGuildBankTabs) == "function" and GetNumGuildBankTabs() or nil
    local current = type(GetCurrentGuildBankTab) == "function" and GetCurrentGuildBankTab() or nil
    local S = addon and addon.Sync
    local capture = S and S.guildCapture
    local phase = not capture and "idle" or capture.pending and "pending-tab-" .. capture.pending
        or capture.started and "queued" or "initializing"
    Say("status open=" .. tostring(IsOpen()) .. " enabled=" .. Value(enabled) .. " tabs=" .. Value(tabCount)
        .. " current=" .. Value(current) .. " query=" .. type(QueryGuildBankTab)
        .. " itemInfo=" .. type(GetGuildBankItemInfo) .. " itemLink=" .. type(GetGuildBankItemLink)
        .. " collector=" .. phase .. " collectorError=" .. Value(S and S.guildError)
        .. " initReason=" .. Value(capture and capture.lastReason))
    if S and S.guildTrace and #S.guildTrace > 0 then Say("collector-trace=" .. table.concat(S.guildTrace, " > ")) end
    local counts = S and S.guildEventCounts or {}
    local lifecycle = S and S.guildLifecycle or {}
    Say("event-registration rawOpen=" .. tostring(rawRegistered.GUILDBANKFRAME_OPENED)
        .. " rawClose=" .. tostring(rawRegistered.GUILDBANKFRAME_CLOSED)
        .. " productionOpen=" .. tostring(S and S.optionalEvents and S.optionalEvents.GUILDBANKFRAME_OPENED)
        .. " productionClose=" .. tostring(S and S.optionalEvents and S.optionalEvents.GUILDBANKFRAME_CLOSED)
        .. " rawCounts(open=" .. (rawEvents.GUILDBANKFRAME_OPENED or 0) .. ",close=" .. (rawEvents.GUILDBANKFRAME_CLOSED or 0)
        .. ",show=" .. (rawEvents.FRAME_ONSHOW or 0) .. ",hide=" .. (rawEvents.FRAME_ONHIDE or 0) .. ")"
        .. " productionCounts(open=" .. (counts.GUILDBANKFRAME_OPENED or 0) .. ",close=" .. (counts.GUILDBANKFRAME_CLOSED or 0)
        .. ",update=" .. (counts.GUILDBANK_UPDATE_TABS or 0) .. ",slots=" .. (counts.GUILDBANKBAGSLOTS_CHANGED or 0) .. ")"
        .. " productionLast=" .. Value(S and S.lastGuildEvent) .. " frameHooks=" .. tostring(frameHooksInstalled))
    Say("production-lifecycle hooks=" .. tostring(S and S.guildHooksInstalled)
        .. " show=" .. (lifecycle.shows or 0) .. " hide=" .. (lifecycle.hides or 0)
        .. " starts=" .. (lifecycle.starts or 0) .. " closes=" .. (lifecycle.closes or 0))
    local validations = S and S.guildLastValidation or {}
    local ids = {}
    for tab in pairs(validations) do ids[#ids + 1] = tab end
    table.sort(ids)
    for _, tab in ipairs(ids) do
        local validation = validations[tab]
        local detail = validation and validation.detail
        Say("tabValidation tab=" .. tab .. " state=" .. Value(validation and validation.state)
            .. " reason=" .. Value(detail and detail.reason) .. " slot=" .. Value(detail and detail.slot)
            .. " info=" .. Fields(detail))
    end
    if type(tabCount) ~= "number" then return end
    for tab = 1, math.min(tabCount, MAX_TABS) do Scan(tab, "read") end
end

for _, event in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED",
    "GUILDBANK_UPDATE_TABS", "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_TEXT", "GUILDBANK_TEXT_CHANGED",
    "GUILDBANKLOG_UPDATE", "GUILDBANK_ITEM_LOCK_CHANGED" }) do
    rawRegistered[event] = pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    CountRaw(event)
    if GetTime() > activeUntil then return end
    Say("event=" .. event .. " arg1=" .. Value(arg1) .. " arg2=" .. Value(arg2))
end)

SLASH_WOWSYNCGUILDBANK1 = "/wowsyncguildbank"
SlashCmdList.WOWSYNCGUILDBANK = function(argument)
    local command, value = (argument or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or "status"):lower()
    if command == "" or command == "status" then Status()
    elseif command == "query" then Say("/wowsyncguildbank [status]")
    else Say("/wowsyncguildbank [status|query <viewable-tab>] — query is explicit and does not export or persist data") end
end
