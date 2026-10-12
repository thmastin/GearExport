-- Forever 1.60.1 supported builds: carried-container contract carried forward from 70245.
-- No bank range, family, free-slot API, or transferability inference.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key)
    return function() return object[key] end
end

local function ParseItemReference(link)
    if type(link) ~= "string" or link == "" then return nil, nil, "UNAVAILABLE" end
    local ref = link:match("(item:[^|]+)")
    if not ref or not ref:match("^item:%d+[%d:%-]*$") then return nil, nil, "MALFORMED" end
    local linkID = tonumber(ref:match("^item:(%d+)"))
    if not linkID or linkID <= 0 then return nil, nil, "MALFORMED" end
    return ref, linkID, "PARSED"
end

local function IdentityDetails(bag, slot, id, embeddedState, embeddedID, fallbackState, fallbackID, apiAvailable, reason)
    return "bag " .. bag .. " slot " .. slot .. " exact item identity rejected"
        .. " (reportedItemID=" .. (id and tostring(id) or "UNKNOWN")
        .. "; embeddedState=" .. embeddedState
        .. "; embeddedItemID=" .. (embeddedID and tostring(embeddedID) or "UNKNOWN")
        .. "; fallbackAPI=" .. (apiAvailable and "AVAILABLE" or "MISSING")
        .. "; fallbackState=" .. fallbackState
        .. "; fallbackItemID=" .. (fallbackID and tostring(fallbackID) or "UNKNOWN")
        .. "; reason=" .. reason .. ")"
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

local function Failed(reason, retry)
    return nil, { reason = "Forever " .. tostring(addon.Forever.build) .. " " .. reason, retry = retry, stale = true }
end

local function ExactItemReference(api, info, bag, slot, id)
    local infoState, embeddedID, embeddedRef = "NIL", nil, nil
    local ok, link = pcall(function() return info.hyperlink end)
    if not ok then infoState = "API_ERROR"
    elseif type(link) == "string" and link ~= "" then
        embeddedRef, embeddedID, infoState = ParseItemReference(link)
        if embeddedRef and embeddedID == id then
            return embeddedRef, embeddedID, "CONTAINER_INFO_HYPERLINK"
        elseif embeddedRef then infoState = "ID_MISMATCH"
        end
    elseif link ~= nil then infoState = "UNSUPPORTED_VALUE_TYPE"
    end

    local apiAvailable = type(api.GetContainerItemLink) == "function"
    local slotAPIState, fallbackID, fallbackRef = "API_MISSING", nil, nil
    if apiAvailable then
        local linkOK, value = pcall(api.GetContainerItemLink, bag, slot)
        if not linkOK then slotAPIState = "API_ERROR"
        elseif value == nil then slotAPIState = "NIL_RESULT"
        elseif type(value) ~= "string" or value == "" then slotAPIState = "UNSUPPORTED_VALUE_TYPE"
        else
            fallbackRef, fallbackID, slotAPIState = ParseItemReference(value)
            if fallbackRef and fallbackID ~= id then slotAPIState = "ID_MISMATCH" end
        end
    end

    -- A second, independently returned link can recover a missing or malformed
    -- embedded link only when its observed base ID matches the slot's itemID.
    -- A parseable disagreement between two link sources is retained as a hard
    -- contradiction rather than preferring either result.
    if fallbackRef and fallbackID == id then
        if embeddedID and embeddedID ~= fallbackID then
            return nil, IdentityDetails(bag, slot, id, infoState, embeddedID,
                slotAPIState, fallbackID, apiAvailable, "EMBEDDED_AND_FALLBACK_DISAGREE"), nil
        end
        local diagnostics
        if infoState ~= "NIL" then
            diagnostics = { embeddedState = infoState, embeddedItemID = embeddedID,
                fallbackState = "OBSERVED_MATCH", fallbackItemID = fallbackID,
                fallbackAPI = "AVAILABLE", reason = "EMBEDDED_LINK_UNUSABLE_FALLBACK_MATCHED_SLOT_ID" }
        end
        return fallbackRef, fallbackID, "C_Container.GetContainerItemLink", nil, diagnostics
    end

    local reason = embeddedID and fallbackID and embeddedID ~= fallbackID
        and "EMBEDDED_AND_FALLBACK_DISAGREE"
        or fallbackRef and fallbackID ~= id and "FALLBACK_ID_MISMATCH"
        or "NO_VALID_EXACT_LINK_MATCHES_SLOT_ID"
    return nil, IdentityDetails(bag, slot, id, infoState, embeddedID,
        slotAPIState, fallbackID, apiAvailable, reason), nil
end

S.collectors.bags = function()
    local api = type(C_Container) == "table" and C_Container or {}
    if type(api.GetContainerNumSlots) ~= "function" or type(api.GetContainerItemInfo) ~= "function" then
        return Failed("carried-container APIs unavailable", false)
    end
    local issues, containers, observedSlots = {}, {}, {}
    -- The probe observed the carried range 0..5, capacities for each index,
    -- and every slot in each non-empty container. Fail closed on range drift.
    for bag = 0, 5 do
        local capacity = F.Number("Carried bag " .. bag .. " capacity", api.GetContainerNumSlots, issues, bag)
        if capacity == nil or capacity > 120 then
            return Failed("carried-container capacity unknown or changed", false)
        end
        local container = { id = bag, capacity = capacity, slots = {} }
        observedSlots[bag] = {}
        local occupied = 0
        for slot = 1, capacity do
            local result = F.Read("Carried bag " .. bag .. " slot " .. slot, function()
                return { api.GetContainerItemInfo(bag, slot) }
            end, 1, "table", issues)
            if not result then return Failed("carried-container slot unavailable", true) end
            if result[1] ~= nil then
                local info = F.Read("Carried bag item", Field(result, 1), 1, "table", issues)
                if not info then return Failed("carried item restricted or malformed", true) end
                local locked = F.Read("Carried item lock", Field(info, "isLocked"), 1, "boolean", issues)
                if locked ~= false then return Failed("carried item lock state unknown", true) end
                local id = F.Number("Carried item ID", Field(info, "itemID"), issues)
                if id == 0 then id = nil end
                local ref, linkID, linkSource, _, identityDiagnostics = ExactItemReference(api, info, bag, slot, id)
                if not ref then return Failed(linkID, true) end
                local count = F.Number("Carried item stack count", Field(info, "stackCount"), issues)
                if not count or count == 0 then return Failed("carried item quantity unknown", true) end
                local item = { itemID = id or linkID, itemString = ref, count = count,
                    itemStringSource = linkSource, itemIdentityState = "OBSERVED_EXACT_ITEM_STRING" }
                if identityDiagnostics then
                    item.identityDiagnostics = identityDiagnostics
                    issues[#issues + 1] = "Carried item exact-link fallback used after embedded link was unusable at bag "
                        .. bag .. " slot " .. slot
                end
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
        if finalCapacity ~= capacity then return Failed("carried-container changed during capture", true) end
        containers[#containers + 1] = container
    end
    -- Re-read the observed range so a slot mutation during the scan cannot
    -- produce a mixed snapshot. Successful nil remains distinct from errors.
    for bag = 0, 5 do
        for slot = 1, containers[bag + 1].capacity do
            local result = F.Read("Carried bag " .. bag .. " slot " .. slot .. " verification", function()
                return { api.GetContainerItemInfo(bag, slot) }
            end, 1, "table", issues)
            if not result then return Failed("carried-container verification unavailable", true) end
            local expected = observedSlots[bag][slot]
            if result[1] == nil then
                if expected ~= false then return Failed("carried-container changed during capture", true) end
            else
                if expected == false or type(result[1]) ~= "table" then
                    return Failed("carried-container changed during capture", true)
                end
                local info = result[1]
                local id = F.Number("Carried item verification ID", Field(info, "itemID"), issues)
                if id == 0 then id = nil end
                local ref, linkID = ExactItemReference(api, info, bag, slot, id)
                local count = F.Number("Carried item verification quantity", Field(info, "stackCount"), issues)
                local locked = F.Read("Carried item verification lock", Field(info, "isLocked"), 1, "boolean", issues)
                local bound, bindingState = BindingFacet(info, issues)
                if not ref or (id or linkID) ~= expected.itemID or ref ~= expected.itemString
                    or count ~= expected.count or locked ~= false
                    or bindingState ~= expected.bindingState or bound ~= expected.bound then
                    return Failed("carried-container changed during capture at bag " .. bag .. " slot " .. slot, true)
                end
            end
        end
    end
    return { containers = containers }, { completeness = #issues > 0 and "partial" or "complete",
        reason = #issues > 0 and table.concat(issues, "; ") or nil }
end
