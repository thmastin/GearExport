-- Synthetic API-contract fixtures, not Hallo's equipment or real item data.
return function(S, check, equal, advance)
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
        GetItemInfo = function(link)
            equal(link, "|Hitem:900001:7:0:0|h[Synthetic tunic]|h", "metadata uses equipped variant")
            return "Synthetic tunic", link, 1, 99, 0
        end,
        GetItemStats = function() error("Unverified effective stats must not be read") end,
    }
    local data, meta = S.collectors.equipment()
    equal(data.slots[5].itemID, 900001, "equipped identity")
    equal(data.slots[5].itemString, "item:900001:7:0:0", "variant retained")
    equal(data.slots[5].name, "Synthetic tunic", "equipped name")
    equal(data.slots[5].itemLevel, 12, "location level, not generic level 99")
    equal(data.slots[5].requiredLevel, 0, "known zero required level")
    equal(data.slots[5].stats, nil, "effective stats unknown pending runtime evidence")
    equal(data.slots[1], nil, "explicit false presence is empty")
    equal(meta.completeness, "partial", "unverified stats keep coverage partial")
    check(not meta.retry, "unverified stats do not cause pointless retries")
    S.RequestSync(); advance(1)
    local text = S.RenderSection("equipment", S.GetSnapshot())
    check(text:find("slot\titemRef\tname\tilvl\trequiredLevel\teffectiveStats", 1, true), "shared contract header")
    check(text:find("5:\titem:900001:7:0:0\tSynthetic tunic\t12\t0\t?", 1, true), "canonical equipment row")
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
            for _, row in pairs(real) do
                if row[1] == link then return row[2], link, nil, nil, row[4] end
            end
            error("Unexpected reference")
        end,
    }
    data, meta = S.collectors.equipment()
    local actual = S.RenderSection("equipment", { sections = { equipment = {
        data = data, completeness = meta.completeness, reason = meta.reason,
        observedAt = 1789704998,
    } } })
    for slot = 1, 19 do
        local row = real[slot]
        local expected = slot .. ":\tEMPTY"
        if row then
            expected = slot .. ":\t" .. table.concat(row, "\t") .. "\t?"
            equal(data.slots[slot].stats, nil, "real equipment stats remain unknown")
        end
        check(("\n" .. actual .. "\n"):find("\n" .. expected .. "\n", 1, true),
            "real level-6 equipment row matches: " .. slot)
    end
    equal(meta.completeness, "partial", "real equipment coverage remains partial")
    C_Item, C_PaperDollInfo, ItemLocation, issecretvalue = itemAPI, paperAPI, locations, restricted
end
