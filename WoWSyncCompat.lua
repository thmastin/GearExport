-- Client differences shared by the TBC, Classic Era and Retail package targets.
-- This file only observes data. It must not call gameplay/action APIs.
local C = WoWSyncCompat or {}
WoWSyncCompat = C

local function Optional(fn, ...)
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

function C.IsRetail()
    return WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

-- Audited on Anniversary, Era and Retail: no arguments or direct return;
-- TIME_PLAYED_MSG supplies total seconds, then seconds at this level.
function C.RequestPlayed()
    if type(RequestTimePlayed) ~= "function" then return false end
    return pcall(RequestTimePlayed)
end

function C.PlayedSeconds(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value < 0
        or value == math.huge or value % 1 ~= 0 then return nil end
    return value
end

function C.GetItemInfo(reference)
    if reference == nil then return nil end
    return Optional(C.IsRetail() and C_Item and C_Item.GetItemInfo or GetItemInfo, reference)
end

function C.GetItemCount(reference, includeBank)
    return Optional(C.IsRetail() and C_Item and C_Item.GetItemCount or GetItemCount, reference, includeBank)
end

function C.GetItemLevel(reference, fallback)
    if not C.IsRetail() then return fallback end
    return Optional(C_Item and C_Item.GetDetailedItemLevelInfo, reference)
end

function C.RequestItemData(itemID)
    if C.IsRetail() and itemID then Optional(C_Item and C_Item.RequestLoadItemDataByID, itemID) end
end

local function Known(value)
    if value == nil then return false end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    return true
end

local function Evidence(value)
    if not Known(value) then return { state = "UNKNOWN" } end
    return { state = "KNOWN", value = value }
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, ...)
    if not ok then return nil, false end
    if not Known(value) then return nil, false end
    return value, true
end

local function ReadEvidence(fn, ...)
    local value, valid = Read(fn, ...)
    if not valid then return { state = "UNKNOWN" } end
    return Evidence(value)
end

local function CandidateLocation(kind, container, slot)
    if not C.IsRetail() or not ItemLocation then return nil end
    local ctor = kind == "equipment" and ItemLocation.CreateFromEquipmentSlot or ItemLocation.CreateFromBagAndSlot
    local ok, location
    if kind == "equipment" then ok, location = pcall(ctor, ItemLocation, slot)
    else ok, location = pcall(ctor, ItemLocation, container, slot) end
    if not ok then return nil end
    return location
end

local function ItemString(link)
    if type(link) ~= "string" then return nil end
    local ok, value = pcall(string.match, link, "(item:[^|]+)")
    return ok and value or nil
end

local function TooltipBinding(kind, container, slot)
    if not C_TooltipInfo then return nil end
    local ok, info
    if kind == "equipment" and type(C_TooltipInfo.GetInventoryItem) == "function" then
        ok, info = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
    elseif kind ~= "equipment" and type(C_TooltipInfo.GetBagItem) == "function" then
        ok, info = pcall(C_TooltipInfo.GetBagItem, container, slot)
    end
    if not ok or type(info) ~= "table" or type(info.lines) ~= "table" then return nil end
    local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemBinding
    if lineType == nil then return nil end
    for _, line in ipairs(info.lines) do
        if type(line) == "table" and line.type == lineType then
            if Known(line.bindingType) then return line.bindingType end
            if Known(line.itemBinding) then return line.itemBinding end
            for _, arg in ipairs(type(line.args) == "table" and line.args or {}) do
                if type(arg) == "table" and (arg.field == "bindingType" or arg.field == "itemBinding")
                    and Known(arg.intVal) then return arg.intVal end
            end
            return nil
        end
    end
    return nil
end

local function TooltipBindingEvidence(kind, container, slot)
    local value = TooltipBinding(kind, container, slot)
    if not Known(value) then return Evidence(nil) end
    local enums = Enum and Enum.TooltipDataItemBinding
    if type(enums) ~= "table" then return { state = "UNKNOWN", rawValue = value } end
    for _, knownValue in pairs(enums) do
        if knownValue == value then return Evidence(value) end
    end
    return { state = "UNKNOWN", rawValue = value }
end

function C.GetGearCandidate(kind, container, slot, itemID, itemLink)
    if not C.IsRetail() then return nil, "not-retail" end
    local location = CandidateLocation(kind, container, slot)
    local locationIdentityValid, locationValid, locatedLink, locatedString = false, false, nil, nil
    if location and Known(itemID) then
        local locatedID, idKnown = Read(C_Item and C_Item.GetItemID, location)
        local exists, existsKnown = Read(C_Item and C_Item.DoesItemExist, location)
        locationIdentityValid = idKnown and locatedID == itemID and existsKnown and exists == true
        locatedLink = Read(C_Item and C_Item.GetItemLink, location)
        locatedString = ItemString(locatedLink)
        local observedString = ItemString(itemLink)
        locationValid = locationIdentityValid and locatedString ~= nil
            and (observedString == nil or observedString == locatedString)
    end
    local exactLocation = locationValid and location or nil
    local itemString = ItemString(itemLink) or (locationValid and locatedString)
    local candidate = {
        candidateState = "UNKNOWN",
        itemID = Evidence(itemID),
        itemString = Evidence(itemString),
        observedLocation = kind == "equipment"
            and { type = "EQUIPMENT_SLOT", slot = slot }
            or { type = kind == "bank" and "BANK_SLOT" or "CONTAINER_SLOT", containerID = container, slot = slot },
        itemGUID = exactLocation and ReadEvidence(C_Item and C_Item.GetItemGUID, exactLocation) or Evidence(nil),
        equipType = exactLocation and ReadEvidence(C_Item and C_Item.GetItemInventoryType, exactLocation) or Evidence(nil),
        currentItemLevel = exactLocation and ReadEvidence(C_Item and C_Item.GetCurrentItemLevel, exactLocation) or Evidence(nil),
        isBound = exactLocation and ReadEvidence(C_Item and C_Item.IsBound, exactLocation) or Evidence(nil),
        boundToAccountUntilEquip = exactLocation and ReadEvidence(C_Item and C_Item.IsBoundToAccountUntilEquip, exactLocation) or Evidence(nil),
        tooltipBindingType = exactLocation and TooltipBindingEvidence(kind, container, slot) or Evidence(nil),
        currentCharacterCanUse = ReadEvidence(C_PlayerInfo and C_PlayerInfo.CanUseItem, itemID),
    }
    local ref = Known(itemLink) and itemLink or (locationValid and locatedLink) or (Known(itemID) and itemID or nil)
    local cached, cacheKnown
    if exactLocation then cached, cacheKnown = Read(C_Item and C_Item.IsItemDataCached, exactLocation) end
    if cacheKnown and cached == false and exactLocation then
        pcall(C_Item and C_Item.RequestLoadItemData, exactLocation)
    end
    local name, link, quality, itemLevel, requiredLevel, itemType, subType,
        stackCount, itemEquipLoc, icon, sellPrice, classID, subclassID = nil
    local infoFn = C_Item and C_Item.GetItemInfo
    if type(infoFn) == "function" and ref then
        local values = { pcall(infoFn, ref) }
        if values[1] then
            name, link, quality, itemLevel, requiredLevel, itemType, subType,
                stackCount, itemEquipLoc, icon, sellPrice, classID, subclassID =
                    values[2], values[3], values[4], values[5], values[6], values[7], values[8],
                    values[9], values[10], values[11], values[12], values[13], values[14]
        end
    end
    candidate.requiredLevel = Evidence(requiredLevel)
    candidate.classID, candidate.subclassID = Evidence(classID), Evidence(subclassID)
    candidate.baseEquipLocation = Evidence(itemEquipLoc)
    candidate.itemBindToAccount = ref and ReadEvidence(C_Item and C_Item.IsItemBindToAccount, ref) or Evidence(nil)
    candidate.itemBindToAccountUntilEquip = ref and ReadEvidence(C_Item and C_Item.IsItemBindToAccountUntilEquip, ref) or Evidence(nil)
    local equippable, equippableKnown = Read(C_Item and C_Item.IsEquippableItem, ref)
    local metadataReady = cacheKnown and cached == true or not cacheKnown and Known(name)
    if equippableKnown and equippable == false and metadataReady then
        return nil, "not-equippable"
    end
    if not locationValid then
        if locationIdentityValid and not locatedString then pcall(C_Item and C_Item.RequestLoadItemData, location) end
        return candidate, "unknown"
    end
    if equippableKnown and equippable == true then candidate.candidateState = "EQUIPPABLE"
    else
        if exactLocation then pcall(C_Item and C_Item.RequestLoadItemData, exactLocation) end
        return candidate, "unknown"
    end
    return candidate, nil
end

function C.CollectGearCandidates()
    if not C.IsRetail() then return nil, false end
    if type(GetCursorInfo) == "function" and GetCursorInfo() then return nil, true end
    local candidates, pending = {}, false
    local function Add(kind, container, slot, id, link)
        local candidate, state = C.GetGearCandidate(kind, container, slot, id, link)
        if state == "unknown" then pending = true end
        if candidate then
            for _, value in pairs(candidate) do
                if type(value) == "table" and value.state == "UNKNOWN" then pending = true end
            end
            candidates[#candidates + 1] = candidate
        end
    end
    local bags, bank = C.GetBankRanges()
    if not bags then return nil, true end
    local bankAccessible = WoWSync and WoWSync.bankOpen and C.IsBankViewable()
    if bankAccessible and not bank then return nil, true end
    if not bankAccessible then bank = nil end
    local function ScanContainers(ids, isBank)
        for _, bag in ipairs(ids or {}) do
            local count = C.GetContainerSlotCount(bag)
            if count == nil or C.ContainerRequiresCapacity(bag, isBank) and count == 0 then return false end
            local free = C.GetContainerFreeSlots(bag)
            local occupied = 0
            for slot = 1, count do
                local info = C.GetContainerInfo(bag, slot)
                if info then
                    occupied = occupied + 1
                    if not Known(info.isLocked) or info.isLocked == true then return false end
                    local link = Known(info.hyperlink) and info.hyperlink or C.GetContainerLink(bag, slot)
                    local id = Known(info.itemID) and info.itemID or tonumber(ItemString(link) and ItemString(link):match("item:(%d+)"))
                    Add(isBank and "bank" or "bag", bag, slot, id, link)
                end
            end
            if free ~= nil and occupied ~= count - free then return false end
        end
        return true
    end
    if not ScanContainers(bags, false) then return nil, true end
    for slot = 1, 19 do
        local link = Optional(GetInventoryItemLink, "player", slot)
        local id = Optional(GetInventoryItemID, "player", slot)
        if Known(link) or Known(id) then Add("equipment", nil, slot, id, link) end
    end
    if bank and not ScanContainers(bank, true) then return nil, true end
    if type(GetCursorInfo) == "function" and GetCursorInfo() then return nil, true end
    table.sort(candidates, function(a, b)
        local x, y = a.observedLocation, b.observedLocation
        if x.type ~= y.type then return x.type < y.type end
        if (x.containerID or -1) ~= (y.containerID or -1) then return (x.containerID or -1) < (y.containerID or -1) end
        return x.slot < y.slot
    end)
    return candidates, pending
end

function C.GetEquipmentStats(link, slot, legacyReader)
    if not C.IsRetail() then return legacyReader(link, slot) end
    local values = Optional(C_Item and C_Item.GetItemStats, link)
    local tooltip = Optional(C_TooltipInfo and C_TooltipInfo.GetInventoryItem, "player", slot)
    local result, missing = {}, false
    for key, value in pairs(values or {}) do
        if not (issecretvalue and issecretvalue(value)) and type(value) == "number" then
            result[#result + 1] = { name = key, value = value }
        else missing = true end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result, not missing and values ~= nil and tooltip ~= nil and tooltip.lines ~= nil and #tooltip.lines > 0
end

function C.GetProfessionState(legacyReader)
    if not C.IsRetail() then
        if not GetNumSkillLines or not GetSkillLineInfo or not GetSpellTabInfo or not GetSpellBookItemName then
            return nil, { reason = "Classic skill/spellbook APIs unavailable" }
        end
        if GetNumSkillLines() == 0 then return nil, { reason = "Skill lines not ready", retry = true } end
        local names, err = C.GetProfessionSpellEvidence()
        if not names and err then return nil, { reason = err, retry = true } end
        local entries, collapsed = legacyReader()
        table.sort(entries, function(a, b) return a.name < b.name end)
        return { entries = entries, identification = "abandonable skill lines and ranked trade-skill spells" },
            { completeness = collapsed and "partial" or "complete", reason = collapsed and "Collapsed skill headers; visible skills only" or nil }
    end
    if not GetProfessions or not GetProfessionInfo then return nil, { reason = "Profession APIs unavailable" } end
    local indices, entries, missing = { GetProfessions() }, {}, false
    -- Sparse tuple: a character can have only fishing or cooking.
    for position = 1, 5 do
        local index = indices[position]
        if index then
            local name, _, rank, maxRank, _, _, skillLine, _, _, _, tier = GetProfessionInfo(index)
            if not name then missing = true else
                local info = skillLine and Optional(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLine)
                entries[#entries + 1] = { name = name, rank = rank, maxRank = maxRank,
                    skillLineID = skillLine, tier = tier,
                    expansion = info and info.expansionName ~= "" and info.expansionName or nil,
                    category = position <= 2 and "PRIMARY" or "SECONDARY" }
                if rank == nil or maxRank == nil then missing = true end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return (a.skillLineID or 0) < (b.skillLineID or 0)
    end)
    return { entries = entries, retail = true,
        coverage = "Tracked primary/secondary professions and exposed tier; historical tier catalogue, recipes and knowledge excluded" },
        { completeness = missing and "partial" or "complete", reason = missing and "Profession fields pending" or nil, retry = missing }
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
    if C.IsRetail() and (not Enum or not Enum.BagIndex or bag > Enum.BagIndex.ReagentBag) then return nil end
    local api = C_Container
    local inventoryID = Optional(api and api.ContainerIDToInventoryID or ContainerIDToInventoryID, bag)
    if not inventoryID then return nil end
    local link = Optional(GetInventoryItemLink, "player", inventoryID)
    return link, Optional(GetInventoryItemID, "player", inventoryID),
        Optional(GetInventoryItemTexture, "player", inventoryID)
end

function C.GetBankRanges()
    if C.IsRetail() then
        if not Enum or not Enum.BagIndex then return nil, nil end
        local bags, bank = {}, nil
        for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do bags[#bags + 1] = bag end
        local kind = Enum.BankType and Enum.BankType.Character
        if kind and C_Bank and Optional(C_Bank.CanViewBank, kind) then
            bank = Optional(C_Bank.FetchPurchasedBankTabIDs, kind)
        end
        return bags, bank
    end
    local bagSlots, bankSlots = NUM_BAG_SLOTS or 4, NUM_BANKBAGSLOTS or 7
    local bags, bank = {}, {}
    for bag = 0, bagSlots do bags[#bags + 1] = bag end
    bank[#bank + 1] = BANK_CONTAINER or -1
    for bag = bagSlots + 1, bagSlots + bankSlots do bank[#bank + 1] = bag end
    return bags, bank
end

function C.IsBankViewable()
    if not C.IsRetail() then return true end
    return C_Bank and Enum and Enum.BankType and Optional(C_Bank.CanViewBank, Enum.BankType.Character) == true or false
end

function C.GetContainerCategory(bag, bank)
    if not C.IsRetail() then return nil end
    return bank and "CHARACTER" or bag == Enum.BagIndex.ReagentBag and "REAGENT_BAG" or "CARRIED"
end

function C.ContainerRequiresCapacity(bag, bank)
    if C.IsRetail() then return bank or bag == Enum.BagIndex.Backpack end
    return bag == 0 or bag == (BANK_CONTAINER or -1)
end

function C.GetBankCoverage()
    if not C.IsRetail() then return nil end
    return "CHARACTER purchased tabs only; ACCOUNT/Warband API-supported but deferred; legacy main bank, bank bags and reagent bank not applicable"
end

function C.GetPurchasedBankSlots()
    if C.IsRetail() then
        return Optional(C_Bank and C_Bank.FetchNumPurchasedBankTabs, Enum.BankType.Character), "tabs"
    end
    return Optional(GetNumBankSlots), "bags"
end

function C.EnumerateSpellbook()
    if C.IsRetail() then
        local api, enum = C_SpellBook, Enum
        if not api or not api.GetNumSpellBookSkillLines or not api.GetSpellBookSkillLineInfo
            or not api.GetSpellBookItemInfo or not enum or not enum.SpellBookItemType or not enum.SpellBookSpellBank then
            return nil, "Retail spellbook APIs unavailable"
        end
        local count, result, ranges = api.GetNumSpellBookSkillLines(), {}, {}
        if not count or count == 0 then return nil, "Spellbook not ready" end
        for tab = 1, count do
            local info = api.GetSpellBookSkillLineInfo(tab)
            if not info or not info.itemIndexOffset or not info.numSpellBookItems then return nil, "Spellbook skill line pending" end
            ranges[#ranges + 1] = info
        end
        -- Retail's separate professions book exposes player-bank slots outside
        -- the class/spec skill lines. These are abilities, not recipe catalogues.
        if not GetProfessions or not GetProfessionInfo then return nil, "Profession spellbook APIs unavailable" end
        local professions = { GetProfessions() }
        for position = 1, 5 do
            if professions[position] then
                local name, _, _, _, spells, offset = GetProfessionInfo(professions[position])
                if spells == nil or offset == nil then return nil, "Profession spellbook pending" end
                if spells > 0 then ranges[#ranges + 1] = { name = name,
                    itemIndexOffset = offset, numSpellBookItems = spells } end
            end
        end
        for tab, info in ipairs(ranges) do
            if not info.offSpecID then
                local group = { name = info.name, index = tab, entries = {} }
                for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = api.GetSpellBookItemInfo(index, enum.SpellBookSpellBank.Player)
                    if not item then return nil, "Spellbook entry pending" end
                    if not item.isOffSpec then
                        if item.itemType == enum.SpellBookItemType.Spell then
                            group.entries[#group.entries + 1] = { name = item.name ~= "" and item.name or nil,
                                spellID = item.spellID and item.spellID > 0 and item.spellID or nil,
                                kind = "SPELL", passive = item.isPassive }
                        elseif item.itemType == enum.SpellBookItemType.Flyout then
                            if not GetFlyoutInfo or not GetFlyoutSlotInfo then return nil, "Flyout APIs unavailable" end
                            local _, _, slots = GetFlyoutInfo(item.actionID)
                            if not slots then return nil, "Flyout data pending" end
                            for slot = 1, slots do
                                local id, override, known, name = GetFlyoutSlotInfo(item.actionID, slot)
                                if known then group.entries[#group.entries + 1] = { name = name,
                                    spellID = override and override > 0 and override or id, kind = "SPELL" } end
                            end
                        end
                    end
                end
                result[#result + 1] = group
            end
        end
        return result
    end
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
    if C.IsRetail() then
        local name, status, _, level = GetTrainerServiceInfo(index)
        if not name then return nil end
        local cost = Optional(GetTrainerServiceCost, index)
        return { name = name, status = status, requiredLevel = tonumber(level),
            cost = tonumber(cost),
            skillLine = Optional(GetTrainerServiceSkillLine, index) }
    end
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
    if C.IsRetail() then
        local keys = {}
        for _, service in ipairs(report.services or {}) do
            local key = CategoryKey(service.skillLine)
            if key then keys[key] = true end
        end
        local result = {}
        for key in pairs(keys) do result[#result + 1] = key end
        table.sort(result)
        if #result > 0 then return "PROF_" .. table.concat(result, "__") end
        if report.trainer.type == "Talent Trainer" then return "CLASS" end
        return "UNKNOWN"
    end
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
    return itemID ~= nil and C.GetItemInfo(itemID) ~= nil
end

function C.RegisterOptionalEvents(frame)
    if not frame or type(frame.RegisterEvent) ~= "function" then return {} end
    local registered = {}
    local events = { "ITEM_DATA_LOAD_RESULT" }
    if C.IsRetail() then
        for _, event in ipairs({ "BANK_TABS_CHANGED",
            "PLAYER_SPECIALIZATION_CHANGED", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE", "SPELL_TEXT_UPDATE" }) do
            events[#events + 1] = event
        end
    end
    for _, event in ipairs(events) do
        if pcall(frame.RegisterEvent, frame, event) then registered[event] = true end
    end
    return registered
end
