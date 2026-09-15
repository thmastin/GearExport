local ADDON_NAME, addon = ...
addon = addon or {}
addon.Readers = addon.Readers or {}

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt",
    [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main Hand",
    [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard",
}

local STAT_SOURCES = {
    { "Strength", "ITEM_MOD_STRENGTH_SHORT" },
    { "Agility", "ITEM_MOD_AGILITY_SHORT" },
    { "Stamina", "ITEM_MOD_STAMINA_SHORT" },
    { "Intellect", "ITEM_MOD_INTELLECT_SHORT" },
    { "Spirit", "ITEM_MOD_SPIRIT_SHORT" },
    { "Armor", "ITEM_MOD_ARMOR_SHORT" },
    { "Spell Power", "ITEM_MOD_SPELL_POWER_SHORT" },
    { "Healing", "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_HEALING_DONE_SHORT", "ITEM_MOD_HEALING_DONE" },
    { "Spell Damage", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE" },
    { "Mana per 5", "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_MANA_REGENERATION" },
    { "Crit Rating", "ITEM_MOD_CRIT_RATING_SHORT" },
    { "Hit Rating", "ITEM_MOD_HIT_RATING_SHORT" },
    { "Haste Rating", "ITEM_MOD_HASTE_RATING_SHORT" },
    { "Attack Power", "ITEM_MOD_ATTACK_POWER_SHORT" },
    { "Ranged Attack Power", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
}

local statScanTooltip

local function EscapePattern(text)
    return text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function GetEquippedTooltipStats(slotID)
    local values = {}
    if not slotID then return values, false end

    statScanTooltip = statScanTooltip or CreateFrame(
        "GameTooltip", "GearExportStatScanTooltip", UIParent, "GameTooltipTemplate"
    )
    statScanTooltip:Hide()
    statScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    statScanTooltip:ClearLines()
    local ok = pcall(statScanTooltip.SetInventoryItem, statScanTooltip, "player", slotID)
    if not ok then return values, false end

    for lineIndex = 2, statScanTooltip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fontString = _G["GearExportStatScanTooltipText" .. side .. lineIndex]
            local text = fontString and fontString:GetText()
            if text then
                text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                for statIndex, stat in ipairs(STAT_SOURCES) do
                    for keyIndex = 2, #stat do
                        local label = _G[stat[keyIndex]]
                        if type(label) == "string" and label ~= "" then
                            local escapedLabel = EscapePattern(label)
                            local amount = text:match("([%+%-]?%d+)%s*" .. escapedLabel)
                                or text:match(escapedLabel .. "%s*([%+%-]?%d+)")
                            amount = tonumber(amount)
                            if amount then
                                values[statIndex] = (values[statIndex] or 0) + amount
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    -- Measure the tooltip we just read, before Hide/cleanup can reset its lines.
    local ready = statScanTooltip:NumLines() > 0
    statScanTooltip:Hide()
    return values, ready
end

local function MarkdownText(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub("|", "\\|"):gsub("[\r\n]+", " ")
    return value
end

local function FormatMoney(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local coins = copper % 100
    local parts = {}
    if gold > 0 then table.insert(parts, gold .. "g") end
    if silver > 0 or gold > 0 then table.insert(parts, silver .. "s") end
    table.insert(parts, coins .. "c")
    return table.concat(parts, " ")
end

local function CollectUsefulStats(itemLink, slotID)
    if not itemLink then return {} end
    local values = GetItemStats and GetItemStats(itemLink) or {}
    if type(values) ~= "table" then values = {} end

    -- On BCC, GetItemStats() may omit random-property stats. The resolved
    -- equipped-item tooltip contains the effective stats for that instance.
    local tooltipValues, tooltipReady = GetEquippedTooltipStats(slotID)

    local output = {}
    for statIndex, stat in ipairs(STAT_SOURCES) do
        local amount = tooltipValues[statIndex]
        if not amount then
            for keyIndex = 2, #stat do
                if values[stat[keyIndex]] then
                    amount = values[stat[keyIndex]]
                    break
                end
            end
        end
        if amount and amount ~= 0 then
            table.insert(output, { name = stat[1], value = amount })
        end
    end
    return output, tooltipReady
end

addon.Readers.EquipmentStats = CollectUsefulStats
addon.Readers.SlotNames = SLOT_NAMES

local function GetUsefulStats(itemLink, slotID)
    local output = {}
    for _, stat in ipairs(CollectUsefulStats(itemLink, slotID)) do
        table.insert(output, stat.name .. " " .. (stat.value > 0 and "+" or "") .. stat.value)
    end
    return table.concat(output, ", ")
end

local function BuildEquipmentSection(output)
    table.insert(output, "## Equipment")
    table.insert(output, "")
    table.insert(output, "| Slot | Item | Item Level | Required Level | Stats |")
    table.insert(output, "| --- | --- | ---: | ---: | --- |")
    for slotID = 1, 19 do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local name, _, _, itemLevel, requiredLevel = GetItemInfo(link)
            table.insert(output, string.format("| %s | %s | %s | %s | %s |",
                SLOT_NAMES[slotID], MarkdownText(name or link or "Unknown"),
                itemLevel or "", requiredLevel or "", MarkdownText(GetUsefulStats(link, slotID))))
        else
            table.insert(output, string.format("| %s | EMPTY |  |  |  |", SLOT_NAMES[slotID]))
        end
    end
    table.insert(output, "")
end

local function CollectProfessions()
    local entries, collapsed = {}, false

    -- Primary professions are abandonable skill lines. Secondary professions are
    -- identified by ranked trade-skill spells across the spellbook, rather than
    -- assuming that the General tab has a fixed index on every client.
    local tradeSkillSpells = {}
    if WoWSyncCompat and WoWSyncCompat.GetProfessionSpellEvidence then
        tradeSkillSpells = WoWSyncCompat.GetProfessionSpellEvidence() or tradeSkillSpells
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            if offset and numSpells then
                for spellIndex = offset + 1, offset + numSpells do
                    local spellName, spellRank = GetSpellBookItemName(spellIndex, BOOKTYPE_SPELL)
                    if spellName and spellRank and spellRank ~= "" then tradeSkillSpells[spellName] = true end
                end
            end
        end
    end

    if GetNumSkillLines and GetSkillLineInfo then
        for skillIndex = 1, GetNumSkillLines() do
            local name, isHeader, isExpanded, rank, _, _, maxRank, isAbandonable = GetSkillLineInfo(skillIndex)
            if isHeader and not isExpanded then collapsed = true end
            if name and not isHeader and rank and maxRank and maxRank > 0
                and (isAbandonable or tradeSkillSpells[name]) then
                table.insert(entries, { name = name, rank = rank, maxRank = maxRank })
            end
        end
    end
    return entries, collapsed
end

addon.Readers.Professions = CollectProfessions

local function BuildProfessionsSection(output)
    table.insert(output, "## Professions")
    table.insert(output, "")
    local entries = CollectProfessions()
    for _, entry in ipairs(entries) do
        table.insert(output, string.format("* %s: %s / %s", MarkdownText(entry.name), entry.rank, entry.maxRank))
    end
    if #entries == 0 then table.insert(output, "* No known professions found") end
    table.insert(output, "")
end

local function BuildBagSection(output)
    if not GetContainerNumSlots or not GetContainerNumFreeSlots then return end
    local total, free = 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        total = total + (GetContainerNumSlots(bag) or 0)
        free = free + (GetContainerNumFreeSlots(bag) or 0)
    end
    table.insert(output, "## Bags")
    table.insert(output, "")
    table.insert(output, "* Free bag slots: " .. free)
    table.insert(output, "* Total bag slots: " .. total)
    table.insert(output, "")
end

local function BuildCharacterReport()
    local name = UnitName("player") or "Unknown Character"
    local _, class = UnitClass("player")
    local output = { "# " .. MarkdownText(name), "" }
    table.insert(output, "* Level: " .. (UnitLevel("player") or "?"))
    table.insert(output, "* Class: " .. MarkdownText(class or "Unknown"))
    table.insert(output, "* Money: " .. FormatMoney(GetMoney and GetMoney() or 0))
    table.insert(output, "")
    BuildEquipmentSection(output)
    BuildProfessionsSection(output)
    BuildBagSection(output)
    return table.concat(output, "\n")
end

local TSM_SOURCES = {
    { "DBMarket", "DBMarket", true },
    { "DBMinBuyout", "DBMinBuyout", true },
    { "DBRegionMarketAvg", "DBRegionMarketAvg", true },
    { "DBRegionSaleAvg", "DBRegionSaleAvg", true },
    { "DBRegionSaleRate", "DBRegionSaleRate", false },
    { "DBRegionSoldPerDay", "DBRegionSoldPerDay", false },
    { "Disenchant value", "Destroy", true },
}

local function GetTSMValues(itemID, itemLink)
    if type(TSM_API) ~= "table" or type(TSM_API.GetCustomPriceValue) ~= "function" then return nil end
    local itemString = "i:" .. itemID
    if itemLink and type(TSM_API.ToItemString) == "function" then
        local ok, converted = pcall(TSM_API.ToItemString, itemLink)
        if ok and converted then itemString = converted end
    end
    local values = {}
    for _, source in ipairs(TSM_SOURCES) do
        local ok, value = pcall(TSM_API.GetCustomPriceValue, source[2], itemString)
        value = tonumber(value)
        if ok and value then
            table.insert(values, { label = source[1], value = value, isMoney = source[3] })
        end
    end
    return values
end

local function ResolveItemReference(argument)
    argument = (argument or ""):match("^%s*(.-)%s*$")
    if argument ~= "" then return argument end
    if GameTooltip and GameTooltip.GetItem then
        local _, link = GameTooltip:GetItem()
        return link
    end
end

local function BuildItemReport(argument)
    local itemReference = ResolveItemReference(argument)
    if not itemReference then
        return "## Item\n\nNo item found. Hover an item and run `/itemx`, or use `/itemx <item link or item ID>`."
    end

    local name, link, quality, _, _, _, _, _, _, _, vendorValue = GetItemInfo(itemReference)
    local itemID = tonumber(tostring(link or itemReference):match("item:(%d+)")) or tonumber(itemReference)
    if not itemID then
        return "## Item\n\nItem information is not available yet. Try again after the item tooltip has loaded."
    end
    local quantity = GetItemCount and GetItemCount(itemID, false) or 0
    local qualityName = quality and _G["ITEM_QUALITY" .. quality .. "_DESC"]
    local output = { "## Item", "" }
    table.insert(output, "* Name: " .. MarkdownText(name or link or ("Item " .. itemID)))
    table.insert(output, "* Item ID: " .. itemID)
    table.insert(output, "* Quality: " .. MarkdownText(qualityName or quality or "Unknown"))
    table.insert(output, "* Quantity in bags: " .. quantity)
    table.insert(output, "* Vendor value each: " .. (vendorValue and FormatMoney(vendorValue) or "Unknown"))
    table.insert(output, "* Vendor value total: " .. (vendorValue and FormatMoney(vendorValue * quantity) or "Unknown"))

    local tsmValues = GetTSMValues(itemID, link)
    if tsmValues and #tsmValues > 0 then
        table.insert(output, "")
        table.insert(output, "### TSM Pricing")
        table.insert(output, "")
        for _, entry in ipairs(tsmValues) do
            local value = entry.isMoney and FormatMoney(entry.value) or string.format("%.4g", entry.value)
            table.insert(output, "* " .. entry.label .. ": " .. value)
        end
    end
    return table.concat(output, "\n")
end

local function GetTSMPriceMap(itemID, itemLink)
    local result = {}
    local values = GetTSMValues(itemID, itemLink)
    if values then
        for _, entry in ipairs(values) do result[entry.label] = entry.value end
    end
    return result
end

local inventoryScanTooltip
local QUEST_ITEM_CLASS_ID = LE_ITEM_CLASS_QUESTITEM or 12
local ECONOMIC_ITEM_CLASSES = {
    [0] = true,  -- Consumable
    [1] = true,  -- Container
    [2] = true,  -- Weapon
    [3] = true,  -- Gem
    [4] = true,  -- Armor
    [7] = true,  -- Trade Goods
    [9] = true,  -- Recipe
}

local function GetBagItemFlags(bag, slot, bindType)
    local binding = ({ [1] = "Bind on Pickup", [2] = "Bind on Equip", [3] = "Bind on Use" })[bindType]
        or (bindType == 0 and "Unbound" or "Unknown")
    local isConjured = false
    inventoryScanTooltip = inventoryScanTooltip or CreateFrame(
        "GameTooltip", "GearExportInventoryScanTooltip", UIParent, "GameTooltipTemplate"
    )
    inventoryScanTooltip:Hide()
    inventoryScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    inventoryScanTooltip:ClearLines()
    if not pcall(inventoryScanTooltip.SetBagItem, inventoryScanTooltip, bag, slot) then
        return binding, isConjured
    end
    for lineIndex = 2, inventoryScanTooltip:NumLines() do
        local fontString = _G["GearExportInventoryScanTooltipTextLeft" .. lineIndex]
        local text = fontString and fontString:GetText()
        if text == ITEM_SOULBOUND then
            binding = "Soulbound"
        elseif text == ITEM_BIND_ON_PICKUP then
            binding = "Bind on Pickup"
        elseif text == ITEM_BIND_ON_EQUIP then
            binding = "Bind on Equip"
        elseif text == ITEM_BIND_ON_USE then
            binding = "Bind on Use"
        elseif text == ITEM_CONJURED then
            isConjured = true
        end
    end
    inventoryScanTooltip:Hide()
    return binding, isConjured
end

local function ToTSMItemString(itemLink, itemID)
    if type(TSM_API) == "table" and type(TSM_API.ToItemString) == "function" then
        local ok, itemString = pcall(TSM_API.ToItemString, itemLink)
        if ok and itemString then return itemString end
    end
    return "i:" .. itemID
end

local function GetContainerSlotCount(bag)
    if bag == (BANK_CONTAINER or -1) and NUM_BANKGENERIC_SLOTS then
        return NUM_BANKGENERIC_SLOTS
    elseif C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function GetContainerSlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        local link = info.hyperlink
        if not link and C_Container.GetContainerItemLink then
            link = C_Container.GetContainerItemLink(bag, slot)
        end
        return link, info.stackCount or 1, info.itemID
    elseif GetContainerItemInfo and GetContainerItemLink then
        local link = GetContainerItemLink(bag, slot)
        if not link then return nil end
        local _, quantity = GetContainerItemInfo(bag, slot)
        return link, quantity or 1, tonumber(link:match("item:(%d+)"))
    end
end

local function GetContainerFreeCount(bag)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bag) or 0
    elseif GetContainerNumFreeSlots then
        return GetContainerNumFreeSlots(bag) or 0
    end
    return 0
end

local function AddContainerItems(items, firstBag, lastBag, location)
    for bag = firstBag, lastBag do
        for slot = 1, GetContainerSlotCount(bag) do
            local itemLink, quantity, discoveredItemID = GetContainerSlotItem(bag, slot)
            if itemLink then
                local name, resolvedLink, quality, _, _, itemType, itemSubType, _, _, _, vendorEach,
                    classID, subClassID, bindType = GetItemInfo(itemLink)
                local itemID = discoveredItemID or tonumber(itemLink:match("item:(%d+)"))
                if itemID then
                    local binding, isConjured = GetBagItemFlags(bag, slot, bindType)
                    local isQuestItem = bindType == 4 or classID == QUEST_ITEM_CLASS_ID
                    if not isQuestItem and not isConjured then
                        local itemString = ToTSMItemString(itemLink, itemID)
                        local item = items[itemString]
                        if not item then
                            item = {
                                itemString = itemString, itemID = itemID, link = resolvedLink or itemLink,
                                name = name or ("Item " .. itemID), quality = quality,
                                itemType = itemType, itemSubType = itemSubType,
                                classID = classID, subClassID = subClassID,
                                vendorEach = vendorEach or 0, binding = binding, bags = 0, bankLive = 0,
                            }
                            items[itemString] = item
                        elseif item.binding ~= binding then
                            item.binding = "Mixed"
                        end
                        item[location] = item[location] + (quantity or 1)
                    end
                end
            end
        end
    end
end

local function SafeTSMQuantity(functionName, itemString)
    local api = type(TSM_API) == "table" and TSM_API[functionName]
    if type(api) ~= "function" then return nil, false end
    local ok, quantity = pcall(api, itemString)
    quantity = ok and tonumber(quantity) or nil
    return quantity, quantity ~= nil
end

local function InventoryMoney(value)
    return value and FormatMoney(value) or "—"
end

local function BuildInventoryReport()
    local items = {}
    AddContainerItems(items, 0, NUM_BAG_SLOTS or 4, "bags")

    local bankIsOpen = BankFrame and BankFrame:IsShown()
    if bankIsOpen then
        AddContainerItems(items, BANK_CONTAINER or -1, BANK_CONTAINER or -1, "bankLive")
        AddContainerItems(items, (NUM_BAG_SLOTS or 4) + 1,
            (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7), "bankLive")
    end

    local hasTSMInventory = type(TSM_API) == "table"
        and type(TSM_API.GetBankQuantity) == "function"
        and type(TSM_API.GetMailQuantity) == "function"
        and type(TSM_API.GetAuctionQuantity) == "function"
    local rows = {}
    local estimatedMarket, vendorValue = 0, 0
    local bankAvailable, mailAvailable, auctionAvailable = bankIsOpen, false, false
    for _, item in pairs(items) do
        item.prices = GetTSMPriceMap(item.itemID, item.link)
        if hasTSMInventory then
            local bankOK, mailOK, auctionOK
            if bankIsOpen then
                item.bank = item.bankLive
            else
                item.bank, bankOK = SafeTSMQuantity("GetBankQuantity", item.itemString)
                item.bank = item.bank or 0
            end
            item.mail, mailOK = SafeTSMQuantity("GetMailQuantity", item.itemString)
            item.auction, auctionOK = SafeTSMQuantity("GetAuctionQuantity", item.itemString)
            item.mail = item.mail or 0
            item.auction = item.auction or 0
            bankAvailable = bankAvailable or bankOK
            mailAvailable = mailAvailable or mailOK
            auctionAvailable = auctionAvailable or auctionOK
        elseif bankIsOpen then
            item.bank = item.bankLive
        end
        item.total = item.bags + (item.bank or 0) + (item.mail or 0) + (item.auction or 0)
        if item.binding == "Soulbound" and (item.mail or 0) + (item.auction or 0) > 0 then
            item.binding = "Mixed"
        end
        item.vendorTotal = item.vendorEach > 0 and item.vendorEach * item.total or nil
        local isAuctionable = item.binding ~= "Soulbound" and item.binding ~= "Bind on Pickup"
            and item.binding ~= "Mixed" and item.binding ~= "Unknown"
        item.marketTotal = isAuctionable and item.prices.DBMarket
            and item.prices.DBMarket * item.total or nil
        local hasOtherTSM = false
        for _, value in pairs(item.prices) do
            if value and value > 0 then hasOtherTSM = true break end
        end
        item.sortGroup = item.marketTotal and item.marketTotal > 0 and 1
            or hasOtherTSM and 2 or item.vendorTotal and item.vendorTotal > 0 and 3 or 4
        if hasOtherTSM or item.vendorTotal or ECONOMIC_ITEM_CLASSES[item.classID] then
            table.insert(rows, item)
            estimatedMarket = estimatedMarket + (item.marketTotal or 0)
            vendorValue = vendorValue + (item.vendorTotal or 0)
        end
    end

    table.sort(rows, function(a, b)
        if a.sortGroup ~= b.sortGroup then return a.sortGroup < b.sortGroup end
        if a.sortGroup == 1 and a.marketTotal ~= b.marketTotal then return a.marketTotal > b.marketTotal end
        return a.name:lower() < b.name:lower()
    end)

    local name = UnitName("player") or "Unknown Character"
    local output = { "# Inventory Market Export", "", "## Character", "" }
    table.insert(output, "* Name: " .. MarkdownText(name))
    table.insert(output, "* Level: " .. (UnitLevel("player") or "?"))
    table.insert(output, "* Money: " .. FormatMoney(GetMoney and GetMoney() or 0))
    table.insert(output, "")
    table.insert(output, "## Inventory Data")
    table.insert(output, "")
    table.insert(output, "* Bags: Live")
    if hasTSMInventory then
        table.insert(output, bankIsOpen and "* Bank: Live" or bankAvailable
            and "* Bank: TSM cached (current character)" or "* Bank: Unavailable")
        table.insert(output, mailAvailable and "* Mail: TSM cached (current character)"
            or "* Mail: Unavailable")
        table.insert(output, auctionAvailable and "* Auction House: TSM cached (current character)"
            or "* Auction House: Unavailable")
    elseif bankIsOpen then
        table.insert(output, "* Bank: Live")
        table.insert(output, "* Mail: Unavailable")
        table.insert(output, "* Auction House: Unavailable")
    else
        table.insert(output, "* Bank, Mail, Auction House: Unavailable")
    end
    table.insert(output, "")
    table.insert(output, "## Summary")
    table.insert(output, "")
    table.insert(output, "* Distinct economic items: " .. #rows)
    table.insert(output, "* Estimated auctionable DBMarket value: " .. FormatMoney(estimatedMarket))
    table.insert(output, "* Vendor value: " .. FormatMoney(vendorValue))
    if (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots then
        local free, total = 0, 0
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            free = free + GetContainerFreeCount(bag)
            total = total + GetContainerSlotCount(bag)
        end
        table.insert(output, string.format("* Free bag slots: %d / %d", free, total))
    end
    table.insert(output, "")
    table.insert(output, "## Items")
    table.insert(output, "")

    local locationHeaders = hasTSMInventory and "| Item | Item ID | Bags | Bank | Mail | AH | Total "
        or bankIsOpen and "| Item | Item ID | Bags | Bank | Total "
        or "| Item | Item ID | Bags | Total "
    local locationRule = hasTSMInventory and "| --- | ---: | ---: | ---: | ---: | ---: | ---: "
        or bankIsOpen and "| --- | ---: | ---: | ---: | ---: "
        or "| --- | ---: | ---: | ---: "
    local valueHeaders = "| Quality | Binding | Vendor Each | Vendor Total | DBMarket Each | Market Total | DBMinBuyout | Region Market Avg | Region Sale Avg | Sale Rate | Sold/Day | DE Value |"
    local valueRule = "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
    table.insert(output, locationHeaders .. valueHeaders)
    table.insert(output, locationRule .. valueRule)

    for _, item in ipairs(rows) do
        local locationValues = hasTSMInventory and string.format("| %s | %d | %d | %d | %d | %d | %d ",
            MarkdownText(item.name), item.itemID, item.bags, item.bank, item.mail, item.auction, item.total)
            or bankIsOpen and string.format("| %s | %d | %d | %d | %d ",
                MarkdownText(item.name), item.itemID, item.bags, item.bank, item.total)
            or string.format("| %s | %d | %d | %d ",
                MarkdownText(item.name), item.itemID, item.bags, item.total)
        local qualityName = item.quality and _G["ITEM_QUALITY" .. item.quality .. "_DESC"] or "Unknown"
        local p = item.prices
        local valueColumns = string.format("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
            MarkdownText(qualityName), MarkdownText(item.binding),
            item.vendorEach > 0 and FormatMoney(item.vendorEach) or "—", InventoryMoney(item.vendorTotal),
            InventoryMoney(p.DBMarket), InventoryMoney(item.marketTotal), InventoryMoney(p.DBMinBuyout),
            InventoryMoney(p.DBRegionMarketAvg), InventoryMoney(p.DBRegionSaleAvg),
            p.DBRegionSaleRate and string.format("%.4g", p.DBRegionSaleRate) or "—",
            p.DBRegionSoldPerDay and string.format("%.4g", p.DBRegionSoldPerDay) or "—",
            InventoryMoney(p["Disenchant value"]))
        table.insert(output, locationValues .. valueColumns)
    end
    return table.concat(output, "\n")
end

local TRAINER_STATUS_LABELS = {
    available = "Available",
    used = "Known",
    unavailable = "Unavailable",
}

local function TrainerWindowIsOpen()
    return ClassTrainerFrame and ClassTrainerFrame:IsShown()
end

local function CollectTrainerReport(enrich)
    if not TrainerWindowIsOpen() or type(GetNumTrainerServices) ~= "function"
        or type(GetTrainerServiceInfo) ~= "function" then
        return nil
    end

    local _, class = UnitClass("player")
    local report = {
        character = {
            name = UnitName("player") or "Unknown Character",
            level = UnitLevel("player"),
            class = class or "Unknown",
            money = GetMoney and GetMoney() or 0,
        },
        trainer = {
            name = UnitName("npc"),
            type = IsTradeskillTrainer and IsTradeskillTrainer() and "Trade Skill Trainer"
                or IsTalentTrainer and IsTalentTrainer() and "Talent Trainer"
                or "Trainer",
        },
        services = {},
    }

    for index = 1, GetNumTrainerServices() do
        local name, subText, serviceType = GetTrainerServiceInfo(index)
        -- The legacy API includes category headers in the filtered service list.
        if name and serviceType ~= "header" then
            local cost = type(GetTrainerServiceCost) == "function" and GetTrainerServiceCost(index) or nil
            local requiredLevel = type(GetTrainerServiceLevelReq) == "function"
                and GetTrainerServiceLevelReq(index) or nil
            local service = {
                name = name,
                rank = subText,
                status = serviceType,
                cost = tonumber(cost),
                requiredLevel = tonumber(requiredLevel),
            }
            if enrich then enrich(service, index) end
            table.insert(report.services, service)
        end
    end
    return report
end

addon.Readers.Trainer = CollectTrainerReport

local function RenderTrainerReport(report)
    local output = { "# Trainer Export", "", "## Character", "" }
    table.insert(output, "* Name: " .. MarkdownText(report.character.name))
    table.insert(output, "* Level: " .. tostring(report.character.level or "Unknown"))
    table.insert(output, "* Class: " .. MarkdownText(report.character.class))
    table.insert(output, "* Money: " .. FormatMoney(report.character.money))
    table.insert(output, "")
    table.insert(output, "## Trainer")
    table.insert(output, "")
    table.insert(output, "* Name: " .. MarkdownText(report.trainer.name or "Unknown"))
    table.insert(output, "* Type: " .. MarkdownText(report.trainer.type))
    table.insert(output, "")
    table.insert(output, "## Services")
    table.insert(output, "")
    table.insert(output, "| Ability | Rank | Required Level | Cost | Status | Affordable |")
    table.insert(output, "| --- | --- | ---: | ---: | --- | --- |")
    for _, service in ipairs(report.services) do
        local status = TRAINER_STATUS_LABELS[service.status] or service.status or "Unknown"
        local affordable = service.cost ~= nil
            and (report.character.money >= service.cost and "Yes" or "No") or "Unknown"
        table.insert(output, string.format("| %s | %s | %s | %s | %s | %s |",
            MarkdownText(service.name), MarkdownText(service.rank and service.rank ~= "" and service.rank or "—"),
            service.requiredLevel or "—", service.cost and FormatMoney(service.cost) or "—",
            MarkdownText(status), affordable))
    end
    if #report.services == 0 then
        table.insert(output, "| No services exposed by the current trainer filters. | — | — | — | — | — |")
    end
    return table.concat(output, "\n")
end

local frame = CreateFrame("Frame", "GearExportFrame", UIParent)
frame:SetSize(620, 520)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if GearExportDB then
        local point, _, relativePoint, x, y = self:GetPoint()
        GearExportDB.position = { point, relativePoint, x, y }
    end
end)
frame:Hide()

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.92)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -15)
title:SetText("Gear Export")

local scroll = CreateFrame("ScrollFrame", "GearExportScrollFrame", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 20, -45)
scroll:SetPoint("BOTTOMRIGHT", -42, 48)

local edit = CreateFrame("EditBox", nil, scroll)
edit:SetMultiLine(true)
edit:SetAutoFocus(false)
edit:SetFontObject(ChatFontNormal)
edit:SetWidth(545)
edit:SetHeight(420)
edit:SetTextInsets(4, 4, 4, 4)
edit:SetScript("OnEscapePressed", function() frame:Hide() end)
edit:SetScript("OnTextChanged", function(self)
    self:SetHeight(math.max(420, (self:GetNumLines() or 1) * 14 + 16))
end)
scroll:SetScrollChild(edit)

local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
close:SetSize(80, 22)
close:SetPoint("BOTTOM", 0, 15)
close:SetText("Close")
close:SetScript("OnClick", function() frame:Hide() end)

local function ShowReport(report, slot)
    GearExportDB = GearExportDB or {}
    GearExportDB.exports = GearExportDB.exports or {}
    GearExportDB.exportMeta = GearExportDB.exportMeta or {}
    if slot then
        GearExportDB.exports[slot] = report
        GearExportDB.exportMeta[slot] = {
            time = date("%Y-%m-%d %H:%M:%S"),
            character = UnitName("player"),
            level = UnitLevel("player"),
        }
        GearExportDB.latestExport = report
    end
    frame:Show()
    scroll:SetVerticalScroll(0)
    edit:SetText(report)
    edit:SetFocus()
    edit:HighlightText()
end

local function BuildHelpReport()
    return table.concat({
        "# GearExport Help",
        "",
        "* `/gearx` — Export the complete character report.",
        "* `/gearx help` — Show this help.",
        "* `/gearhelp` — Show this help.",
        "* `/itemx` — Export the item currently under the mouse pointer.",
        "* `/itemx <item link or item ID>` — Export a specific item.",
        "* `/itemx help` — Show this help.",
        "* `/bagsx` — Export current-character inventory and market values.",
        "* `/trainerx` — Export the currently open trainer window.",
        "",
        "Reports are selected automatically. Press `Ctrl+C` to copy and Escape to close.",
    }, "\n")
end

local function IsHelpArgument(argument)
    argument = (argument or ""):match("^%s*(.-)%s*$"):lower()
    return argument == "help" or argument == "?"
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    GearExportDB = GearExportDB or {}
    GearExportDB.exports = GearExportDB.exports or {}
    GearExportDB.exportMeta = GearExportDB.exportMeta or {}
    local position = GearExportDB.position
    if position then
        frame:ClearAllPoints()
        frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    end
end)

table.insert(UISpecialFrames, "GearExportFrame")

SLASH_GEAREXPORT1 = "/gearexport"
SLASH_GEAREXPORT2 = "/gearx"
SlashCmdList.GEAREXPORT = function(argument)
    if IsHelpArgument(argument) then ShowReport(BuildHelpReport()); return end
    ShowReport(BuildCharacterReport(), "character")
end

SLASH_GEARITEMEXPORT1 = "/itemx"
SlashCmdList.GEARITEMEXPORT = function(argument)
    if IsHelpArgument(argument) then ShowReport(BuildHelpReport()); return end
    ShowReport(BuildItemReport(argument), "item")
end

SLASH_GEARHELP1 = "/gearhelp"
SlashCmdList.GEARHELP = function() ShowReport(BuildHelpReport()) end

SLASH_GEARINVENTORYEXPORT1 = "/bagsx"
SlashCmdList.GEARINVENTORYEXPORT = function(argument)
    if IsHelpArgument(argument) then ShowReport(BuildHelpReport()); return end
    ShowReport(BuildInventoryReport(), "inventory")
end

SLASH_GEARTRAINEREXPORT1 = "/trainerx"
SlashCmdList.GEARTRAINEREXPORT = function(argument)
    if IsHelpArgument(argument) then ShowReport(BuildHelpReport()); return end
    local report = CollectTrainerReport()
    if not report then
        print("GearExport: Open a trainer window before using /trainerx.")
        return
    end
    ShowReport(RenderTrainerReport(report), "trainer")
end
