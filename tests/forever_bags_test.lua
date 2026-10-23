-- Synthetic build-70009 API shapes, not invented Hallo bag contents.
return function(S, check, equal, advance)
    local savedContainer, savedItem, savedLocation, savedConstants, savedEnum, savedSecret =
        C_Container, C_Item, ItemLocation, Constants, Enum, issecretvalue
    local secret, priceMissing = {}, false
    issecretvalue = function(value) return value == secret end
    Constants = { InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 } }
    Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 } }
    local capacity = { [0] = 3, 2, 0, 0, 0, 1 }
    local contents = { [0] = {
        { itemID = 900101, hyperlink = "item:900101:0", itemName = "Synthetic item", stackCount = 2, isBound = false, isLocked = false },
        { itemID = 900101, hyperlink = "item:900101:0", itemName = "Synthetic item", stackCount = 3, isBound = true, isLocked = false },
    }, [1] = {
        { itemID = 900101, hyperlink = "item:900101:7", itemName = "Synthetic variant", stackCount = 1, isBound = false, isLocked = false },
    } }
    local visited = {}
    local function Free(bag)
        local count = 0
        for _ in pairs(contents[bag] or {}) do count = count + 1 end
        return capacity[bag] - count, 0
    end
    C_Container = {
        GetContainerNumSlots = function(bag)
            check(bag >= 0 and bag <= 5, "never reads bank/keyring")
            visited[bag] = true; return capacity[bag]
        end,
        GetContainerNumFreeSlots = function(bag) return Free(bag) end,
        ContainerIDToInventoryID = function(bag) return 20 + bag end,
        GetContainerItemInfo = function(bag, slot) return (contents[bag] or {})[slot] end,
    }
    ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
    C_Item = {
        DoesItemExist = function(location) return capacity[location.slot - 20] > 0 end,
        GetItemID = function(location) return 910000 + location.slot end,
        GetItemLink = function(location) return "item:" .. (910000 + location.slot) .. ":0" end,
        GetItemInfo = function(reference)
            return "Synthetic bag/item", reference, nil, nil, nil, nil, nil, nil, nil, nil,
                not priceMissing and 0 or nil
        end,
    }
    local data, meta = S.collectors.bags()
    equal(#data.containers, 6, "runtime carried range includes enabled reagent bag")
    equal(meta.completeness, "complete", "fully observed bag state")
    equal(data.containers[1].capacity, 3, "backpack capacity")
    equal(data.containers[1].free, 1, "observed free slots")
    equal(data.containers[2].bag.itemString, "item:910021:0", "bag identity uses inventory mapping")
    equal(data.containers[2].bag.name, "Synthetic bag/item", "bag name observed")
    equal(data.containers[3].bag, nil, "confirmed missing bag")
    equal(data.containers[1].slots[1].count, 2, "quantity")
    equal(data.containers[1].slots[1].vendorCopper, 0, "known zero vendor value")
    equal(data.containers[1].slots[1].bound, false, "known unbound")
    S.RequestSync(); advance(3)
    local text = S.RenderSection("bags", S.GetSnapshot())
    check(text:find("Slots: 3 free / 6", 1, true), "canonical bag totals")
    check(text:find("container\tcapacity\tfree\tfamily\tbagRef", 1, true), "unchanged container schema")
    check(text:find("itemRef\tname\tqty\tbound\tvendorEachCopper", 1, true), "unchanged item schema")
    check(text:find("item:900101:0\tSynthetic item\t2\tno\t0", 1, true), "unbound stacks remain separate")
    check(text:find("item:900101:0\tSynthetic item\t3\tyes\t0", 1, true), "binding distinctions preserved")
    check(text:find("item:900101:7\tSynthetic variant\t1\tno\t0", 1, true), "variant distinctions preserved")
    local frozen = S.GetSnapshot()
    equal(S.RenderSection("bags", frozen), S.RenderSection("bags", frozen), "deterministic frozen bags")
    check(S.eventFrame.events.BAG_UPDATE and S.eventFrame.events.BAG_UPDATE_DELAYED
        and S.eventFrame.events.ITEM_LOCK_CHANGED, "bag refresh events registered")
    priceMissing = true
    contents[0][1].itemName, contents[0][1].isBound = nil, nil
    data, meta = S.collectors.bags()
    equal(meta.completeness, "partial", "missing metadata keeps structural observation")
    equal(data.containers[1].slots[1].name, nil, "missing name unknown")
    equal(data.containers[1].slots[1].bound, nil, "missing binding unknown")
    equal(data.containers[1].slots[1].vendorCopper, nil, "missing price never zero")
    S.eventFrame.scripts.OnEvent(S.eventFrame, "BAG_UPDATE", 0); advance(1)
    equal(S.record.sections.bags.completeness, "partial", "event captures partial metadata")
    priceMissing = false
    contents[0][1].itemName, contents[0][1].isBound = "Synthetic item", false
    S.eventFrame.scripts.OnEvent(S.eventFrame, "GET_ITEM_INFO_RECEIVED", 900101, true); advance(3)
    equal(S.record.sections.bags.completeness, "complete", "metadata readiness refreshes bags")
    contents[0][1].stackCount = secret
    equal(S.collectors.bags(), nil, "restricted quantity cannot become zero")
    contents[0][1].stackCount = 0
    equal(S.collectors.bags(), nil, "zero quantity on occupied slot is unavailable")
    contents[0][1].stackCount = 2
    contents[0][1].isLocked = true
    equal(S.collectors.bags(), nil, "moving items are not captured")
    S.eventFrame.scripts.OnEvent(S.eventFrame, "ITEM_LOCK_CHANGED", 0, 1); advance(1)
    equal(S.record.sections.bags.data.containers[1].slots[1].count, 2, "failed refresh preserves last observation")
    check(S.record.sections.bags.lastAttemptError ~= nil, "failed refresh is explicitly reported")
    contents[0][1].isLocked = false
    contents[0][1].itemID, contents[0][1].hyperlink = nil, nil
    equal(S.collectors.bags(), nil, "unidentified item is not dropped")
    contents[0][1].itemID, contents[0][1].hyperlink = 900101, "item:900101:0"
    local originalInfo = C_Container.GetContainerItemInfo
    C_Container.GetContainerItemInfo = function() return nil end
    equal(S.collectors.bags(), nil, "nil slots contradicting free count are not empty")
    C_Container.GetContainerItemInfo = function() error("unavailable") end
    equal(S.collectors.bags(), nil, "throwing API is unknown")
    C_Container.GetContainerItemInfo = nil
    equal(S.collectors.bags(), nil, "missing API is unknown")
    C_Container.GetContainerItemInfo = function() return secret end
    equal(S.collectors.bags(), nil, "restricted record unknown")
    C_Container.GetContainerItemInfo = originalInfo
    local free = C_Container.GetContainerNumFreeSlots
    C_Container.GetContainerNumFreeSlots = function() return 100, 0 end
    equal(S.collectors.bags(), nil, "invalid free count rejected")
    C_Container.GetContainerNumFreeSlots = function() return nil end
    equal(S.collectors.bags(), nil, "missing free count not guessed")
    C_Container.GetContainerNumFreeSlots = free
    local present = C_Item.DoesItemExist
    C_Item.DoesItemExist = function() return true end
    equal(S.collectors.bags(), nil, "equipped bag with zero capacity is pending")
    C_Item.DoesItemExist = present
    local bagLink = C_Item.GetItemLink
    C_Item.GetItemLink = function() return nil end
    data, meta = S.collectors.bags()
    equal(data.containers[2].bag.itemID, 910021, "uncached bag link keeps ID")
    equal(meta.completeness, "partial", "uncached bag identity partial")
    C_Item.GetItemLink = bagLink
    local calls = 0
    C_Container.GetContainerNumFreeSlots = function(bag)
        if bag == 0 then calls = calls + 1; if calls == 3 then return 2, 0 end end
        return Free(bag)
    end
    equal(S.collectors.bags(), nil, "changing counts during capture rejected")
    C_Container.GetContainerNumFreeSlots = free
    contents = {}
    S.eventFrame.scripts.OnEvent(S.eventFrame, "BAG_UPDATE_DELAYED"); advance(3)
    text = S.RenderSection("bags", S.GetSnapshot())
    check(text:find("Items: EMPTY", 1, true), "observed empty is distinct from unknown")
    equal(S.record.sections.bags.completeness, "complete", "observed empty complete")
    Constants.InventoryConstants.NumReagentBagSlots = 0
    visited = {}; data = S.collectors.bags()
    equal(#data.containers, 5, "no reagent bag assumed when client disables it")
    check(not visited[5], "disabled reagent container not scanned")
    Constants.InventoryConstants.NumBagSlots = 7
    equal(S.collectors.bags(), nil, "changed bag range rejected")
    Constants = nil
    equal(S.collectors.bags(), nil, "no guessed range without constants")
    C_Container, C_Item, ItemLocation, Constants, Enum, issecretvalue =
        savedContainer, savedItem, savedLocation, savedConstants, savedEnum, savedSecret
end
