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
    equal(S.collectors.bags(), nil, "mismatched item ID and hyperlink fail closed")
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
