local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Meta(issues)
    table.sort(issues)
    return { completeness = #issues > 0 and "partial" or "complete",
        reason = #issues > 0 and table.concat(issues, "; ") or nil }
end

-- Only mappings corroborated against Hallo's equipped-item tooltip belong
-- here. C_Item.GetItemStats remains an untyped variant, so unknown keys are
-- not exported merely because their values are numeric.
local FOREVER_EFFECTIVE_STATS = {
    RESISTANCE0_NAME = "Armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Damage Per Second",
}

local function ForeverEffectiveStats(link, itemAPI, issues, label)
    local values = F.Read(label .. " effective stats", itemAPI.GetItemStats, 1, "table", issues, link)
    if not values then return nil, true end -- an item-data load may still resolve this
    local output, recognized = {}, 0
    for key, value in pairs(values) do
        local name = FOREVER_EFFECTIVE_STATS[key]
        if name then
            if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
                and not (type(issecretvalue) == "function" and issecretvalue(value)) then
                output[#output + 1] = { name = name, value = value }
                recognized = recognized + 1
            else
                issues[#issues + 1] = label .. " effective stat " .. key .. " malformed"
            end
        else
            issues[#issues + 1] = label .. " effective stat " .. tostring(key) .. " unsupported"
        end
    end
    if recognized == 0 then issues[#issues + 1] = label .. " effective stats have no supported values" end
    table.sort(output, function(a, b) return a.name < b.name end)
    return recognized > 0 and output or nil, false
end

S.collectors.character = function()
    local issues = {}
    local data = {
        name = F.Read("Name", UnitName, 1, "string", issues, "player"),
        realm = F.Read("Realm", GetRealmName, 1, "string", issues),
        class = F.Read("Class", UnitClass, 2, "string", issues, "player"),
        level = F.Number("Level", UnitLevel, issues, "player"),
        faction = F.Read("Faction", UnitFactionGroup, 1, "string", issues, "player"),
        moneyCopper = F.Number("MoneyCopper", GetMoney, issues),
        xp = F.Number("XP", UnitXP, issues, "player"),
        xpMax = F.Number("XPMax", UnitXPMax, issues, "player"),
        clientVersion = F.Read("ClientVersion", GetBuildInfo, 1, "string", issues),
        clientBuild = F.Read("ClientBuild", GetBuildInfo, 2, "string", issues),
        interface = F.Read("Interface", GetBuildInfo, 4, "number", issues),
        clientFamily = "Forever",
    }
    local played = S.played
    if played then
        if played.guid ~= UnitGUID("player") then
            issues[#issues + 1] = "Playtime response belongs to a different character"
        else
            data.playedSeconds, data.levelPlayedSeconds = played.total, played.levelSeconds
            if data.playedSeconds == nil then issues[#issues + 1] = "Total playtime unavailable" end
            if data.levelPlayedSeconds == nil then issues[#issues + 1] = "Level playtime unavailable" end
        end
    else
        issues[#issues + 1] = "Playtime response not observed"
    end
    return data, Meta(issues)
end

S.collectors.location = function()
    local issues = {}
    local data = { zone = F.Read("Zone", GetRealZoneText, 1, "string", issues),
        subzone = F.Read("Subzone", GetSubZoneText, 1, "string", issues) }
    data.mapID = F.Number("MapID", type(C_Map) == "table" and C_Map.GetBestMapForUnit, issues, "player")
    if data.mapID then
        -- Protect the complete vector access, including field lookup and GetXY.
        local function Coordinates()
            local position = C_Map.GetPlayerMapPosition(data.mapID, "player")
            return position:GetXY()
        end
        local x = F.Read("PositionX", Coordinates, 1, "number", issues)
        local y = F.Read("PositionY", Coordinates, 2, "number", issues)
        if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            data.x, data.y = math.floor(x * 10000 + 0.5) / 100, math.floor(y * 10000 + 0.5) / 100
        else issues[#issues + 1] = "Position unknown" end
    end
    return data, Meta(issues)
end

-- Build 70009 uses ItemLocation/C_Item and C_PaperDollInfo. Do not route
-- through the Classic legacy readers merely because IsRetail() is false.
S.collectors.equipment = function()
    local data, issues, observed, pending = { slots = {} }, {}, 0, false
    local itemAPI = type(C_Item) == "table" and C_Item or {}
    local paperAPI = type(C_PaperDollInfo) == "table" and C_PaperDollInfo or {}
    local locations = type(ItemLocation) == "table" and ItemLocation or {}
    for slot = 1, 19 do
        local label = "Equipment slot " .. slot
        -- An unknown slot has an unknown row; nil is reserved for confirmed EMPTY.
        data.slots[slot] = {}
        local actual = F.Number(label, paperAPI.GetInventorySlotInfoForInvSlot, issues, slot)
        if actual == slot then
            local location = F.Read(label .. " location", locations.CreateFromEquipmentSlot,
                1, "table", issues, locations, slot)
            local exists
            if location then exists = F.Read(label .. " presence", itemAPI.DoesItemExist,
                1, "boolean", issues, location) end
            if exists == false then
                data.slots[slot], observed = nil, observed + 1
            elseif exists == true then
                observed = observed + 1
                local item = data.slots[slot]
                local before = #issues
                local id = F.Number(label .. " ID", itemAPI.GetItemID, issues, location)
                if id and id > 0 then item.itemID = id
                else issues[#issues + 1] = label .. " identity pending" end
                local link = F.Read(label .. " link", itemAPI.GetItemLink, 1, "string", issues, location)
                local reference = link and link:match("(item:[^|]+)")
                if reference and not reference:match("^item:%d+[%d:%-]*$") then reference = nil end
                local linkID = reference and tonumber(reference:match("^item:(%d+)"))
                if linkID and linkID > 0 and (not item.itemID or linkID == item.itemID) then
                    item.itemString, item.itemID = reference, linkID
                else
                    link = nil
                    issues[#issues + 1] = label .. " link identity unavailable or inconsistent"
                end
                -- Location-specific level, not the generic item's base level.
                item.itemLevel = F.Number(label .. " level", itemAPI.GetCurrentItemLevel, issues, location)
                if link then
                    item.name = F.Read(label .. " name", itemAPI.GetItemInfo, 1, "string", issues, link)
                    local required = F.Read(label .. " required level", itemAPI.GetItemInfo, 5, "number", issues, link)
                    if required and required >= 0 and required % 1 == 0 then item.requiredLevel = required
                    else issues[#issues + 1] = label .. " required level unknown" end
                end
                if #issues > before then pending = true end
                local stats, statPending = ForeverEffectiveStats(link, itemAPI, issues, label)
                item.stats = stats
                if statPending then pending = true end
            end
        else
            issues[#issues + 1] = label .. " mapping unknown"
        end
    end
    if observed == 0 then return nil, { reason = "Forever equipment APIs unavailable or no slot presence established" } end
    local meta = Meta(issues)
    meta.retry = pending
    return data, meta
end

-- Preserve canonical section order, but never read deferred subsystems.
