local _, addon = ...
local S, readers = addon.Sync, addon.Readers

local function Optional(fn, ...)
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

function S.Item(link, itemID)
    itemID = itemID or (link and tonumber(link:match("item:(%d+)")))
    local item = { itemID = itemID, itemString = link and link:match("(item:[^|]+)") }
    local name, _, quality, level, requiredLevel, _, _, _, _, _, vendor = GetItemInfo(link or itemID)
    item.name, item.quality, item.itemLevel, item.requiredLevel = name, quality, level, requiredLevel
    item.vendorCopper = vendor
    return item
end

S.collectors.character = function()
    local _, class = UnitClass("player")
    local version, build, _, interface = GetBuildInfo()
    local data = { name = UnitName("player"), realm = GetRealmName(), class = class,
        level = UnitLevel("player"), faction = Optional(UnitFactionGroup, "player"),
        moneyCopper = GetMoney(), xp = Optional(UnitXP, "player"), xpMax = Optional(UnitXPMax, "player"),
        clientVersion = version, clientBuild = build, interface = interface }
    if not data.name or not class or data.level < 1 then return nil, { reason = "Character not ready", retry = true } end
    return data
end

S.collectors.location = function()
    local mapID = C_Map and Optional(C_Map.GetBestMapForUnit, "player")
    local position = mapID and Optional(C_Map.GetPlayerMapPosition, mapID, "player")
    local x, y
    if position then x, y = position:GetXY() end
    return { zone = Optional(GetRealZoneText), subzone = Optional(GetSubZoneText), mapID = mapID,
        x = x and math.floor(x * 10000 + 0.5) / 100, y = y and math.floor(y * 10000 + 0.5) / 100 }
end

local function Containers(bank)
    if bank and not S.bankOpen then return nil, { reason = "Bank closed" } end
    local api = C_Container or {}
    local slots = api.GetContainerNumSlots or GetContainerNumSlots
    local freeSlots = api.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not slots or not (api.GetContainerItemInfo or GetContainerItemInfo) then
        return nil, { reason = "Container APIs unavailable" }
    end
    local bags = {}
    if bank then
        bags[1] = BANK_CONTAINER or -1
        for bag = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7) do bags[#bags + 1] = bag end
    else
        for bag = 0, NUM_BAG_SLOTS or 4 do bags[#bags + 1] = bag end
    end
    local data = { containers = {} }
    local incomplete, locked = false, false
    for _, bag in ipairs(bags) do
        local count = slots(bag)
        if count == nil or ((bag == 0 or bag == (BANK_CONTAINER or -1)) and count == 0) then
            return nil, { reason = "Container capacity not ready", retry = true }
        end
        local free, family
        if freeSlots then free, family = freeSlots(bag) end
        local container = { id = bag, capacity = count, free = free, family = family, slots = {} }
        local inventoryID = bag > 0 and Optional(api.ContainerIDToInventoryID or ContainerIDToInventoryID, bag)
        if bag > 0 and inventoryID then
            local link = GetInventoryItemLink("player", inventoryID)
            local equipped = link or Optional(GetInventoryItemID, "player", inventoryID)
                or Optional(GetInventoryItemTexture, "player", inventoryID)
            if equipped and count == 0 then
                return nil, { reason = "Equipped bag capacity pending", retry = true }
            end
            if link then container.bag = S.Item(link); if not container.bag.name then incomplete = true end end
            if not link and count > 0 then incomplete = true end
        end
        local occupied = 0
        for slot = 1, count do
            local info
            if api.GetContainerItemInfo then
                info = api.GetContainerItemInfo(bag, slot)
            else
                local texture, quantity, isLocked, quality, _, _, link = GetContainerItemInfo(bag, slot)
                link = link or Optional(GetContainerItemLink, bag, slot)
                if texture or link then info = { stackCount = quantity, isLocked = isLocked, quality = quality, hyperlink = link } end
            end
            if info then
                occupied = occupied + 1
                local link = info.hyperlink or Optional(api.GetContainerItemLink or GetContainerItemLink, bag, slot)
                local id = info.itemID or link and tonumber(link:match("item:(%d+)"))
                if not id or not info.stackCount then return nil, { reason = "Item identity/quantity pending", retry = true } end
                local item = S.Item(link, id)
                item.count, item.bound = info.stackCount, info.isBound
                container.slots[slot] = item
                if not item.name or not item.itemString then incomplete = true end
                if info.isLocked then locked = true end
            end
        end
        if free ~= nil and occupied ~= count - free then
            return nil, { reason = "Container contents still settling", retry = true }
        end
        data.containers[#data.containers + 1] = container
    end
    if locked or GetCursorInfo() then return nil, { reason = "Inventory movement in progress", retry = true } end
    if bank then
        data.visit = S.Copy(S.record.visits.bank)
        data.purchasedBagSlots = Optional(GetNumBankSlots)
    end
    return data, { completeness = incomplete and "partial" or "complete",
        reason = incomplete and "Item metadata pending" or nil, retry = incomplete }
end
S.collectors.bags = function() return Containers(false) end
S.collectors.bank = function() return Containers(true) end

S.collectors.equipment = function()
    local data, incomplete = { slots = {} }, false
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        local id = Optional(GetInventoryItemID, "player", slot)
        if link or id then
            local item = S.Item(link, id)
            if link then
                local ready
                item.stats, ready = readers.EquipmentStats(link, slot)
                if not ready then incomplete = true end
            end
            data.slots[slot] = item
            if not link or not item.name then incomplete = true end
        elseif (Optional(GetInventoryItemTexture, "player", slot)) then
            return nil, { reason = "Equipment identity pending", retry = true }
        end
    end
    return data, { completeness = incomplete and "partial" or "complete",
        reason = incomplete and "Item metadata or equipped tooltip pending" or nil, retry = incomplete }
end

S.collectors.professions = function()
    if not GetNumSkillLines or not GetSkillLineInfo or not GetSpellTabInfo or not GetSpellBookItemName then
        return nil, { reason = "Classic skill/spellbook APIs unavailable" }
    end
    if GetNumSkillLines() == 0 then return nil, { reason = "Skill lines not ready", retry = true } end
    local _, _, offset, count = GetSpellTabInfo(1)
    if offset == nil or count == nil then return nil, { reason = "General spellbook not ready", retry = true } end
    local entries, collapsed = readers.Professions()
    table.sort(entries, function(a, b) return a.name < b.name end)
    return { entries = entries, identification = "abandonable skill lines and ranked General spells" },
        { completeness = collapsed and "partial" or "complete", reason = collapsed and "Collapsed skill headers; visible skills only" or nil }
end

S.collectors.spells = function()
    if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellBookItemName then
        return nil, { reason = "Classic spellbook enumeration unavailable" }
    end
    local entries, seen, incomplete = {}, {}, false
    local tabs = GetNumSpellTabs()
    if not tabs or tabs == 0 then return nil, { reason = "Spellbook not ready", retry = true } end
    for tab = 1, tabs do
        local _, _, offset, count = GetSpellTabInfo(tab)
        if not offset or not count then return nil, { reason = "Spellbook tab not ready", retry = true } end
        for index = offset + 1, offset + count do
            local name, rank = GetSpellBookItemName(index, BOOKTYPE_SPELL)
            local kind, id = Optional(GetSpellBookItemInfo, index, BOOKTYPE_SPELL)
            local link = Optional(GetSpellLink, index, BOOKTYPE_SPELL)
            id = link and tonumber(link:match("spell:(%d+)")) or (kind == "SPELL" and id or nil)
            if name then
                local key = id and tostring(id) or name .. "\031" .. (rank or "")
                if not seen[key] then
                    entries[#entries + 1] = { spellID = id, name = name, rank = rank, kind = kind }
                    seen[key] = true
                end
                if not id then incomplete = true end
            else incomplete = true end
        end
    end
    table.sort(entries, function(a, b)
        if a.spellID ~= b.spellID then return (a.spellID or math.huge) < (b.spellID or math.huge) end
        if a.name ~= b.name then return a.name < b.name end
        return (a.rank or "") < (b.rank or "")
    end)
    return { entries = entries, coverage = "player spellbook; exposed ranks; excludes recipe catalogues and pet spellbook" },
        { completeness = incomplete and "partial" or "complete", reason = incomplete and "Some spell identities pending" or nil, retry = incomplete }
end

S.collectors.trainer = function()
    if not S.trainerOpen then return nil, { reason = "Trainer closed" } end
    local report = readers.Trainer(function(service, index)
        local skill, rank, met = Optional(GetTrainerServiceSkillReq, index)
        if skill then service.skillRequirement = { name = skill, rank = rank, met = met } end
        local requirements = Optional(GetTrainerServiceNumAbilityReq, index)
        if requirements and requirements > 0 then
            service.abilityRequirements = {}
            for req = 1, requirements do
                local name, has = Optional(GetTrainerServiceAbilityReq, index, req)
                service.abilityRequirements[#service.abilityRequirements + 1] = { name = name, met = has }
            end
        end
        -- Service indices are UI positions, never stable spell IDs. No name guessing.
    end)
    if not report then return nil, { reason = "Trainer UI/data not ready", retry = true } end
    local filters, collapsed, missing = {}, false, false
    for _, status in ipairs({ "available", "unavailable", "used" }) do
        filters[status] = Optional(GetTrainerServiceTypeFilter, status)
    end
    for index = 1, GetNumTrainerServices() do
        local name, _, kind, expanded = GetTrainerServiceInfo(index)
        if not name then missing = true end
        if kind == "header" and not expanded then collapsed = true end
    end
    for _, service in ipairs(report.services) do
        if service.cost == nil or service.requiredLevel == nil then missing = true end
    end
    table.sort(report.services, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if (a.rank or "") ~= (b.rank or "") then return (a.rank or "") < (b.rank or "") end
        if (a.status or "") ~= (b.status or "") then return (a.status or "") < (b.status or "") end
        return (a.cost or -1) < (b.cost or -1)
    end)
    local data = { visit = S.Copy(S.record.visits.trainer), name = report.trainer.name,
        trainerType = report.trainer.type, services = report.services, filters = filters,
        collapsed = collapsed, moneyAtVisit = report.character.money, coverage = "visible filtered services; spell IDs unavailable" }
    -- A zero-row response can mean filtered-out entries OR data still arriving.
    local empty = #report.services == 0
    local complete = not missing and not empty and not collapsed and filters.available and filters.unavailable and filters.used
    return data, { completeness = complete and "complete" or "partial",
        reason = missing and "Trainer fields pending" or empty and "No visible services; completeness unknown"
            or not complete and "Filtered/collapsed trainer list" or nil,
        retry = missing or empty }
end
