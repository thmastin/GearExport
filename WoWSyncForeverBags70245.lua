-- Forever 1.60.1.70245: only the live-observed carried container tuple.
-- No bank range, family, free-slot API, or transferability inference.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key)
    return function() return object[key] end
end

local function ItemReference(link, id)
    if type(link) ~= "string" then return nil end
    local ref = link:match("(item:[^|]+)")
    if not ref or not ref:match("^item:%d+[%d:%-]*$") then return nil end
    local linkID = tonumber(ref:match("^item:(%d+)"))
    if not linkID or linkID <= 0 or id and id ~= linkID then return nil end
    return ref, linkID
end

local function BindingFacet(info, issues)
    local ok, value = pcall(function() return info.isBound end)
    if not ok then
        issues[#issues + 1] = "Carried item binding field failed"
        return nil, "API_ERROR"
    end
    if type(issecretvalue) == "function" then
        local public, secret = pcall(issecretvalue, value)
        if not public or secret then
            issues[#issues + 1] = "Carried item binding field restricted"
            return nil, "UNKNOWN"
        end
    end
    if type(value) == "boolean" then
        return value, value and "OBSERVED_TRUE" or "OBSERVED_FALSE"
    end
    issues[#issues + 1] = "Carried item binding field unknown"
    return nil, "UNKNOWN"
end

S.collectors.bags = function()
    local api = type(C_Container) == "table" and C_Container or {}
    if type(api.GetContainerNumSlots) ~= "function" or type(api.GetContainerItemInfo) ~= "function" then
        return nil, { reason = "Forever 70245 carried-container APIs unavailable" }
    end
    local issues, containers, observedSlots = {}, {}, {}
    -- The probe observed the carried range 0..5, capacities for each index,
    -- and every slot in each non-empty container. Fail closed on range drift.
    for bag = 0, 5 do
        local capacity = F.Number("Carried bag " .. bag .. " capacity", api.GetContainerNumSlots, issues, bag)
        if capacity == nil or capacity > 120 then
            return nil, { reason = "Forever 70245 carried-container capacity unknown or changed" }
        end
        local container = { id = bag, capacity = capacity, slots = {} }
        observedSlots[bag] = {}
        local occupied = 0
        for slot = 1, capacity do
            local result = F.Read("Carried bag " .. bag .. " slot " .. slot, function()
                return { api.GetContainerItemInfo(bag, slot) }
            end, 1, "table", issues)
            if not result then return nil, { reason = "Forever 70245 carried-container slot unavailable" } end
            if result[1] ~= nil then
                local info = F.Read("Carried bag item", Field(result, 1), 1, "table", issues)
                if not info then return nil, { reason = "Forever 70245 carried item restricted or malformed" } end
                local locked = F.Read("Carried item lock", Field(info, "isLocked"), 1, "boolean", issues)
                if locked ~= false then return nil, { reason = "Forever 70245 carried item lock state unknown" } end
                local id = F.Number("Carried item ID", Field(info, "itemID"), issues)
                if id == 0 then id = nil end
                local link = F.Read("Carried item hyperlink", Field(info, "hyperlink"), 1, "string", issues)
                local ref, linkID = ItemReference(link, id)
                if not ref then return nil, { reason = "Forever 70245 exact carried item identity unknown" } end
                local count = F.Number("Carried item stack count", Field(info, "stackCount"), issues)
                if not count or count == 0 then return nil, { reason = "Forever 70245 carried item quantity unknown" } end
                local item = { itemID = id or linkID, itemString = ref, count = count }
                item.name = F.Read("Carried item name", Field(info, "itemName"), 1, "string", issues)
                item.bound, item.bindingState = BindingFacet(info, issues)
                container.slots[slot] = item
                occupied = occupied + 1
                observedSlots[bag][slot] = { itemID = item.itemID, itemString = item.itemString,
                    count = item.count, bindingState = item.bindingState, bound = item.bound }
            else
                observedSlots[bag][slot] = false
            end
        end
        container.free = capacity - occupied
        local finalCapacity = F.Number("Carried bag " .. bag .. " final capacity", api.GetContainerNumSlots, issues, bag)
        if finalCapacity ~= capacity then return nil, { reason = "Forever 70245 carried-container changed during capture" } end
        containers[#containers + 1] = container
    end
    -- Re-read the observed range so a slot mutation during the scan cannot
    -- produce a mixed snapshot. Successful nil remains distinct from errors.
    for bag = 0, 5 do
        for slot = 1, containers[bag + 1].capacity do
            local result = F.Read("Carried bag " .. bag .. " slot " .. slot .. " verification", function()
                return { api.GetContainerItemInfo(bag, slot) }
            end, 1, "table", issues)
            if not result then return nil, { reason = "Forever 70245 carried-container verification unavailable" } end
            local expected = observedSlots[bag][slot]
            if result[1] == nil then
                if expected ~= false then return nil, { reason = "Forever 70245 carried-container changed during capture" } end
            else
                if expected == false or type(result[1]) ~= "table" then
                    return nil, { reason = "Forever 70245 carried-container changed during capture" }
                end
                local info = result[1]
                local id = F.Number("Carried item verification ID", Field(info, "itemID"), issues)
                if id == 0 then id = nil end
                local link = F.Read("Carried item verification hyperlink", Field(info, "hyperlink"), 1, "string", issues)
                local ref, linkID = ItemReference(link, id)
                local count = F.Number("Carried item verification quantity", Field(info, "stackCount"), issues)
                local locked = F.Read("Carried item verification lock", Field(info, "isLocked"), 1, "boolean", issues)
                local bound, bindingState = BindingFacet(info, issues)
                if not ref or (id or linkID) ~= expected.itemID or ref ~= expected.itemString
                    or count ~= expected.count or locked ~= false
                    or bindingState ~= expected.bindingState or bound ~= expected.bound then
                    return nil, { reason = "Forever 70245 carried-container changed during capture" }
                end
            end
        end
    end
    return { containers = containers }, { completeness = #issues > 0 and "partial" or "complete",
        reason = #issues > 0 and table.concat(issues, "; ") or nil }
end
