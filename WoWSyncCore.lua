-- Observation only. No inventory/trainer action APIs belong in WoWSync.
local ADDON_NAME, addon = ...
local S = { apiVersion = 1, schemaVersion = 1, collectors = {}, dirty = {},
    order = { "character", "location", "equipment", "bags", "bank", "professions", "spells", "trainer" },
    bankOpen = false, trainerOpen = false, sessions = { bank = 0, trainer = 0 } }
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

function S.Initialize()
    if S.record then return true end
    if WoWSyncDB ~= nil and (type(WoWSyncDB) ~= "table"
        or (WoWSyncDB.schemaVersion ~= nil and WoWSyncDB.schemaVersion ~= 1)) then
        S.error = "Unsupported WoWSync database; existing data was preserved."
        return false
    end
    local guid = UnitGUID("player")
    if not guid then return false end
    WoWSyncDB = WoWSyncDB or {}
    local db = WoWSyncDB
    db.schemaVersion = 1
    db.settings = type(db.settings) == "table" and db.settings or {}
    db.characters = type(db.characters) == "table" and db.characters or {}
    local record = db.characters[guid]
    if type(record) ~= "table" then record = {}; db.characters[guid] = record end
    record.identity = { guid = guid, name = UnitName("player"), realm = GetRealmName() }
    record.sections = type(record.sections) == "table" and record.sections or {}
    record.visits = type(record.visits) == "table" and record.visits or {}
    S.record = record
    S.settings = db.settings
    S.error = nil
    return true
end

function S.Commit(key, data, meta)
    local old = S.record.sections[key]
    local now = S.Now()
    local changed = not old or not Equal(old.data, data)
    S.record.sections[key] = { data = data, observedAt = now,
        changedAt = changed and now or old.changedAt,
        revision = ((old and old.revision) or 0) + (changed and 1 or 0),
        completeness = meta.completeness or "complete", reason = meta.reason,
        source = meta.source or "client", capture = S.capture }
end

function S.Attempt(key, reason)
    local old = S.record.sections[key]
    if not old then old = { completeness = "unknown", revision = 0 }; S.record.sections[key] = old end
    old.lastAttemptAt, old.lastAttemptError = S.Now(), reason
end

function S.Mark(key, delay)
    if not S.collectors[key] then return end
    if key == "bank" and not S.bankOpen or key == "trainer" and not S.trainerOpen then return end
    local now = GetTime()
    local pending = S.dirty[key]
    if not pending then pending = { first = now, tries = 0 }; S.dirty[key] = pending end
    pending.due = math.min(now + (delay or 0.35), pending.first + 1.5)
    S.Wake()
end

function S.RequestSync()
    if not S.Initialize() then return false, S.error or "Character is not ready yet." end
    for _, key in ipairs(S.order) do S.Mark(key, 0.15) end
    return true
end

function S.GetSnapshot()
    if not S.Initialize() then return nil end
    local snapshot = { identity = S.Copy(S.record.identity), sections = S.Copy(S.record.sections),
        visits = S.Copy(S.record.visits) }
    snapshot.schemaVersion = S.schemaVersion
    snapshot.generatedAt = S.Now()
    snapshot.access = { bank = S.bankOpen, trainer = S.trainerOpen }
    snapshot.pending = {}
    for key in pairs(S.dirty) do snapshot.pending[key] = true end
    return snapshot
end

function S.GetSection(key)
    if not S.Initialize() then return nil end
    return S.Copy(S.record.sections[key])
end

local frame = CreateFrame("Frame")
S.eventFrame = frame
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
            if ok and data then S.Commit(key, data, meta)
            else S.Attempt(key, meta.reason or "Data unavailable") end
            if meta.retry and not force and pending.tries < 4
                and (key ~= "bank" or S.bankOpen) and (key ~= "trainer" or S.trainerOpen) then
                pending.tries = pending.tries + 1
                pending.due = now + 0.5
                S.dirty[key] = pending
            end
        end
    end
end
S.Process = Process

local function Tick()
    Process(false)
    if S.exportRequest and (not next(S.dirty) or GetTime() >= S.exportRequest.deadline) then
        local callback = S.exportRequest.callback
        S.exportRequest = nil
        local snapshot = S.GetSnapshot()
        if snapshot then
            local text = S.Render(snapshot)
            S.record.latestExport = { text = text, generatedAt = snapshot.generatedAt }
            callback(text)
        end
    end
    if not next(S.dirty) and not S.exportRequest then frame:SetScript("OnUpdate", nil) end
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
    S.record.visits[key] = { openedAt = S.Now(), location = ok and location or nil,
        name = UnitName("npc"), guid = UnitGUID("npc"), session = S.sessions[key] }
end

local function Close(key)
    if not S.record then return end
    local visit = S.record.visits[key]
    local section = S.record.sections[key]
    if visit then
        visit.closedAt = S.Now()
        visit.unreconciled = S.dirty[key] ~= nil or not section or not section.data
            or section.lastAttemptError ~= nil
    end
    if S.dirty[key] then S.Attempt(key, "Closed before pending capture settled") end
    S.dirty[key] = nil
end

local events = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_DESCRIPTION_UPDATE",
    "TRAINER_SERVICE_INFO_NAME_UPDATE", "TRAINER_CLOSED",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "SKILL_LINES_CHANGED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_MONEY", "PLAYER_LEVEL_UP",
    "PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "GET_ITEM_INFO_RECEIVED",
}
S.unsupportedEvents = {}
for _, event in ipairs(events) do
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then S.unsupportedEvents[event] = true end
end

frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == ADDON_NAME then S.Initialize(); if S.InitializeUI then S.InitializeUI() end end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        S.RequestSync(); if S.InitializeUI then S.InitializeUI() end
    elseif event == "PLAYER_LOGOUT" then
        if S.record then Process(true) end
    elseif event == "BANKFRAME_OPENED" then
        S.bankOpen = true; Visit("bank"); S.Mark("bank"); S.Mark("bags")
    elseif event == "BANKFRAME_CLOSED" then
        S.bankOpen = false; Close("bank"); S.Mark("bags")
    elseif event == "TRAINER_SHOW" then
        S.trainerOpen = true; Visit("trainer"); S.Mark("trainer"); S.Mark("spells")
    elseif event == "TRAINER_CLOSED" then
        S.trainerOpen = false; Close("trainer")
    elseif event:match("^TRAINER_") then
        S.Mark("trainer")
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED"
        or event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        S.Mark("bags"); S.Mark("bank")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" and arg == "player" then
        S.Mark("equipment"); S.Mark("bags")
    elseif event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        S.Mark("professions"); S.Mark("spells"); S.Mark("trainer")
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if S.record then
            for _, key in ipairs({ "bags", "bank", "equipment" }) do
                local section = S.record.sections[key]
                if section and section.completeness == "partial" then S.Mark(key) end
            end
        end
    elseif event:match("^ZONE_CHANGED") then
        S.Mark("location")
    elseif event == "PLAYER_MONEY" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE" then
        S.Mark("character")
    end
end)
