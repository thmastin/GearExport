-- Synthetic API-contract fixtures, not Hallo's equipment or real item data.
return function(S, check, equal, advance)
    local slotNames = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
        [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2",
        [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard" }
    local itemAPI, paperAPI, locations = C_Item, C_PaperDollInfo, ItemLocation
    local occupied, pending, secret = { [5] = true }, false, {}
    local restricted = issecretvalue
    issecretvalue = function(value) return value == secret end
    C_PaperDollInfo = { GetInventorySlotInfoForInvSlot = function(slot) return slot end }
    ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
    C_Item = {
        DoesItemExist = function(location) return occupied[location.slot] == true end,
        GetItemID = function() return 900001 end,
        GetItemLink = function() if not pending then return "|Hitem:900001:7:0:0|h[Synthetic tunic]|h" end end,
        GetCurrentItemLevel = function() if not pending then return 12 end end,
        GetItemInfo = function(ref)
            if pending then return nil end
            if type(ref) == "string" then equal(ref, "|Hitem:900001:7:0:0|h[Synthetic tunic]|h", "metadata uses equipped variant")
            else equal(ref, 900001, "metadata falls back to observed base item ID without fabricating a variant") end
            return "Synthetic tunic", type(ref) == "string" and ref or nil, 1, 99, 0
        end,
        RequestLoadItemDataByID = function(id) equal(id, 900001, "uncached item load request uses observed ID") end,
        GetItemStats = function() error("70291 effective stat semantics are not verified") end,
    }
    local data, meta = S.collectors.equipment()
    equal(data.slots[5].itemID, 900001, "equipped identity")
    equal(data.slots[5].itemString, "item:900001:7:0:0", "variant retained")
    equal(data.slots[5].name, "Synthetic tunic", "equipped name")
    equal(data.slots[5].itemLevel, 12, "location level, not generic level 99")
    equal(data.slots[5].requiredLevel, 0, "known zero required level")
    equal(data.slots[5].stats, nil, "70291 effective stat semantics remain unknown")
    equal(data.slots[1], nil, "explicit false presence is empty")
    equal(meta.completeness, "partial", "unverified effective stats keep the section partial")
    check(not meta.retry, "semantic unknown does not cause a retry loop")
    S.RequestSync(); advance(1)
    local text = S.RenderSection("equipment", S.GetSnapshot())
    check(text:find("slot\titemRef\tname\tilvl\trequiredLevel\teffectiveStats", 1, true), "shared contract header")
    check(text:find("5:Chest\titem:900001:7:0:0\tSynthetic tunic\t12\t0\t?", 1, true), "human-readable Forever slot and unknown effective stats render")
    check(S.eventFrame.events.PLAYER_EQUIPMENT_CHANGED, "equipment event registered")
    check(S.eventFrame.events.ITEM_DATA_LOAD_RESULT, "item cache event registered")
    pending = true
    S.eventFrame.scripts.OnEvent(S.eventFrame, "PLAYER_EQUIPMENT_CHANGED", 5)
    advance(1)
    equal(S.record.sections.equipment.data.slots[5].name, nil, "pending metadata clears previous name")
    equal(S.record.sections.equipment.data.slots[5].itemID, 900001, "pending metadata keeps observed ID")
    pending = false
    S.eventFrame.scripts.OnEvent(S.eventFrame, "ITEM_DATA_LOAD_RESULT", 900001, true)
    advance(3)
    equal(S.record.sections.equipment.data.slots[5].name, "Synthetic tunic", "delayed cache data captured")
    occupied = {}
    S.eventFrame.scripts.OnEvent(S.eventFrame, "UNIT_INVENTORY_CHANGED", "player")
    advance(1)
    data = S.record.sections.equipment.data
    equal(next(data.slots), nil, "observed empty equipment removes old item")
    equal(S.record.sections.equipment.completeness, "complete", "all explicitly empty is observed complete")
    local presence = C_Item.DoesItemExist
    C_Item.DoesItemExist = function(location) if location.slot == 1 then return secret end; return false end
    data, meta = S.collectors.equipment()
    check(data.slots[1] ~= nil, "restricted presence cannot become EMPTY")
    equal(data.slots[1].itemID, nil, "restricted presence cannot fabricate identity")
    equal(meta.completeness, "partial", "partial slot availability")
    C_Item.DoesItemExist = function() error("API unavailable") end
    equal(S.collectors.equipment(), nil, "all presence calls fail: UNKNOWN section")
    C_Item.DoesItemExist = presence
    occupied = { [5] = true }
    C_Item.GetCurrentItemLevel = function() return secret end
    C_Item.GetItemInfo = function() return secret, nil, nil, 99, -1 end
    data = S.collectors.equipment()
    equal(data.slots[5].name, nil, "restricted name unknown")
    equal(data.slots[5].itemLevel, nil, "restricted level unknown")
    equal(data.slots[5].requiredLevel, nil, "invalid required level unknown")
    C_Item.GetItemLink = function() return "|Hitem:900002:0|h[Different item]|h" end
    data = S.collectors.equipment()
    equal(data.slots[5].itemString, nil, "inconsistent identity rejects variant")
    equal(data.slots[5].itemID, 900001, "independent location ID preserved")
    C_Item.GetItemLink = function() return "item:900001:garbage" end
    data = S.collectors.equipment()
    equal(data.slots[5].itemString, nil, "malformed item string is not truncated into an identity")
    C_PaperDollInfo.GetInventorySlotInfoForInvSlot = function(slot) return slot + 1 end
    equal(S.collectors.equipment(), nil, "changed slot mapping is UNKNOWN")
    C_PaperDollInfo = nil
    equal(S.collectors.equipment(), nil, "missing slot API is UNKNOWN")
    local _, unavailableMeta = S.collectors.equipment()
    equal(unavailableMeta.stale, true, "failed 70245 equipment capture marks prior evidence stale")
    -- Replay the user's real level-6 equipment values. The API wrappers are
    -- mocks; the item references/metadata and empty slots are real evidence.
    local real = assert(loadfile("tests/fixtures/forever/hallo-level6-equipment.lua"))()
    C_PaperDollInfo = { GetInventorySlotInfoForInvSlot = function(slot) return slot end }
    C_Item = {
        DoesItemExist = function(location) return real[location.slot] ~= nil end,
        GetItemID = function(location) return tonumber(real[location.slot][1]:match("item:(%d+)")) end,
        GetItemLink = function(location) return real[location.slot][1] end,
        GetCurrentItemLevel = function(location) return real[location.slot][3] end,
        GetItemInfo = function(link)
            if type(link) == "number" then return nil end
            for _, row in pairs(real) do
                if row[1] == link then return row[2], link, nil, nil, row[4] end
            end
            error("Unexpected reference")
        end, GetItemStats = function() error("must not query unverified stat semantics") end,
    }
    data, meta = S.collectors.equipment()
    local actual = S.RenderSection("equipment", { sections = { equipment = {
        data = data, completeness = meta.completeness, reason = meta.reason,
        observedAt = 1789704998,
    } } })
    for slot = 1, 19 do
        local row = real[slot]
        local expected = slot .. ":" .. slotNames[slot] .. "\tEMPTY"
        if row then
            expected = slot .. ":" .. slotNames[slot] .. "\t" .. table.concat(row, "\t") .. "\t?"
            equal(data.slots[slot].stats, nil, "equipped effective stats remain unknown")
        end
        check(("\n" .. actual .. "\n"):find("\n" .. expected .. "\n", 1, true),
            "real level-6 equipment row matches: " .. slot)
    end
    equal(meta.completeness, "partial", "real equipment coverage remains partial")
    C_Item, C_PaperDollInfo, ItemLocation, issecretvalue = itemAPI, paperAPI, locations, restricted
end
