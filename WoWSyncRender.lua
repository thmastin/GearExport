-- Pure renderers: no WoW APIs, clocks, database writes, or scans. A frozen
-- snapshot renders identically, and each section can be rendered independently.
local _, addon = ...
local S = addon.Sync
local labels = { character = "CHARACTER", location = "LOCATION", equipment = "EQUIPMENT",
    bags = "BAGS", bank = "BANK", accountBank = "ACCOUNT BANK", guildBank = "GUILD BANK", professions = "PROFESSIONS", spells = "KNOWN SPELLS", trainer = "TRAINERS" }

local function Text(value)
    if value == nil then return "?" end
    if type(value) == "boolean" then return value and "yes" or "no" end
    local text = tostring(value):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\r", "\\r"):gsub("\n", "\\n")
    return text
end
local function Row(out, ...)
    local row = {}
    for index = 1, select("#", ...) do row[index] = Text(select(index, ...)) end
    out[#out + 1] = table.concat(row, "\t")
end
local function Field(out, key, value) out[#out + 1] = key .. ": " .. Text(value) end
local function SortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
local function Ref(item) return item.itemString or (item.itemID and "item:" .. item.itemID) end
local function Stats(item)
    local parts = {}
    for _, stat in ipairs(item.stats or {}) do parts[#parts + 1] = stat.name .. "=" .. tostring(stat.value) end
    return #parts > 0 and table.concat(parts, "; ") or nil
end

local renderers = {}
renderers.character = function(out, data)
    Field(out, "Name", data.name); Field(out, "Realm", data.realm)
    Field(out, "Class", data.class); Field(out, "Level", data.level)
    Field(out, "Faction", data.faction); Field(out, "MoneyCopper", data.moneyCopper)
    Field(out, "PlayedSeconds", data.playedSeconds)
    Field(out, "LevelPlayedSeconds", data.levelPlayedSeconds)
    if data.xp and data.xpMax and data.xpMax > 0 then Field(out, "XP", data.xp .. "/" .. data.xpMax) end
    if data.clientFamily == "Forever" and (data.xp == nil or data.xpMax == nil) then
        Field(out, "XP", Text(data.xp) .. "/" .. Text(data.xpMax))
    end
    Field(out, "Client", (data.clientVersion or "?") .. " build " .. (data.clientBuild or "?"))
    if data.clientFamily then Field(out, "ClientFamily", data.clientFamily); Field(out, "Interface", data.interface) end
end
renderers.location = function(out, data)
    Field(out, "Zone", data.zone)
    if data.subzone and data.subzone ~= "" then Field(out, "Subzone", data.subzone) end
    if data.mapID then Field(out, "MapID", data.mapID) end
    if data.x and data.y then Field(out, "PositionPercent", data.x .. "," .. data.y) end
end
renderers.equipment = function(out, data)
    Row(out, "slot", "itemRef", "name", "ilvl", "requiredLevel", "effectiveStats")
    for slot = 1, 19 do
        local item = data.slots[slot]
        local label = slot .. ":" .. (addon.Readers.SlotNames[slot] or "")
        if item then Row(out, label, Ref(item), item.name, item.itemLevel, item.requiredLevel, Stats(item))
        else Row(out, label, "EMPTY") end
    end
end

local function Inventory(out, data)
    local groups, rows, total, free = {}, {}, 0, 0
    local containers = {}
    for _, container in ipairs(data.containers) do containers[#containers + 1] = container end
    table.sort(containers, function(a, b) return a.id < b.id end)
    Row(out, "container", "capacity", "free", "family", "bagRef")
    for _, container in ipairs(containers) do
        if container.storage then Field(out, "ContainerStorage " .. container.id, container.storage) end
        total = total + container.capacity
        if container.free == nil then free = nil elseif free then free = free + container.free end
        Row(out, container.id, container.capacity, container.free, container.family,
            container.bag and Ref(container.bag) or "-")
        for _, slot in ipairs(SortedKeys(container.slots)) do
            local item = container.slots[slot]
            -- Keep binding and metadata distinctions; never collapse item variants.
            local key = table.concat({ Ref(item) or "?", Text(item.bound), Text(item.name), Text(item.vendorCopper) }, "\031")
            local entry = groups[key]
            if not entry then entry = { item = item, count = 0, key = key }; groups[key] = entry; rows[#rows + 1] = entry end
            entry.count = entry.count + item.count
        end
    end
    Field(out, "Slots", Text(free) .. " free / " .. total)
    table.sort(rows, function(a, b)
        if a.item.itemID ~= b.item.itemID then return (a.item.itemID or 0) < (b.item.itemID or 0) end
        return a.key < b.key
    end)
    Row(out, "itemRef", "name", "qty", "bound", "vendorEachCopper")
    for _, entry in ipairs(rows) do Row(out, Ref(entry.item), entry.item.name, entry.count, entry.item.bound, entry.item.vendorCopper) end
    if #rows == 0 and data.emptyKnown ~= false then Field(out, "Items", "EMPTY") end
end
renderers.bags = Inventory
renderers.bank = function(out, data)
    if data.coverage then Field(out, "Coverage", data.coverage) end
    if data.visit then Field(out, "SnapshotVisit", data.visit.openedAt) end
    if data.purchasedBagSlots then Field(out, "PurchasedBankBagSlots", data.purchasedBagSlots) end
    if data.purchasedTabs then Field(out, "PurchasedBankTabs", data.purchasedTabs) end
    Inventory(out, data)
end
renderers.accountBank = function(out, data)
    Field(out, "Scope", data.ownerScope or "ACCOUNT_WARBAND")
    if data.coverage then Field(out, "Coverage", data.coverage) end
    if data.visit then Field(out, "SnapshotVisit", data.visit.openedAt) end
    if data.purchasedTabs then Field(out, "PurchasedBankTabs", data.purchasedTabs) end
    Inventory(out, data)
end
renderers.guildBank = function(out, data)
    Field(out, "Scope", data.ownerScope or "GUILD")
    local guild = data.guild or {}
    Field(out, "GuildClubID", guild.clubID)
    Field(out, "GuildName", guild.name)
    if data.coverage then Field(out, "Coverage", data.coverage) end
    if data.visit then Field(out, "SnapshotVisit", data.visit.openedAt) end
    Row(out, "tab", "name", "viewable", "state", "note")
    for _, tab in ipairs(data.tabs or {}) do Row(out, tab.id, tab.name, tab.canView, tab.state, tab.reason) end
    Inventory(out, data)
end
renderers.professions = function(out, data)
    if data.coverage then Field(out, "Coverage", data.coverage) end
    if data.retail then
        Row(out, "profession", "skill", "maxSkill", "skillLineID", "tier", "expansion", "category")
        for _, entry in ipairs(data.entries) do Row(out, entry.name, entry.rank, entry.maxRank,
            entry.skillLineID, entry.tier, entry.expansion, entry.category) end
        if #data.entries == 0 then Field(out, "Professions", "None exposed by tracked profession APIs") end
        return
    end
    Row(out, "profession", "skill", "maxSkill")
    for _, entry in ipairs(data.entries) do Row(out, entry.name, entry.rank, entry.maxRank) end
    if #data.entries == 0 then Field(out, "Professions", "None identified in exposed skill lines") end
end
renderers.spells = function(out, data)
    Field(out, "Coverage", data.coverage)
    Row(out, "spellID", "name", "rank")
    for _, entry in ipairs(data.entries) do Row(out, entry.spellID, entry.name, entry.rank or "-") end
end
local function Requirements(service)
    local parts = {}
    if service.skillRequirement then
        local skill = service.skillRequirement
        parts[#parts + 1] = (skill.name or "?") .. " " .. Text(skill.rank) .. " met=" .. Text(skill.met)
    end
    for _, requirement in ipairs(service.abilityRequirements or {}) do
        parts[#parts + 1] = (requirement.name or "?") .. " met=" .. Text(requirement.met)
    end
    return #parts > 0 and table.concat(parts, "; ") or "-"
end
local function RenderTrainerSnapshot(out, category, data, visit, active)
    out[#out + 1] = "[" .. Text(category) .. "]"
    local state = active and "OBSERVED" or "LAST_SEEN"
    Field(out, "State", state .. "; " .. Text(data.completeness) .. "; observed=" .. Text(data.observedAt))
    if data.reason then Field(out, "CoverageNote", data.reason) end
    if visit then
        Field(out, "LastVisit", visit.openedAt)
        if visit.name then Field(out, "VisitedNPC", visit.name) end
        if visit.location and visit.location.zone then Field(out, "VisitedZone", visit.location.zone) end
        if visit.unreconciled then Field(out, "VisitStatus", "Closed before capture settled") end
    end
    Field(out, "Name", data.name); Field(out, "Type", data.trainerType)
    Field(out, "Coverage", data.coverage)
    local filter = data.filters or {}
    Field(out, "Filters", "available=" .. Text(filter.available) .. "; unavailable=" .. Text(filter.unavailable) .. "; known=" .. Text(filter.used))
    Field(out, "MoneyAtVisitCopper", data.moneyAtVisit)
    Row(out, "spellID", "ability", "rank", "statusAtVisit", "requiredLevel", "costCopper", "requirementsAtVisit")
    for _, service in ipairs(data.services) do
        Row(out, service.spellID, service.name, service.rank or "-", service.status, service.requiredLevel, service.cost, Requirements(service))
    end
end

renderers.trainer = function(out, data, snapshot)
    local snapshots = data.snapshots or {}
    local visits = snapshot.visits and snapshot.visits.trainers or {}
    for _, category in ipairs(SortedKeys(snapshots)) do
        local current = snapshots[category]
        local visit = visits[category] or current.visit
        local active = snapshot.access and snapshot.access.trainer
            and snapshot.access.trainerCategory == category
            and visit and current.visit and visit.session == current.visit.session
        RenderTrainerSnapshot(out, category, current, visit, active)
    end
end

local function RenderTrainerSection(snapshot, section)
    local out = { "[TRAINERS]" }
    if not section or not section.data or type(section.data.snapshots) ~= "table"
        or not next(section.data.snapshots) then
        Field(out, "State", "UNKNOWN")
        Field(out, "Reason", section and section.lastAttemptError or "Not observed")
        return table.concat(out, "\n")
    end
    local categories = SortedKeys(section.data.snapshots)
    Field(out, "State", "OBSERVED; categories=" .. #categories .. "; observed=" .. Text(section.observedAt))
    if section.reason then Field(out, "CoverageNote", section.reason) end
    renderers.trainer(out, section.data, snapshot)
    return table.concat(out, "\n")
end

function S.RenderSection(key, snapshot)
    if not renderers[key] then return nil, "Unknown section: " .. tostring(key) end
    if key == "trainer" then
        return RenderTrainerSection(snapshot, snapshot.sections and snapshot.sections.trainer)
    end
    local out = { "[" .. labels[key] .. "]" }
    local section = key == "accountBank" and snapshot.accountSections and snapshot.accountSections.bank
        or key == "guildBank" and snapshot.guildSections and snapshot.guildSections.bank
        or snapshot.sections and snapshot.sections[key]
    local visit = (key == "accountBank" or key == "guildBank") and section and section.data and section.data.visit
        or snapshot.visits and snapshot.visits[key]
    if visit then
        Field(out, "LastVisit", visit.openedAt)
        if visit.name then Field(out, "VisitedNPC", visit.name) end
        if visit.location and visit.location.zone then Field(out, "VisitedZone", visit.location.zone) end
        if visit.unreconciled then Field(out, "VisitStatus", "Closed before capture settled") end
    end
    if not section or not section.data then
        Field(out, "State", "UNKNOWN")
        if key == "accountBank" then Field(out, "Scope", "ACCOUNT_WARBAND") end
        if key == "guildBank" then Field(out, "Scope", "GUILD") end
        Field(out, "Reason", section and section.lastAttemptError or key == "guildBank" and snapshot.guildError or "Not observed")
        return table.concat(out, "\n")
    end
    local access = key == "bank" or key == "accountBank" or key == "guildBank" or key == "trainer"
    local sameVisit = not access or visit and section.data.visit and visit.openedAt == section.data.visit.openedAt
        and visit.session == section.data.visit.session
    local stale = section.lastAttemptStale or access and not (snapshot.access and snapshot.access[key] and sameVisit)
    local state = stale and "LAST_SEEN" or "OBSERVED"
    Field(out, "State", state .. "; " .. section.completeness .. "; observed=" .. Text(section.observedAt))
    if snapshot.pending and snapshot.pending[key] then Field(out, "Pending", "Refresh pending; showing last observation") end
    if section.reason then Field(out, "CoverageNote", section.reason) end
    if section.lastAttemptError then Field(out, "RefreshIssue", section.lastAttemptError) end
    renderers[key](out, section.data)
    return table.concat(out, "\n")
end

function S.Render(snapshot, sections)
    assert(type(snapshot) == "table" and snapshot.schemaVersion == 1, "Unsupported WoWSync snapshot")
    local out = { "WOWSYNC v1", "Generated: " .. Text(snapshot.generatedAt),
        "Format: tab-separated columns; ?=unknown; timestamps=Unix seconds; money=copper; itemRef preserves item variants." }
    for _, key in ipairs(sections or S.order) do
        local text, err = S.RenderSection(key, snapshot)
        assert(text, err)
        out[#out + 1] = text
    end
    out[#out + 1] = "[END]"
    return table.concat(out, "\n\n")
end
