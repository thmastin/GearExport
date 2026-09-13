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
        local count, result = api.GetNumSpellBookSkillLines(), {}
        if not count or count == 0 then return nil, "Spellbook not ready" end
        for tab = 1, count do
            local info = api.GetSpellBookSkillLineInfo(tab)
            if not info or not info.itemIndexOffset or not info.numSpellBookItems then return nil, "Spellbook skill line pending" end
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
