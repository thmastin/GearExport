-- Forever 1.60.1 supported builds: carried-container contract carried forward from 70245.
-- No bank range, family, free-slot API, or transferability inference.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key)
    return function() return object[key] end
end

local MAX_LINK_DIAGNOSTIC_SCAN = 160

local function IsEscapedPipe(value, position)
    local count = 0
    for index = position, 1, -1 do
        if value:sub(index, index) ~= "|" then break end
        count = count + 1
    end
    return count > 0 and count % 2 == 0
end

local function ParseItemReference(link)
    if type(link) ~= "string" or link == "" then return nil, nil, "UNAVAILABLE" end
    local marker = link:find("|Hitem:", 1, true)
    local ref, baseIDHint
    if marker then
        if IsEscapedPipe(link, marker) then return nil, nil, "MALFORMED_ESCAPE" end
        local payloadStart = marker + 2
        local terminator = link:find("|h", payloadStart, true)
        if not terminator then return nil, nil, "TRUNCATED_ITEM_PAYLOAD" end
        if IsEscapedPipe(link, terminator) then return nil, nil, "MALFORMED_ESCAPE" end
        ref = link:sub(payloadStart, terminator - 1)
    elseif link:sub(1, 5) == "item:" then
        ref = link
    else
        if link:find("|H", 1, true) then return nil, nil, "NON_ITEM_LINK" end
        return nil, nil, "UNRECOGNIZED_FORMAT"
    end
    baseIDHint = tonumber(ref:match("^item:(%d+)"))
    if not ref:match("^item:%d+[%d:%-]*$") then
        return nil, nil, "MALFORMED_ITEM_PAYLOAD", baseIDHint
    end
    local linkID = baseIDHint
    if not linkID or linkID <= 0 then return nil, nil, "MALFORMED_ITEM_PAYLOAD", baseIDHint end
    return ref, linkID, "PARSED"
end

-- Persist only structural summaries: never link text, display names, chat text,
-- player identifiers, or variant payloads. Scan at most 160 characters.
local function LinkDiagnostic(value)
    local valueType = type(value)
    if valueType ~= "string" then
        local safeType = (valueType == "nil" or valueType == "number" or valueType == "boolean"
            or valueType == "table" or valueType == "function" or valueType == "userdata" or valueType == "thread")
            and valueType or "OTHER"
        return "type=" .. safeType .. ";shape=NON_STRING"
    end
    local totalLength = #value
    local sample = value:sub(1, MAX_LINK_DIAGNOSTIC_SCAN)
    local clipped = totalLength > MAX_LINK_DIAGNOSTIC_SCAN
    local marker = sample:find("|Hitem:", 1, true)
    local escaped = sample:find("||", 1, true) ~= nil
    local itemToken = sample:find("item:", 1, true)
    local otherLink = sample:find("|H([^:|]+):")
    local shape, payload = "UNRECOGNIZED_FORMAT", "NONE"
    local close
    if marker then
        if IsEscapedPipe(sample, marker) then shape = "ESCAPED_DELIMITER"
        else
            close = sample:find("|h", marker + 7, true)
            if close and IsEscapedPipe(sample, close) then shape = "ESCAPED_DELIMITER"
            elseif close then
                local prefix = sample:sub(1, marker - 1)
                if prefix:find("|cff%x%x%x%x%x%x%x%x", 1) == 1 or prefix:find("|cn", 1, true) == 1 then
                    shape = "COLORED_ITEM_HYPERLINK"
                else shape = "ITEM_HYPERLINK" end
            elseif clipped then shape = "INSPECTION_LIMIT_REACHED"
            else shape = "TRUNCATED_ITEM_PAYLOAD" end
        end
        local payloadStart = marker + 2
        local payloadEnd = close or (#sample + 1)
        local itemPayload = sample:sub(payloadStart, payloadEnd - 1)
        if clipped and not close then payload = "INSPECTION_LIMIT_REACHED"
        elseif itemPayload:match("^item:%d+[%d:%-]*$") then payload = "NUMERIC_ITEM_FIELDS"
        else payload = "MALFORMED_ITEM_FIELDS" end
    elseif sample:sub(1, 5) == "item:" then
        shape = "PLAIN_ITEM_STRING"
        if clipped then payload = "INSPECTION_LIMIT_REACHED"
        elseif sample:match("^item:%d+[%d:%-]*$") then payload = "NUMERIC_ITEM_FIELDS"
        else payload = "MALFORMED_ITEM_FIELDS" end
    elseif escaped and itemToken then shape = "ESCAPED_DELIMITER"
    elseif otherLink then shape = "NON_ITEM_HYPERLINK"
    elseif itemToken then shape = "UNWRAPPED_ITEM_TOKEN"
    elseif clipped then shape = "INSPECTION_LIMIT_REACHED" end
    local length = clipped and (MAX_LINK_DIAGNOSTIC_SCAN .. "+") or tostring(totalLength)
    return "type=string;length=" .. length .. ";shape=" .. shape .. ";payload=" .. payload
        .. ";escaped=" .. (escaped and "yes" or "no")
        .. ";itemMarker=" .. (marker and "yes" or "no")
        .. ";itemToken=" .. (itemToken and "yes" or "no")
        .. ";hyperlinkClose=" .. (close and "yes" or "no")
end

local function SafeLinkDiagnostic(value)
    local ok, diagnostic = pcall(LinkDiagnostic, value)
    return ok and diagnostic or "type=restricted;shape=UNAVAILABLE"
end

local function IdentityDetails(bag, slot, id, embeddedState, embeddedID, fallbackState, fallbackID,
    apiAvailable, reason, embeddedDiagnostic, fallbackDiagnostic, embeddedBaseIDHint)
    return "bag " .. bag .. " slot " .. slot .. " exact item identity rejected"
        .. " (reportedItemID=" .. (id and tostring(id) or "UNKNOWN")
        .. "; embeddedState=" .. embeddedState
        .. "; embeddedItemID=" .. (embeddedID and tostring(embeddedID) or "UNKNOWN")
        .. "; embeddedBaseIDHint=" .. (embeddedBaseIDHint and tostring(embeddedBaseIDHint) or "UNKNOWN")
        .. "; fallbackAPI=" .. (apiAvailable and "AVAILABLE" or "MISSING")
        .. "; fallbackState=" .. fallbackState
        .. "; fallbackItemID=" .. (fallbackID and tostring(fallbackID) or "UNKNOWN")
        .. "; reason=" .. reason
        .. "; embeddedDiagnostic={" .. embeddedDiagnostic .. "}"
        .. "; fallbackDiagnostic={" .. fallbackDiagnostic .. "})"
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
    local infoState, embeddedID, embeddedRef, embeddedBaseIDHint = "NIL", nil, nil, nil
    local ok, link = pcall(function() return info.hyperlink end)
    if not ok then infoState = "API_ERROR"
    elseif type(link) == "string" and link ~= "" then
        local parsed
        parsed, embeddedRef, embeddedID, infoState, embeddedBaseIDHint = pcall(ParseItemReference, link)
        if not parsed then embeddedRef, embeddedID, infoState, embeddedBaseIDHint = nil, nil, "API_ERROR", nil end
        if embeddedRef and embeddedID == id then
            return embeddedRef, embeddedID, "CONTAINER_INFO_HYPERLINK"
        elseif embeddedRef then infoState = "ID_MISMATCH"
        end
    elseif link ~= nil then infoState = "UNSUPPORTED_VALUE_TYPE"
    end
    local embeddedDiagnostic = SafeLinkDiagnostic(ok and link or nil)

    local apiAvailable = type(api.GetContainerItemLink) == "function"
    local slotAPIState, fallbackID, fallbackRef, fallbackValue = "API_MISSING", nil, nil, nil
    if apiAvailable then
        local linkOK, value = pcall(api.GetContainerItemLink, bag, slot)
        if linkOK then fallbackValue = value end
        if not linkOK then slotAPIState = "API_ERROR"
        elseif value == nil then slotAPIState = "NIL_RESULT"
        elseif type(value) ~= "string" or value == "" then slotAPIState = "UNSUPPORTED_VALUE_TYPE"
        else
            local parsed
            parsed, fallbackRef, fallbackID, slotAPIState = pcall(ParseItemReference, value)
            if not parsed then fallbackRef, fallbackID, slotAPIState = nil, nil, "API_ERROR"
            elseif fallbackRef and fallbackID ~= id then slotAPIState = "ID_MISMATCH" end
        end
    end
    local fallbackDiagnostic = SafeLinkDiagnostic(fallbackValue)

    -- A second, independently returned link can recover a missing or malformed
    -- embedded link only when its observed base ID matches the slot's itemID.
    -- A parseable disagreement between two link sources is retained as a hard
    -- contradiction rather than preferring either result.
    if fallbackRef and fallbackID == id then
        local embeddedEvidenceID = embeddedID or embeddedBaseIDHint
        if embeddedEvidenceID and embeddedEvidenceID ~= fallbackID then
            return nil, IdentityDetails(bag, slot, id, infoState, embeddedID,
                slotAPIState, fallbackID, apiAvailable, "EMBEDDED_AND_FALLBACK_DISAGREE",
                embeddedDiagnostic, fallbackDiagnostic, embeddedBaseIDHint), nil
        end
        local diagnostics
        if infoState ~= "NIL" then
            diagnostics = { embeddedState = infoState, embeddedItemID = embeddedID,
                fallbackState = "OBSERVED_MATCH", fallbackItemID = fallbackID,
                fallbackAPI = "AVAILABLE", embeddedDiagnostic = embeddedDiagnostic,
                fallbackDiagnostic = fallbackDiagnostic,
                reason = "EMBEDDED_LINK_UNUSABLE_FALLBACK_MATCHED_SLOT_ID" }
        end
        return fallbackRef, fallbackID, "C_Container.GetContainerItemLink", nil, diagnostics
    end

    local embeddedEvidenceID = embeddedID or embeddedBaseIDHint
    local reason = embeddedEvidenceID and fallbackID and embeddedEvidenceID ~= fallbackID
        and "EMBEDDED_AND_FALLBACK_DISAGREE"
        or fallbackRef and fallbackID ~= id and "FALLBACK_ID_MISMATCH"
        or "NO_VALID_EXACT_LINK_MATCHES_SLOT_ID"
    return nil, IdentityDetails(bag, slot, id, infoState, embeddedID,
        slotAPIState, fallbackID, apiAvailable, reason, embeddedDiagnostic, fallbackDiagnostic,
        embeddedBaseIDHint), nil
end

S.collectors.bags = function()
    local api = type(C_Container) == "table" and C_Container or {}
    if type(api.GetContainerNumSlots) ~= "function" or type(api.GetContainerItemInfo) ~= "function" then
        return Failed("carried-container APIs unavailable", false)
    end
    local issues, containers, observedSlots, failures = {}, {}, {}, {}
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
                local count = F.Number("Carried item stack count", Field(info, "stackCount"), issues)
                if not ref and (not count or count == 0) then return Failed("carried item quantity unknown", true) end
                local item = { itemID = ref and (id or linkID) or id, count = count }
                local infoFn = type(C_Item) == "table" and C_Item.GetItemInfo or GetItemInfo
                if type(infoFn) == "function" then
                    local infoOK, name, itemLink, quality, itemLevel, requiredLevel, minLevel, itemType, subType,
                        maxStack, equipLoc, texture, classID, subClassID = pcall(infoFn, ref or id)
                    if infoOK then
                        if not name then quality, classID, subClassID, equipLoc, requiredLevel = nil, nil, nil, nil, nil end
                        item.quality, item.classID, item.subClassID, item.equipLoc, item.requiredLevel = quality, classID, subClassID, equipLoc, requiredLevel
                        item.itemMetadataState = name and quality ~= nil and classID ~= nil and subClassID ~= nil and equipLoc ~= nil and requiredLevel ~= nil and "OBSERVED" or "UNKNOWN"
                        if item.itemMetadataState == "UNKNOWN" then issues[#issues + 1] = "Carried item metadata unknown" end
                        if classID == 9 and type(WoWSyncCompat.ReadRecipeTooltip) == "function" and type(GetLocale) == "function" and GetLocale() == "enUS" then
                            local tipOK, recipe, known = pcall(WoWSyncCompat.ReadRecipeTooltip, ref or id)
                            if tipOK then item.requiredProfession, item.requiredSkill, item.recipeAlreadyKnown = recipe and recipe.profession, recipe and recipe.skill, known end
                        end
                    else item.itemMetadataState = "UNKNOWN"; issues[#issues + 1] = "Carried item metadata unknown" end
                else item.itemMetadataState = "UNKNOWN"; issues[#issues + 1] = "Carried item metadata unknown" end
                if ref then
                    item.itemString, item.itemStringSource = ref, linkSource
                    item.itemIdentityState = "OBSERVED_EXACT_ITEM_STRING"
                else
                    item.itemIdentityState = "UNKNOWN"
                    item.itemIdentityReason = linkID
                    item.identityDiagnostics = { reason = linkID }
                    failures[#failures + 1] = { bag = bag, slot = slot, itemID = id,
                        reason = linkID }
                end
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
                    identityState = item.itemIdentityState, identityReason = item.itemIdentityReason,
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
                local identityMatches = expected.identityState == "UNKNOWN"
                    and not ref and linkID == expected.identityReason
                    or expected.identityState == "OBSERVED_EXACT_ITEM_STRING"
                    and ref and ref == expected.itemString
                local reportedIDMatches = expected.identityState == "UNKNOWN"
                    and id == expected.itemID or expected.identityState == "OBSERVED_EXACT_ITEM_STRING"
                    and (id or linkID) == expected.itemID
                if not identityMatches or not reportedIDMatches
                    or count ~= expected.count or locked ~= false
                    or bindingState ~= expected.bindingState or bound ~= expected.bound then
                    return Failed("carried-container changed during capture at bag " .. bag .. " slot " .. slot, true)
                end
            end
        end
    end
    return { containers = containers, formatVersion = 2 }, { completeness = (#issues > 0 or #failures > 0) and "partial" or "complete",
        partial = #failures > 0 or nil, slotFailures = #failures > 0 and failures or nil,
        reason = #issues > 0 and table.concat(issues, "; ") or nil }
end
