-- Additive item metadata is deduplicated by base item ID, never itemRef or
-- storage ownership. These are live Retail evidence fixtures, not an
-- expansion-name mapping.
return function(S, C, check, equal)
    local savedInstant = GetItemInfoInstant
    local savedRetail = C.IsRetail
    C.IsRetail = function() return true end
    GetItemInfoInstant = function(id)
        if id == 236949 then return id, "Trade Goods", "Parts", "", 1, 7, 11 end
    end
    local instant = C.GetItemMetadata(236949, nil, nil, 0, 11, true)
    equal(instant.classID, 7, "instant class ID fills an uncached full record")
    equal(instant.subclassID, 11, "instant subclass ID fills an uncached full record")
    equal(instant.bindType, 0, "raw bind type preserves zero")
    equal(instant.expansionID, 11, "raw expansion ID preserves live value")
    equal(instant.isCraftingReagent, true, "explicit reagent true preserved")
    GetItemInfoInstant = nil
    local unavailable = C.GetItemMetadata(999999, nil, nil, nil, nil, nil)
    equal(unavailable.classID, nil, "unavailable instant metadata remains unknown")
    GetItemInfoInstant, C.IsRetail = savedInstant, savedRetail

    local function Item(id, variant)
        return { itemID = id, itemString = "item:" .. id .. ":" .. (variant or "0"), count = 1 }
    end
    local snapshot = {
        schemaVersion = 1,
        sections = {
            equipment = { data = { slots = { [1] = Item(236949, "85:253") } } },
            bags = { completeness = "complete", data = { containers = { { id = 0, capacity = 2, free = 0,
                slots = { [1] = Item(89112), [2] = Item(236949, "86:253") } } } } },
            bank = { data = { containers = { { id = 6, slots = { [1] = Item(202071) } } } } },
        },
        accountSections = { bank = { data = { containers = { { id = 12, slots = { [1] = Item(210931), [2] = Item(236949, "0:0:1") } } } } } },
        guildSections = { bank = { data = { containers = { { id = 1, slots = { [1] = Item(187707) } } } } } },
        itemMetadata = {
            [89112] = { classID = 7, subclassID = 10, bindType = 0, expansionID = 4, isCraftingReagent = true },
            [187707] = { classID = 7, subclassID = 10, bindType = 0, expansionID = 8, isCraftingReagent = true },
            [202071] = { classID = 15, subclassID = 0, bindType = 0, expansionID = 9, isCraftingReagent = false },
            [210931] = { classID = 7, subclassID = 7, bindType = 0, expansionID = 10, isCraftingReagent = true },
            [236949] = { classID = 7, subclassID = 11, bindType = 0, expansionID = 11, isCraftingReagent = true },
        },
    }
    local text = assert(S.RenderSection("itemMetadata", snapshot))
    check(text:find("baseItemID\tclassID\tsubclassID\tbindType\texpansionID\tisCraftingReagent", 1, true), "metadata headers are stable")
    check(text:find("89112\t7\t10\t0\t4\tyes", 1, true), "Mote of Harmony raw evidence fixture")
    check(text:find("187707\t7\t10\t0\t8\tyes", 1, true), "Progenitor Essentia raw evidence fixture")
    check(text:find("202071\t15\t0\t0\t9\tno", 1, true), "Elemental Mote false reagent fixture")
    check(text:find("210931\t7\t7\t0\t10\tyes", 1, true), "Bismuth raw evidence fixture")
    check(text:find("236949\t7\t11\t0\t11\tyes", 1, true), "Mote of Light raw evidence fixture")
    local _, duplicates = text:gsub("236949\t", "")
    equal(duplicates, 1, "multiple itemRefs and storage locations deduplicate by base item ID")
    check(not text:find("Midnight", 1, true) and not text:find("Dragonflight", 1, true), "addon has no expansion-name mapping")
    local first = text:find("89112", 1, true)
    check(first < text:find("187707", 1, true) and text:find("187707", 1, true) < text:find("236949", 1, true),
        "metadata rows sort by numeric base item ID")

    snapshot.itemMetadata[202071] = nil
    local unknown = assert(S.RenderSection("itemMetadata", snapshot))
    check(unknown:find("202071\t?\t?\t?\t?\t?", 1, true), "missing metadata facets render explicit unknowns")
    local bagBefore = assert(S.RenderSection("bags", snapshot))
    snapshot.itemMetadata[89112].expansionID = 254
    equal(S.RenderSection("bags", snapshot), bagBefore, "metadata never changes existing inventory rows")
    local reordered = assert(S.RenderSection("itemMetadata", snapshot))
    check(reordered:find("89112\t7\t10\t0\t254\tyes", 1, true), "raw sentinel-like expansion value is preserved")
end
