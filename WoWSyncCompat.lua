-- Small client-compatibility surface shared by the TBC and Classic Era TOCs.
-- This file only observes data. It must not call gameplay/action APIs.
local C = WoWSyncCompat or {}
WoWSyncCompat = C

local function Optional(fn, ...)
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

function C.GetContainerSlotCount(bag)
    local api = C_Container
    local fn = api and api.GetContainerNumSlots or GetContainerNumSlots
    return Optional(fn, bag)
end

function C.GetContainerFreeSlots(bag)
    local api = C_Container
    local fn = api and api.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if type(fn) ~= "function" then return nil, nil end
    return fn(bag)
end

function C.GetContainerLink(bag, slot)
    local api = C_Container
    local fn = api and api.GetContainerItemLink or GetContainerItemLink
    return Optional(fn, bag, slot)
end

function C.GetContainerInfo(bag, slot)
    local api = C_Container
    if api and type(api.GetContainerItemInfo) == "function" then
        return api.GetContainerItemInfo(bag, slot)
    end
    if type(GetContainerItemInfo) ~= "function" then return nil end
    local texture, quantity, isLocked, quality, _, _, link = GetContainerItemInfo(bag, slot)
    link = link or C.GetContainerLink(bag, slot)
    if not texture and not link then return nil end
    return { stackCount = quantity, isLocked = isLocked, quality = quality, hyperlink = link }
end

function C.GetContainerBagIdentity(bag)
    if bag <= 0 then return nil end
    local api = C_Container
    local inventoryID = Optional(api and api.ContainerIDToInventoryID or ContainerIDToInventoryID, bag)
    if not inventoryID then return nil end
    local link = Optional(GetInventoryItemLink, "player", inventoryID)
    return link, Optional(GetInventoryItemID, "player", inventoryID),
        Optional(GetInventoryItemTexture, "player", inventoryID)
end

function C.GetBankRanges()
    local bagSlots, bankSlots = NUM_BAG_SLOTS or 4, NUM_BANKBAGSLOTS or 7
    local bags, bank = {}, {}
    for bag = 0, bagSlots do bags[#bags + 1] = bag end
    bank[#bank + 1] = BANK_CONTAINER or -1
    for bag = bagSlots + 1, bagSlots + bankSlots do bank[#bank + 1] = bag end
    return bags, bank
end

function C.EnumerateSpellbook()
    if type(GetNumSpellTabs) ~= "function" or type(GetSpellTabInfo) ~= "function"
        or type(GetSpellBookItemName) ~= "function" then
        return nil, "Spellbook APIs unavailable"
    end
    local tabs, result = GetNumSpellTabs(), {}
    if not tabs or tabs == 0 then return nil, "Spellbook not ready" end
    for tab = 1, tabs do
        local name, texture, offset, count = GetSpellTabInfo(tab)
        if offset == nil or count == nil then return nil, "Spellbook tab not ready" end
        local tabData = { index = tab, name = name, texture = texture, offset = offset,
            count = count, entries = {} }
        for index = offset + 1, offset + count do
            local spellName, rank = GetSpellBookItemName(index, BOOKTYPE_SPELL)
            local kind, spellID = Optional(GetSpellBookItemInfo, index, BOOKTYPE_SPELL)
            local link = Optional(GetSpellLink, index, BOOKTYPE_SPELL)
            spellID = link and tonumber(link:match("spell:(%d+)"))
                or (kind == "SPELL" and spellID or nil)
            tabData.entries[#tabData.entries + 1] = { index = index, name = spellName,
                rank = rank, kind = kind, spellID = spellID, link = link }
        end
        result[#result + 1] = tabData
    end
    return result
end

function C.GetProfessionSpellEvidence()
    local tabs, err = C.EnumerateSpellbook()
    if not tabs then return nil, err end
    local names = {}
    for _, tab in ipairs(tabs) do
        for _, entry in ipairs(tab.entries) do
            -- Ranked spells are the stable legacy evidence available on both clients.
            if entry.name and entry.rank and entry.rank ~= "" then names[entry.name] = true end
        end
    end
    return names
end

function C.GetTrainerService(index)
    if type(GetTrainerServiceInfo) ~= "function" then return nil end
    local name, subText, serviceType, expanded = GetTrainerServiceInfo(index)
    if not name then return nil end
    local cost = Optional(GetTrainerServiceCost, index)
    local requiredLevel = Optional(GetTrainerServiceLevelReq, index)
    return { name = name, rank = subText, status = serviceType, expanded = expanded,
        cost = tonumber(cost), requiredLevel = tonumber(requiredLevel) }
end

local function CategoryKey(value)
    if not value or value == "" then return nil end
    local key = tostring(value):upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return key ~= "" and key or nil
end

function C.TrainerCategory(report)
    if not report or not report.trainer then return "UNKNOWN" end
    local skillNames, hasSkill = {}, false
    for _, service in ipairs(report.services or {}) do
        local requirement = service.skillRequirement
        if requirement and requirement.name and requirement.name ~= "" then
            hasSkill = true
            skillNames[CategoryKey(requirement.name)] = true
        end
    end
    local skillKeys = {}
    for key in pairs(skillNames) do skillKeys[#skillKeys + 1] = key end
    table.sort(skillKeys)
    if report.trainer.type == "Trade Skill Trainer" then
        return skillKeys[1] and "PROF_" .. skillKeys[1] or "TRADE"
    end
    if report.trainer.type == "Talent Trainer" then return "CLASS" end
    if hasSkill then return "WEAPON" end
    -- With no visible services or skill requirements, the legacy API does not
    -- expose enough information to distinguish an empty class or weapon trainer.
    -- Preserve the observation without making a category claim.
    return #(report.services or {}) > 0 and "CLASS" or "UNKNOWN"
end

function C.GetLocation()
    local mapID = C_Map and Optional(C_Map.GetBestMapForUnit, "player")
    local position = mapID and Optional(C_Map.GetPlayerMapPosition, mapID, "player")
    local x, y
    if position then x, y = position:GetXY() end
    return { zone = Optional(GetRealZoneText), subzone = Optional(GetSubZoneText), mapID = mapID,
        x = x and math.floor(x * 10000 + 0.5) / 100,
        y = y and math.floor(y * 10000 + 0.5) / 100 }
end

function C.IsItemDataReady(itemID)
    if not itemID or type(GetItemInfo) ~= "function" then return false end
    return GetItemInfo(itemID) ~= nil
end

function C.RegisterOptionalEvents(frame)
    if not frame or type(frame.RegisterEvent) ~= "function" then return {} end
    local registered = {}
    for _, event in ipairs({ "ITEM_DATA_LOAD_RESULT" }) do
        if pcall(frame.RegisterEvent, frame, event) then registered[event] = true end
    end
    return registered
end
