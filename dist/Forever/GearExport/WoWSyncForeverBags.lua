-- Forever build 69913 C_Container contracts; carried bags only, no bank APIs.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key)
    return function() return object[key] end
end

local function ItemReference(link, id)
    local ref = link and link:match("(item:[^|]+)")
    if not ref or not ref:match("^item:%d+[%d:%-]*$") then return nil end
    local linkID = tonumber(ref:match("^item:(%d+)"))
    if not linkID or linkID <= 0 or id and id ~= linkID then return nil end
    return ref, linkID
end

S.collectors.bags = function()
    local issues, data = {}, { containers = {} }
    local function Unavailable(reason, retry)
        return nil, { reason = "Forever bags: " .. reason, retry = retry ~= false }
    end
    local api = type(C_Container) == "table" and C_Container or {}
    local items = type(C_Item) == "table" and C_Item or {}
    local locations = type(ItemLocation) == "table" and ItemLocation or {}
    local constants = type(Constants) == "table" and Constants.InventoryConstants or {}
    local enum = type(Enum) == "table" and Enum.BagIndex or {}
    for _, name in ipairs({ "GetContainerNumSlots", "GetContainerNumFreeSlots", "GetContainerItemInfo" }) do
        if type(api[name]) ~= "function" then return Unavailable(name .. " unavailable", false) end
    end
    local regular = F.Number("Carried bag count", Field(constants, "NumBagSlots"), issues)
    local reagent = F.Number("Reagent bag count", Field(constants, "NumReagentBagSlots"), issues)
    if not regular or regular > 4 or not reagent or reagent > 1 then
        return Unavailable("carried-bag range unavailable or changed", false)
    end
    local keys = { "Backpack" }
    for index = 1, regular do keys[#keys + 1] = "Bag_" .. index end
    if reagent == 1 then keys[#keys + 1] = "ReagentBag" end
    local seen = {}
    for _, key in ipairs(keys) do
        local bag = F.Number("Bag index " .. key, Field(enum, key), issues)
        if not bag or seen[bag] or bag > 5 or key == "Backpack" and bag ~= 0
            or key ~= "Backpack" and bag == 0 then return Unavailable("bag indices unavailable or changed", false) end
        seen[bag] = true
        local label = "Bag " .. bag
        local capacity = F.Number(label .. " capacity", api.GetContainerNumSlots, issues, bag)
        if not capacity or key == "Backpack" and capacity == 0 then
            return Unavailable(label .. " capacity pending")
        end
        local free = F.Number(label .. " free slots", api.GetContainerNumFreeSlots, issues, bag)
        if not free or free > capacity then return Unavailable(label .. " free slots unavailable or inconsistent") end
        local family = F.Number(label .. " family", function()
            return select(2, api.GetContainerNumFreeSlots(bag))
        end, issues)
        local container = { id = bag, capacity = capacity, free = free, family = family, slots = {} }
        if key ~= "Backpack" then
            -- The bag itself is an equipped item, not container slot 1.
            container.bag = {} -- Unknown identity must render ?, never '-'.
            local inventoryID = F.Number(label .. " inventory slot", api.ContainerIDToInventoryID, issues, bag)
            local location = inventoryID and F.Read(label .. " location", locations.CreateFromEquipmentSlot,
                1, "table", issues, locations, inventoryID)
            local exists = location and F.Read(label .. " presence", items.DoesItemExist, 1, "boolean", issues, location)
            if exists == false then
                if capacity ~= 0 then return Unavailable(label .. " absent but capacity nonzero") end
                container.bag = nil
            elseif capacity == 0 then
                return Unavailable(label .. " bag presence/capacity pending")
            elseif exists == true then
                local id = F.Number(label .. " item ID", items.GetItemID, issues, location)
                if id and id > 0 then container.bag.itemID = id end
                local link = F.Read(label .. " item link", items.GetItemLink, 1, "string", issues, location)
                local ref, linkID = ItemReference(link, container.bag.itemID)
                container.bag.itemString = ref
                container.bag.itemID = container.bag.itemID or linkID
                if not ref then issues[#issues + 1] = label .. " item variant unknown" end
                local identity = ref or container.bag.itemID
                if identity then container.bag.name = F.Read(label .. " name", items.GetItemInfo, 1, "string", issues, identity) end
            end
        end
        local occupied = 0
        for slot = 1, capacity do
            local slotLabel = label .. " slot " .. slot
            -- Wrap the nullable result: successful nil is distinct from a failed
            -- call or missing API. Only the former can mean an empty slot.
            local result = F.Read(slotLabel, function()
                return { api.GetContainerItemInfo(bag, slot) }
            end, 1, "table", issues)
            if not result then return Unavailable(slotLabel .. " contents unavailable") end
            if type(result[1]) ~= "nil" then
                local info = F.Read(slotLabel .. " info", Field(result, 1), 1, "table", issues)
                if not info then return Unavailable(slotLabel .. " contents restricted or changed") end
                local locked = F.Read(slotLabel .. " lock", Field(info, "isLocked"), 1, "boolean", issues)
                if locked ~= false then return Unavailable(slotLabel .. " movement/lock state pending") end
                local count = F.Number(slotLabel .. " quantity", Field(info, "stackCount"), issues)
                if not count or count == 0 then return Unavailable(slotLabel .. " quantity unknown") end
                local id = F.Number(slotLabel .. " ID", Field(info, "itemID"), issues)
                if id == 0 then id = nil end
                local link = F.Read(slotLabel .. " link", Field(info, "hyperlink"), 1, "string", issues)
                local ref, linkID = ItemReference(link, id)
                if not ref then issues[#issues + 1] = slotLabel .. " item variant unknown" end
                id = id or linkID
                if not id then return Unavailable(slotLabel .. " identity unknown") end
                local item = { itemID = id, itemString = ref, count = count }
                item.name = F.Read(slotLabel .. " name", Field(info, "itemName"), 1, "string", issues)
                item.bound = F.Read(slotLabel .. " binding", Field(info, "isBound"), 1, "boolean", issues)
                -- Sell price is per item, in copper. hasNoValue/bindType never
                -- substitute for an observed price or current binding state.
                item.vendorCopper = F.Number(slotLabel .. " vendor price", function()
                    return select(11, items.GetItemInfo(ref or id))
                end, issues)
                container.slots[slot], occupied = item, occupied + 1
            end
        end
        if occupied ~= capacity - free then return Unavailable(label .. " contents still settling") end
        -- Reject a changing structural view instead of publishing mixed totals.
        if F.Number(label .. " final capacity", api.GetContainerNumSlots, issues, bag) ~= capacity
            or F.Number(label .. " final free", api.GetContainerNumFreeSlots, issues, bag) ~= free then
            return Unavailable(label .. " changed during capture")
        end
        data.containers[#data.containers + 1] = container
    end
    table.sort(issues)
    return data, { completeness = #issues > 0 and "partial" or "complete",
        reason = #issues > 0 and table.concat(issues, "; ") or nil, retry = #issues > 0 }
end
