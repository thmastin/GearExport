-- Observation only. No inventory/trainer action APIs belong in WoWSync.
local ADDON_NAME, addon = ...
local S = { apiVersion = 1, schemaVersion = 1, collectors = {}, dirty = {},
    order = { "character", "location", "equipment", "bags", "bank", "professions", "spells", "trainer", "itemMetadata" },
    bankOpen = false, guildBankOpen = false, trainerOpen = false, sessions = { bank = 0, accountBank = 0, guildBank = 0, trainer = 0 } }
if WoWSyncCompat and WoWSyncCompat.IsRetail and WoWSyncCompat.IsRetail() then
    table.insert(S.order, 6, "accountBank")
    table.insert(S.order, 7, "guildBank")
end
addon.Sync = S
WoWSync = S

function S.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = S.Copy(v) end
    return result
end

local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function S.Now() return (GetServerTime and GetServerTime()) or time() end

local function NormalizeTrainer(record)
    record.visits = type(record.visits) == "table" and record.visits or {}
    local section = record.sections and record.sections.trainer
    if section and type(section.data) == "table" and type(section.data.snapshots) ~= "table" then
        local legacy = section.data
        legacy.category = legacy.category or "UNKNOWN"
        section.data = { snapshots = { UNKNOWN = legacy } }
        section.completeness = section.completeness or "partial"
        section.reason = section.reason or "Migrated legacy single-trainer snapshot; category unknown"
    end
    if type(record.visits.trainers) ~= "table" then record.visits.trainers = {} end
    if record.visits.trainer and not record.visits.trainers.UNKNOWN then
        record.visits.trainers.UNKNOWN = record.visits.trainer
    end
end

function S.Initialize()
    if S.record then return true end
    if WoWSyncDB ~= nil and (type(WoWSyncDB) ~= "table"
        or (WoWSyncDB.schemaVersion ~= nil and WoWSyncDB.schemaVersion ~= 1)) then
        S.error = "Unsupported WoWSync database; existing data was preserved."
        return false
    end
    local guid, name, realm
    if addon.ReadIdentity then
        guid, name, realm = addon.ReadIdentity()
    else
        guid = UnitGUID("player")
    end
    if not guid then return false end
    WoWSyncDB = WoWSyncDB or {}
    local db = WoWSyncDB
    db.schemaVersion = 1
    db.settings = type(db.settings) == "table" and db.settings or {}
    db.characters = type(db.characters) == "table" and db.characters or {}
    if WoWSyncCompat and WoWSyncCompat.IsRetail and WoWSyncCompat.IsRetail() then
        -- Account/Warband storage belongs to this SavedVariables account scope,
        -- not to whichever character happened to make the observation.
        db.account = type(db.account) == "table" and db.account or {}
        db.account.sections = type(db.account.sections) == "table" and db.account.sections or {}
        db.account.visits = type(db.account.visits) == "table" and db.account.visits or {}
        db.guilds = type(db.guilds) == "table" and db.guilds or {}
        S.account, S.guilds = db.account, db.guilds
    else S.account, S.guilds, S.guild = nil, nil, nil end
    local record = db.characters[guid]
    if type(record) ~= "table" then record = {}; db.characters[guid] = record end
    if not addon.ReadIdentity then name, realm = UnitName("player"), GetRealmName() end
    record.identity = { guid = guid, name = name, realm = realm }
    record.sections = type(record.sections) == "table" and record.sections or {}
    record.visits = type(record.visits) == "table" and record.visits or {}
    record.itemMetadata = type(record.itemMetadata) == "table" and record.itemMetadata or {}
    NormalizeTrainer(record)
    S.record = record
    S.settings = db.settings
    S.error = nil
    return true
end

function S.RememberItemMetadata(itemID, metadata)
    if type(itemID) ~= "number" or itemID <= 0 or itemID % 1 ~= 0 or type(metadata) ~= "table" then return end
    local present = false
    for _, key in ipairs({ "classID", "subclassID", "bindType", "expansionID", "isCraftingReagent" }) do
        if metadata[key] ~= nil then present = true; break end
    end
    if not present then return end
    local known = S.record.itemMetadata[itemID]
    if type(known) ~= "table" then known = {}; S.record.itemMetadata[itemID] = known end
    for _, key in ipairs({ "classID", "subclassID", "bindType", "expansionID", "isCraftingReagent" }) do
        if metadata[key] ~= nil then known[key] = metadata[key] end
    end
end

local function OwnerFor(key)
    if key == "accountBank" then return S.account end
    if key == "guildBank" then return S.guild end
    return S.record
end

local function StoredKey(key)
    return (key == "accountBank" or key == "guildBank") and "bank" or key
end

function S.Commit(key, data, meta)
    local owner, storedKey = OwnerFor(key), StoredKey(key)
    if not owner then return end
    local old = owner.sections[storedKey]
    local now = S.Now()
    local changed = not old or not Equal(old.data, data)
    owner.sections[storedKey] = { data = data, observedAt = now,
        changedAt = changed and now or old.changedAt,
        revision = ((old and old.revision) or 0) + (changed and 1 or 0),
        completeness = meta.completeness or "complete", reason = meta.reason,
        source = meta.source or "client", capture = S.capture }
end

function S.CommitTrainer(category, data, meta)
    local old = S.record.sections.trainer
    local snapshots = old and old.data and old.data.snapshots and S.Copy(old.data.snapshots) or {}
    local now = S.Now()
    data.category = category
    data.observedAt = now
    data.completeness = meta.completeness or "complete"
    data.reason = meta.reason
    snapshots[category] = data
    local merged = { snapshots = snapshots }
    local changed = not old or not Equal(old.data, merged)
    S.record.sections.trainer = { data = merged, observedAt = now,
        changedAt = changed and now or old.changedAt,
        revision = ((old and old.revision) or 0) + (changed and 1 or 0),
        completeness = meta.completeness or "complete", reason = meta.reason,
        source = meta.source or "client", capture = S.capture, lastCategory = category }
end

function S.Attempt(key, reason, stale)
    local owner, storedKey = OwnerFor(key), StoredKey(key)
    if not owner then return end
    local old = owner.sections[storedKey]
    if not old then old = { completeness = "unknown", revision = 0 }; owner.sections[storedKey] = old end
    old.lastAttemptAt, old.lastAttemptError = S.Now(), reason
    if stale and old.data then old.lastAttemptStale = true end
end

function S.Mark(key, delay)
    if not S.collectors[key] then return end
    if (key == "bank" or key == "accountBank") and not S.bankOpen
        or key == "guildBank" and not S.guildBankOpen or key == "trainer" and not S.trainerOpen then return end
    local now = GetTime()
    local pending = S.dirty[key]
    if not pending then pending = { first = now, tries = 0 }; S.dirty[key] = pending end
    pending.due = math.min(now + (delay or 0.35), pending.first + 1.5)
    S.autoExportPending = true
    S.Wake()
end

function S.RequestPlayed()
    if S.playedPending and GetTime() < S.playedPending then return end
    S.played = nil
    S.playedPending = GetTime() + 3
    if S.unsupportedEvents.TIME_PLAYED_MSG or not WoWSyncCompat.RequestPlayed() then
        S.playedPending = nil
    end
end

function S.RequestSync()
    if not S.Initialize() then return false, S.error or "Character is not ready yet." end
    S.RequestPlayed()
    for _, key in ipairs(S.order) do S.Mark(key, 0.15) end
    return true
end

function S.GetSnapshot()
    if not S.Initialize() then return nil end
    if not S.guild and S.ResolveGuildBankOwner then S.ResolveGuildBankOwner() end
    local snapshot = { identity = S.Copy(S.record.identity), sections = S.Copy(S.record.sections),
        visits = S.Copy(S.record.visits), itemMetadata = S.Copy(S.record.itemMetadata) }
    snapshot.schemaVersion = S.schemaVersion
    snapshot.generatedAt = S.Now()
    snapshot.access = { bank = S.bankOpen and (not WoWSyncCompat or WoWSyncCompat.IsBankViewable()), trainer = S.trainerOpen,
        trainerCategory = S.trainerCategory }
    if S.account then
        snapshot.accountSections = S.Copy(S.account.sections)
        snapshot.access.accountBank = S.bankOpen and WoWSyncCompat.IsBankViewable("ACCOUNT")
    end
    if S.guild then
        snapshot.guildSections = S.Copy(S.guild.sections)
        snapshot.guildIdentity = S.Copy(S.guild.identity)
        snapshot.access.guildBank = S.guildBankOpen
    end
    snapshot.guildError = S.guildError
    snapshot.pending = {}
    for key in pairs(S.dirty) do snapshot.pending[key] = true end
    return snapshot
end

function S.GetSection(key)
    if not S.Initialize() then return nil end
    local owner = OwnerFor(key)
    return owner and S.Copy(owner.sections[StoredKey(key)]) or nil
end

local frame = CreateFrame("Frame")
S.eventFrame = frame
local function RefreshLatestExport()
    if not S.record then return nil end
    local snapshot = S.GetSnapshot()
    if not snapshot then return nil end
    if type(S.Render) ~= "function" then return nil end
    local ok, text = pcall(S.Render, snapshot)
    if not ok then
        S.lastRenderError = tostring(text)
        if not S.renderErrorPrinted then
            print("WoWSync: latestExport render failed: " .. S.lastRenderError)
            S.renderErrorPrinted = true
        end
        return nil
    end
    S.lastRenderError = nil
    S.record.latestExport = { text = text, generatedAt = snapshot.generatedAt }
    S.autoExportPending = next(S.dirty) and true or nil
    return text
end

local function Process(force)
    if not S.Initialize() then return end
    S.capture = (S.capture or 0) + 1
    local now = GetTime()
    for _, key in ipairs(S.order) do
        local pending = S.dirty[key]
        if pending and (force or now >= pending.due) then
            S.dirty[key] = nil
            local ok, data, meta = pcall(S.collectors[key])
            meta = ok and (meta or {}) or { reason = "Collector error: " .. tostring(data), retry = true }
            if ok and data then
                if key == "trainer" and data.category and data.snapshot then
                    S.CommitTrainer(data.category, data.snapshot, meta)
                else
                    S.Commit(key, data, meta)
                end
            else S.Attempt(key, meta.reason or "Data unavailable", meta.stale) end
            if meta.retry and not force and pending.tries < 4
                and ((key ~= "bank" and key ~= "accountBank") or S.bankOpen) and (key ~= "trainer" or S.trainerOpen) then
                pending.tries = pending.tries + 1
                pending.due = now + 0.5
                S.dirty[key] = pending
            end
        end
    end
end
S.Process = Process

local function Tick()
    if S.GuildBankTick then S.GuildBankTick(GetTime()) end
    Process(false)
    if S.exportRequest and (not next(S.dirty) and not S.playedPending or GetTime() >= S.exportRequest.deadline) then
        local callback = S.exportRequest.callback
        S.exportRequest = nil
        local text = RefreshLatestExport()
        if text then callback(text) end
    elseif S.autoExportPending and not next(S.dirty) then
        RefreshLatestExport()
    end
    if not next(S.dirty) and not S.exportRequest and not (S.GuildBankActive and S.GuildBankActive()) then frame:SetScript("OnUpdate", nil) end
end
function S.Wake() frame:SetScript("OnUpdate", Tick) end

function S.Export(callback)
    local ok, err = S.RequestSync()
    if not ok then return false, err end
    S.exportRequest = { deadline = GetTime() + 3, callback = callback }
    return true
end

local function Visit(key)
    S.sessions[key] = S.sessions[key] + 1
    if not S.Initialize() then return end
    local ok, location = pcall(S.collectors.location)
    local visit = { openedAt = S.Now(), location = ok and location or nil,
        name = UnitName("npc"), guid = UnitGUID("npc"), session = S.sessions[key] }
    if key == "trainer" then S.currentTrainerVisit = visit
    elseif key == "accountBank" then S.account.visits.bank = visit
    elseif key == "guildBank" then S.guild.visits.bank = visit
    else S.record.visits[key] = visit end
end

local function Close(key)
    if not S.record then return end
    local owner, storedKey = OwnerFor(key), StoredKey(key)
    local visit = key == "trainer" and S.currentTrainerVisit or owner.visits[storedKey]
    if key == "trainer" and visit then
        local category = S.trainerCategory or "UNKNOWN"
        S.record.visits.trainers[category] = visit
        S.currentTrainerVisit = nil
    end
    local section = owner.sections[storedKey]
    local observed = section
    if key == "trainer" and section and section.data and section.data.snapshots then
        observed = section.data.snapshots[S.trainerCategory or "UNKNOWN"]
    end
    if visit then
        visit.closedAt = S.Now()
        visit.unreconciled = S.dirty[key] ~= nil or not observed
            or not observed.data and key ~= "trainer" or section and section.lastAttemptError ~= nil
    end
    if S.dirty[key] then S.Attempt(key, "Closed before pending capture settled") end
    S.dirty[key] = nil
end
S.BeginVisit, S.EndVisit = Visit, Close

local events = addon.SyncEvents or {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_DESCRIPTION_UPDATE",
    "TRAINER_SERVICE_INFO_NAME_UPDATE", "TRAINER_CLOSED",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "SKILL_LINES_CHANGED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_MONEY", "PLAYER_LEVEL_UP",
    "PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "GET_ITEM_INFO_RECEIVED", "TIME_PLAYED_MSG",
}
S.unsupportedEvents = {}
for _, event in ipairs(events) do
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then S.unsupportedEvents[event] = true end
end
if not addon.SyncEvents and WoWSyncCompat and WoWSyncCompat.RegisterOptionalEvents then
    for event in pairs(WoWSyncCompat.RegisterOptionalEvents(frame)) do S.optionalEvents = S.optionalEvents or {}; S.optionalEvents[event] = true end
end

frame:SetScript("OnEvent", function(_, event, arg, arg2)
    if event:match("^GUILDBANK") then
        S.guildEventCounts = S.guildEventCounts or {}
        S.guildEventCounts[event] = (S.guildEventCounts[event] or 0) + 1
        S.lastGuildEvent = event
    end
    if event == "ADDON_LOADED" then
        if arg == ADDON_NAME then S.Initialize(); if S.InitializeUI then S.InitializeUI() end end
        -- Blizzard_GuildBankUI is LoadOnDemand.  Its ADDON_LOADED signal is the
        -- earliest clean point to hook GuildBankFrame before it is shown.
        if arg == "Blizzard_GuildBankUI" and S.InstallGuildBankHooks then S.InstallGuildBankHooks() end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        S.RequestSync(); if S.InitializeUI then S.InitializeUI() end
    elseif event == "TIME_PLAYED_MSG" then
        S.played = { total = WoWSyncCompat.PlayedSeconds(arg),
            levelSeconds = WoWSyncCompat.PlayedSeconds(arg2),
            level = S.playedLevel or UnitLevel("player"), guid = UnitGUID("player") }
        S.playedPending = nil
        S.Mark("character", 0)
    elseif event == "PLAYER_LEVEL_UP" then
        S.playedLevel = arg
        S.playedPending = nil
        S.RequestPlayed()
        S.Mark("character")
    elseif event == "PLAYER_LOGOUT" then
        if S.record then
            pcall(Process, true)
            RefreshLatestExport()
        end
    elseif event == "BANKFRAME_OPENED" then
        S.bankOpen = true; Visit("bank"); if S.collectors.accountBank then Visit("accountBank") end; S.Mark("bank"); S.Mark("accountBank"); S.Mark("bags")
    elseif event == "BANKFRAME_CLOSED" then
        S.bankOpen = false; Close("bank"); if S.collectors.accountBank then Close("accountBank") end; S.Mark("bags")
    elseif event == "GUILDBANKFRAME_OPENED" then
        if S.InstallGuildBankHooks then S.InstallGuildBankHooks() end
        if S.GuildBankOpened then S.GuildBankOpened("event-open") end
    elseif event == "GUILDBANKFRAME_CLOSED" then
        if S.GuildBankClosed then S.GuildBankClosed("event-close") end
    elseif event == "TRAINER_SHOW" then
        S.trainerOpen = true; Visit("trainer"); S.Mark("trainer"); S.Mark("spells")
    elseif event == "TRAINER_CLOSED" then
        S.trainerOpen = false; Close("trainer"); S.trainerCategory = nil
    elseif event:match("^TRAINER_") then
        S.Mark("trainer")
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED"
        or event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        S.Mark("bags"); S.Mark("bank")
    elseif event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
        S.Mark("accountBank")
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_UPDATE_TABS" or event == "GUILDBANK_ITEM_LOCK_CHANGED" then
        if S.GuildBankEvent then S.GuildBankEvent(event, arg, arg2) end
    elseif event == "BANK_TABS_CHANGED" or event == "BANK_TAB_SETTINGS_UPDATED" then
        if arg == nil or arg == (Enum and Enum.BankType and Enum.BankType.Character) then S.Mark("bank") end
        if arg == nil or arg == (Enum and Enum.BankType and Enum.BankType.Account) then S.Mark("accountBank") end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" and arg == "player" then
        S.Mark("equipment"); S.Mark("bags")
    elseif event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE"
        or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELL_TEXT_UPDATE"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "TRADE_SKILL_LIST_UPDATE" then
        S.Mark("professions"); S.Mark("spells"); S.Mark("trainer")
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if S.record then
            local keys = { "bags", "bank", "equipment" }
            if S.account then keys[#keys + 1] = "accountBank" end
            for _, key in ipairs(keys) do
                local section = OwnerFor(key).sections[StoredKey(key)]
                if section and section.completeness == "partial" then S.Mark(key) end
            end
        end
    elseif event:match("^ZONE_CHANGED") then
        S.Mark("location")
    elseif event == "PLAYER_MONEY" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE" then
        S.Mark("character")
    end
end)

SLASH_WOWSYNC1 = "/wowsync"
SlashCmdList["WOWSYNC"] = function(argument)
    local raw = tostring(argument or "")
    local command = (raw:match("^%s*(%S*)") or ""):lower()
    if command == "/wowsync" or command == "wowsync" then
        command = (raw:match("^%s*%S+%s+(%S*)") or ""):lower()
    end
    local function say(text) print("WoWSync: " .. text) end
    if command == "status" or command == "stat" then
        local snapshot = S.GetSnapshot and S.GetSnapshot()
        if not snapshot then say(S.error or "Not ready"); return end
        for _, key in ipairs(S.order) do
            local section = key == "accountBank" and snapshot.accountSections and snapshot.accountSections.bank
                or key == "guildBank" and snapshot.guildSections and snapshot.guildSections.bank
                or snapshot.sections[key]
            say(key .. ": " .. (section and section.completeness or "unknown")
                .. ", observed=" .. tostring(section and section.observedAt or "never")
                .. (snapshot.pending[key] and ", pending" or "")
                .. (section and section.lastAttemptError and (", " .. section.lastAttemptError) or ""))
        end
        local latest = S.record and S.record.latestExport
        say("latestExport: generatedAt=" .. tostring(latest and latest.generatedAt or "none")
            .. (S.autoExportPending and ", autoRefreshPending" or "")
            .. (S.lastRenderError and (", renderError=" .. S.lastRenderError) or ""))
        return
    end
    if command == "" or command == "export" or command == "button" then
        if type(S.SlashExport) == "function" and command ~= "button" then S.SlashExport(); return end
        if type(S.SlashButton) == "function" and command == "button" then S.SlashButton(); return end
        say("Core loaded. Export UI missing - use /wowsync status. Try /gearx as a load check.")
        return
    end
    say("Unknown [" .. raw .. "]. Try /wowsync status")
end
