-- Synthetic API fixtures based on the 70245 runtime shape; none of these
-- synthetic item rows are presented as additional live Hallo observations.
return function(S, check, equal)
    local oldAPI = C_Container
    local capacities = { [0] = 20, [1] = 6, [2] = 6, [3] = 6, [4] = 0, [5] = 0 }
    local inventory = {
        [0] = {
            { itemID = 6948, itemName = "Hearthstone", hyperlink = "|cnIQ1:|Hitem:6948::::::::8:1485::75:::::::|h[Hearthstone]|h|r", stackCount = 1, isBound = true, isLocked = false },
            { itemID = 279960, itemName = "Lodestone", hyperlink = "|cnIQ1:|Hitem:279960::::::::8:1485:::::::::|h[Lodestone]|h|r", stackCount = 3, isBound = false, isLocked = false },
        },
    }
    C_Container = {
        GetContainerNumSlots = function(bag) return capacities[bag] end,
        GetContainerItemInfo = function(bag, slot) return inventory[bag] and inventory[bag][slot] end,
    }
    local data, meta = S.collectors.bags()
    equal(#data.containers, 6, "observed 70245 carried range retained")
    equal(data.containers[1].capacity, 20, "observed backpack capacity")
    equal(data.containers[1].free, 18, "free slots derived from full observed scan")
    equal(data.containers[1].slots[1].itemString, "item:6948::::::::8:1485::75:::::::", "full item string retained")
    equal(data.containers[1].slots[1].bound, true, "binding facet retained")
    equal(data.containers[1].slots[2].count, 3, "physical stack count retained")
    equal(data.containers[1].slots[2].bound, false, "explicit false binding retained")
    equal(meta.completeness, "complete", "fully scanned synthetic 70245 bag snapshot")
    S.RequestSync()
    local rendered = S.RenderSection("bags", { sections = { bags = { data = data } } })
    check(rendered:find("item:6948::::::::8:1485::75:::::::\tHearthstone\t1\tyes", 1, true),
        "canonical export keeps exact bound stack evidence")
    check(rendered:find("item:279960::::::::8:1485:::::::::\tLodestone\t3\tno", 1, true),
        "canonical export keeps unbound stack evidence separately")

    inventory[0][3] = { itemID = 279960, itemName = "Lodestone", hyperlink = "|Hitem:279960:2:0|h[Lodestone]|h", stackCount = 1, isBound = false, isLocked = false }
    local emptyMeta
    data, emptyMeta = S.collectors.bags()
    equal(data.containers[1].slots[2].itemID, data.containers[1].slots[3].itemID,
        "same item ID can occupy distinct physical slots")
    check(data.containers[1].slots[2].itemString ~= data.containers[1].slots[3].itemString,
        "distinct item variants retain distinct exact item strings")

    inventory[0][3] = { itemID = 279960, itemName = "Lodestone", hyperlink = "|Hitem:279960:2:0|h[Lodestone]|h", stackCount = 1, isLocked = false }
    local partial, partialMeta = S.collectors.bags()
    equal(partial.containers[1].slots[3].bound, nil, "missing binding facet remains nil")
    equal(partial.containers[1].slots[3].bindingState, "UNKNOWN", "nil binding is explicitly unknown")
    equal(partialMeta.completeness, "partial", "nil binding marks the section partial")
    inventory[0][3] = setmetatable({ itemID = 279960, itemName = "Lodestone", hyperlink = "|Hitem:279960:2:0|h[Lodestone]|h", stackCount = 1, isLocked = false }, {
        __index = function(_, key) if key == "isBound" then error("synthetic binding read failure") end end,
    })
    partial = S.collectors.bags()
    equal(partial.containers[1].slots[3].bound, nil, "binding field error is not false")
    equal(partial.containers[1].slots[3].bindingState, "API_ERROR", "binding API error retained distinctly")

    inventory = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
    capacities = { [0] = 20, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
    data = S.collectors.bags()
    equal(data.containers[1].free, 20, "observed nil slots remain empty slot observations")
    equal(data.containers[2].capacity, 0, "zero-capacity carried bag retained")
    equal(emptyMeta.completeness, "complete", "empty carried bag scan has explicit successful observations")
    inventory, capacities = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} },
        { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
    data = S.collectors.bags()
    equal(data.containers[1].free, 0, "zero-capacity backpack does not fabricate free slots")

    capacities = { [0] = 20, [1] = 6, [2] = 6, [3] = 6, [4] = 0, [5] = 0 }
    inventory = { [0] = {
        { itemID = 6948, itemName = "Hearthstone", hyperlink = "|Hitem:6948::::::::8:1485::75:::::::|h[Hearthstone]|h", stackCount = 1, isBound = true, isLocked = false },
        { itemID = 279960, itemName = "Lodestone", hyperlink = "|Hitem:279960::::::::8:1485:::::::::|h[Lodestone]|h", stackCount = 3, isBound = false, isLocked = false },
    } }
    local oldInfo = C_Container.GetContainerItemInfo
    C_Container.GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then error("synthetic container API failure") end
        return oldInfo(bag, slot)
    end
    equal(S.collectors.bags(), nil, "container API error is not interpreted as an empty slot")
    local calls = 0
    C_Container.GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then
            calls = calls + 1
            if calls == 2 then return nil end -- change only on the verification pass
        end
        return oldInfo(bag, slot)
    end
    equal(S.collectors.bags(), nil, "slot changing during scan fails closed")
    C_Container.GetContainerItemInfo = oldInfo
    C_Container.GetContainerItemInfo = function(_, slot)
        if slot == 1 then return { itemID = 1, itemName = "bad", hyperlink = "item:2", stackCount = 1, isLocked = false } end
    end
    equal(S.collectors.bags().containers[1].slots[1].itemString, nil, "mismatched link never becomes exact identity")
    local exactFallback = "|Hitem:6948:4:5:6|h[Exact Variant]|h"
    C_Container.GetContainerItemInfo = function(bag, slot)
        local source, info = oldInfo(bag, slot), {}
        if source then for key, value in pairs(source) do info[key] = value end end
        if bag == 0 and slot == 1 then info.hyperlink = nil end
        return source and info or nil
    end
    C_Container.GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then return exactFallback end
        return oldInfo(bag, slot).hyperlink
    end
    local fallback, fallbackMeta = S.collectors.bags()
    equal(fallback.containers[1].slots[1].itemString, "item:6948:4:5:6",
        "slot-link API supplies an observed exact variant when info.hyperlink is absent")
    equal(fallback.containers[1].slots[1].itemStringSource, "C_Container.GetContainerItemLink",
        "exact link source is recorded")
    equal(fallbackMeta.completeness, "complete", "supported exact link fallback keeps successful scan complete")

    -- A malformed embedded link may be independently recovered from the same
    -- slot API, but the discrepancy is retained and the section is partial.
    C_Container.GetContainerItemInfo = function(bag, slot)
        local source, info = oldInfo(bag, slot), {}
        if source then for key, value in pairs(source) do info[key] = value end end
        if bag == 0 and slot == 1 then info.hyperlink = "not-an-item-link" end
        return source and info or nil
    end
    C_Container.GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then return exactFallback end
        return oldInfo(bag, slot).hyperlink
    end
    local recovered, recoveredMeta = S.collectors.bags()
    equal(recovered.containers[1].slots[1].itemString, "item:6948:4:5:6",
        "valid fallback is accepted after malformed embedded link")
    equal(recovered.containers[1].slots[1].identityDiagnostics.embeddedState, "UNRECOGNIZED_FORMAT",
        "malformed embedded-link state is preserved")
    equal(recovered.containers[1].slots[1].identityDiagnostics.fallbackItemID, 6948,
        "fallback base item identity is recorded")
    equal(recoveredMeta.completeness, "partial", "recovered embedded-link defect marks the section partial")

    -- A parsed contradiction is never resolved by choosing one link, even if
    -- the fallback happens to agree with the reported slot itemID.
    C_Container.GetContainerItemInfo = function(bag, slot)
        local source, info = oldInfo(bag, slot), {}
        if source then for key, value in pairs(source) do info[key] = value end end
        if bag == 0 and slot == 1 then info.hyperlink = "|Hitem:999:8:7|h[Contradiction]|h" end
        return source and info or nil
    end
    C_Container.GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then return exactFallback end
        return oldInfo(bag, slot).hyperlink
    end
    local embeddedFallbackConflict, embeddedFallbackConflictMeta = S.collectors.bags()
    check(embeddedFallbackConflict and embeddedFallbackConflict.containers[1].slots[1].itemString == nil, "conflicting links isolate the slot")
    check(embeddedFallbackConflictMeta.slotFailures[1].reason:find("reportedItemID=6948", 1, true)
        and embeddedFallbackConflictMeta.slotFailures[1].reason:find("embeddedItemID=999", 1, true)
        and embeddedFallbackConflictMeta.slotFailures[1].reason:find("fallbackItemID=6948", 1, true)
        and embeddedFallbackConflictMeta.slotFailures[1].reason:find("EMBEDDED_AND_FALLBACK_DISAGREE", 1, true),
        "contradiction diagnostic includes slot and both independently parsed IDs")

    -- A malformed payload can still expose a base-ID hint. Keep it only as
    -- contradictory evidence; it must never be accepted as an item identity.
    C_Container.GetContainerItemInfo = function(bag, slot)
        local source, info = oldInfo(bag, slot), {}
        if source then for key, value in pairs(source) do info[key] = value end end
        if bag == 0 and slot == 1 then info.hyperlink = "|Hitem:999:bad|h[Malformed]|h" end
        return source and info or nil
    end
    C_Container.GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then return exactFallback end
        return oldInfo(bag, slot).hyperlink
    end
    local malformedConflict, malformedConflictMeta = S.collectors.bags()
    check(malformedConflict and malformedConflict.containers[1].slots[1].itemString == nil, "malformed contradiction isolates the slot")
    check(malformedConflictMeta.slotFailures[1].reason:find("embeddedItemID=UNKNOWN", 1, true)
        and malformedConflictMeta.slotFailures[1].reason:find("embeddedBaseIDHint=999", 1, true)
        and malformedConflictMeta.slotFailures[1].reason:find("fallbackItemID=6948", 1, true)
        and malformedConflictMeta.slotFailures[1].reason:find("EMBEDDED_AND_FALLBACK_DISAGREE", 1, true),
        "malformed ID is retained only as a hint in fail-closed diagnostics")

    -- A valid embedded hyperlink remains preferred and does not call the
    -- fallback API unnecessarily.
    C_Container.GetContainerItemInfo = oldInfo
    local linkCalls = 0
    C_Container.GetContainerItemLink = function(bag, slot)
        linkCalls = linkCalls + 1
        return oldInfo(bag, slot).hyperlink
    end
    local embeddedPreferred = S.collectors.bags()
    check(embeddedPreferred and embeddedPreferred.containers[1].slots[1].itemStringSource == "CONTAINER_INFO_HYPERLINK",
        "valid embedded link retains its source")
    equal(linkCalls, 0, "fallback API is not called when embedded exact identity validates")

    local supportedLinks = {
        { "|cffa335ee|Hitem:6948:4:5:6|h[Hearthstone]|h|r", "item:6948:4:5:6", "colored standard wrapper" },
        { "|Hitem:6948:4:5:6|h[Hearthstone]|h", "item:6948:4:5:6", "hyperlink wrapper" },
        { "item:6948:4:5:6", "item:6948:4:5:6", "plain item string" },
        { "|Hitem:6948:1:2:3:4:5:6:7:8:9:10:11:12:13|h[Variant]|h",
            "item:6948:1:2:3:4:5:6:7:8:9:10:11:12:13", "extended variant fields" },
        { "item:6948", "item:6948", "omitted optional item fields" },
    }
    for _, fixture in ipairs(supportedLinks) do
        C_Container.GetContainerItemInfo = function(bag, slot)
            local source, info = oldInfo(bag, slot), {}
            if source then for key, value in pairs(source) do info[key] = value end end
            if bag == 0 and slot == 1 then info.hyperlink = fixture[1] end
            return source and info or nil
        end
        local parsed = S.collectors.bags()
        equal(parsed.containers[1].slots[1].itemString, fixture[2], fixture[3] .. " is preserved exactly")
    end

    local function failingLink(link)
        C_Container.GetContainerItemInfo = function(bag, slot)
            local source, info = oldInfo(bag, slot), {}
            if source then for key, value in pairs(source) do info[key] = value end end
            if bag == 0 and slot == 1 then info.hyperlink = link end
            return source and info or nil
        end
        C_Container.GetContainerItemLink = function(bag, slot)
            if bag == 0 and slot == 1 then return link end
            return oldInfo(bag, slot).hyperlink
        end
        return S.collectors.bags()
    end

    local escapedData, escapedMeta = failingLink("||Hitem:6948:4|h[Private Display]|h")
    check(escapedData and escapedData.containers[1].slots[1].itemString == nil, "escaped hyperlink delimiters are not treated as item identity")
    check(escapedMeta.slotFailures[1].reason:find("shape=ESCAPED_DELIMITER", 1, true)
        and not escapedMeta.slotFailures[1].reason:find("Private Display", 1, true),
        "escaped-link diagnostic identifies structure without recording display text")
    local escapedCloseData, escapedCloseMeta = failingLink("|Hitem:6948:4||h[Private Display]|h")
    check(escapedCloseData and escapedCloseData.containers[1].slots[1].itemString == nil, "escaped close cannot terminate item payload")
    check(escapedCloseMeta.slotFailures[1].reason:find("embeddedState=MALFORMED_ESCAPE", 1, true)
        and escapedCloseMeta.slotFailures[1].reason:find("shape=ESCAPED_DELIMITER", 1, true),
        "escaped close delimiter is diagnosed without relaxing parser acceptance")
    local nonItemData, nonItemMeta = failingLink("|Hspell:123|h[Private Display]|h")
    check(nonItemData and nonItemData.containers[1].slots[1].itemString == nil, "non-item hyperlinks do not satisfy item identity")
    check(nonItemMeta.slotFailures[1].reason:find("shape=NON_ITEM_HYPERLINK", 1, true)
        and not nonItemMeta.slotFailures[1].reason:find("Private Display", 1, true),
        "non-item hyperlink diagnostic is sanitized")
    C_Container.GetContainerItemInfo = function(bag, slot)
        local source, info = oldInfo(bag, slot), {}
        if source then for key, value in pairs(source) do info[key] = value end end
        if bag == 0 and slot == 1 then info.hyperlink = "unrecognized" end
        return source and info or nil
    end
    C_Container.GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then return { private = "must not persist" } end
        return oldInfo(bag, slot).hyperlink
    end
    local wrongTypeData, wrongTypeMeta = S.collectors.bags()
    check(wrongTypeData and wrongTypeData.containers[1].slots[1].itemString == nil, "non-string links do not satisfy exact identity")
    check(wrongTypeMeta.slotFailures[1].reason:find("fallbackState=UNSUPPORTED_VALUE_TYPE", 1, true)
        and wrongTypeMeta.slotFailures[1].reason:find("type=table;shape=NON_STRING", 1, true)
        and not wrongTypeMeta.slotFailures[1].reason:find("must not persist", 1, true),
        "non-string API diagnostics record only the type")
    local truncatedData, truncatedMeta = failingLink("|Hitem:6948:4:5")
    check(truncatedData and truncatedData.containers[1].slots[1].itemString == nil, "unterminated link is not accepted as exact variant")
    check(truncatedMeta.slotFailures[1].reason:find("embeddedState=TRUNCATED_ITEM_PAYLOAD", 1, true)
        and truncatedMeta.slotFailures[1].reason:find("shape=TRUNCATED_ITEM_PAYLOAD", 1, true),
        "truncated payload has explicit parser and format states")
    local oversized = string.rep("PrivateChatPayload", 40)
    local oversizedData, oversizedMeta = failingLink(oversized)
    check(oversizedData and oversizedData.containers[1].slots[1].itemString == nil, "unrecognized long values do not become identity")
    check(oversizedMeta.slotFailures[1].reason:find("length=160+", 1, true)
        and oversizedMeta.slotFailures[1].reason:find("shape=INSPECTION_LIMIT_REACHED", 1, true)
        and not oversizedMeta.slotFailures[1].reason:find("PrivateChatPayload", 1, true)
        and #oversizedMeta.slotFailures[1].reason < 1000,
        "diagnostics cap inspected text and persisted output while redacting raw values")

    C_Container.GetContainerItemInfo = function(bag, slot)
        local source, info = oldInfo(bag, slot), {}
        if source then for key, value in pairs(source) do info[key] = value end end
        if bag == 0 and slot == 1 then info.hyperlink = nil end
        return source and info or nil
    end
    C_Container.GetContainerItemLink = nil
    local unknownIdentity, identityMeta = S.collectors.bags()
    check(unknownIdentity and unknownIdentity.containers[1].slots[1].itemString == nil,
        "item ID alone never substitutes for exact item string, but raw slot is retained")
    equal(unknownIdentity.containers[1].slots[1].itemIdentityState, "UNKNOWN", "unresolved exact identity is explicit")
    equal(unknownIdentity.containers[1].slots[1].itemID, 6948, "reported item ID remains safe raw evidence")
    equal(identityMeta.completeness, "partial", "stable scan with unresolved exact identity is partial")
    equal(identityMeta.partial, true, "partial flag is surfaced for slot failures")
    equal(identityMeta.slotFailures[1].bag, 0, "slot failure identifies its bag")
    equal(identityMeta.slotFailures[1].slot, 1, "slot failure identifies its slot")
    check(identityMeta.slotFailures[1].reason:find("reportedItemID=6948", 1, true)
        and identityMeta.slotFailures[1].reason:find("fallbackAPI=MISSING", 1, true)
        and identityMeta.slotFailures[1].reason:find("fallbackState=API_MISSING", 1, true),
        "failed exact identity retains sanitized API diagnostics")
    C_Container.GetContainerItemLink = function() return nil end
    local noLinks, noLinksMeta = S.collectors.bags()
    check(noLinks and noLinks.containers[1].slots[1].itemString == nil,
        "nil embedded and slot links preserve raw row without synthesizing identity")
    check(noLinksMeta.slotFailures[1].reason:find("embeddedState=NIL", 1, true)
        and noLinksMeta.slotFailures[1].reason:find("fallbackState=NIL_RESULT", 1, true)
        and noLinksMeta.slotFailures[1].reason:find("NO_VALID_EXACT_LINK_MATCHES_SLOT_ID", 1, true),
        "both unavailable-link diagnostics preserve individual API states")
    C_Container.GetContainerItemLink = nil
    C_Container.GetContainerItemInfo = function(_, slot)
        if slot == 1 then return { itemID = 1, itemName = "moving", hyperlink = "item:1", stackCount = 1, isLocked = true } end
    end
    equal(S.collectors.bags(), nil, "moving item snapshot fails closed")
    C_Container.GetContainerItemInfo = oldInfo
    local observed, observedMeta = S.collectors.bags()
    S.Commit("bags", observed, observedMeta)
    local persisted = S.record.sections.bags.data
    equal(persisted.containers[1].id, 0, "structured SavedVariables retain the container identity")
    equal(persisted.containers[1].slots[1].itemString, "item:6948::::::::8:1485::75:::::::",
        "structured SavedVariables retain the exact variant at its physical slot")
    equal(persisted.containers[1].slots[1].count, 1, "structured slot keeps its own stack quantity")
    equal(persisted.containers[1].slots[1].bindingState, "OBSERVED_TRUE",
        "structured slot retains binding provenance independently")
    C_Container.GetContainerNumSlots = nil
    local failed, failedMeta = S.collectors.bags()
    equal(failed, nil, "missing carried API fails the new capture")
    equal(failedMeta.stale, true, "failed 70245 bag capture marks preserved evidence stale")
    S.Attempt("bags", failedMeta.reason, failedMeta.stale)
    local stale = S.RenderSection("bags", S.GetSnapshot())
    check(stale:find("State: LAST_SEEN", 1, true), "previous bag evidence is not labeled current after failure")
    check(stale:find("RefreshIssue:", 1, true), "failed capture reason is exported")
    C_Container, issecretvalue = oldAPI, nil
end
