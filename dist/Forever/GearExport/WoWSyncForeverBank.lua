-- Forever build 70009 modern character-bank observer.  It intentionally asks
-- C_Bank for the actual tab IDs; no Classic negative container IDs are used.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key) return function() return object[key] end end
local function ItemReference(link, id)
    local ref = link and link:match("(item:[^|]+)")
    if not ref or not ref:match("^item:%d+[%d:%-]*$") then return nil end
    local linkID = tonumber(ref:match("^item:(%d+)"))
    if not linkID or linkID <= 0 or id and id ~= linkID then return nil end
    return ref, linkID
end

S.collectors.bank = function()
    if not S.bankOpen then return nil, { reason = "Forever bank is closed" } end
    local bank, container = type(C_Bank) == "table" and C_Bank or {}, type(C_Container) == "table" and C_Container or {}
    local bankType = type(Enum) == "table" and Enum.BankType and Enum.BankType.Character
    if type(bankType) ~= "number" or type(bank.CanViewBank) ~= "function" or type(bank.FetchPurchasedBankTabIDs) ~= "function"
        or type(container.GetContainerNumSlots) ~= "function" or type(container.GetContainerItemInfo) ~= "function" then
        return nil, { reason = "Forever C_Bank/C_Container character-bank APIs unavailable" }
    end
    local issues = {}
    local viewable = F.Read("Character bank viewability", bank.CanViewBank, 1, "boolean", issues, bankType)
    if viewable ~= true then return nil, { reason = "Forever character bank is not viewable", retry = true } end
    local ids = F.Read("Character bank tab IDs", bank.FetchPurchasedBankTabIDs, 1, "table", issues, bankType)
    if not ids then return nil, { reason = "Forever character bank tabs pending", retry = true } end
    local data = { containers = {}, purchasedTabs = #ids,
        coverage = "Forever C_Bank character tabs returned at this visit; account/warband bank excluded" }
    local seen = {}
    for ordinal, id in ipairs(ids) do
        if type(id) ~= "number" or id % 1 ~= 0 or id < 0 or seen[id] then
            return nil, { reason = "Forever character bank tab IDs changed or are malformed", retry = true }
        end
        seen[id] = true
        local label = "Character bank tab " .. ordinal
        local capacity = F.Number(label .. " capacity", container.GetContainerNumSlots, issues, id)
        if not capacity or capacity <= 0 then return nil, { reason = label .. " capacity unavailable", retry = true } end
        local tab, free = { id = id, capacity = capacity, slots = {}, storage = "CharacterBankTab " .. ordinal }, 0
        for slot = 1, capacity do
            local result = F.Read(label .. " slot " .. slot, function() return { container.GetContainerItemInfo(id, slot) } end, 1, "table", issues)
            if not result then return nil, { reason = label .. " contents unavailable", retry = true } end
            if result[1] == nil then
                free = free + 1
            else
                local info = F.Read(label .. " slot " .. slot .. " info", Field(result, 1), 1, "table", issues)
                local locked = info and F.Read(label .. " slot " .. slot .. " lock", Field(info, "isLocked"), 1, "boolean", issues)
                local count = info and F.Number(label .. " slot " .. slot .. " quantity", Field(info, "stackCount"), issues)
                local idValue = info and F.Number(label .. " slot " .. slot .. " ID", Field(info, "itemID"), issues)
                local link = info and F.Read(label .. " slot " .. slot .. " link", Field(info, "hyperlink"), 1, "string", issues)
                local ref, linkID = ItemReference(link, idValue)
                if locked ~= false or not count or count <= 0 or not (idValue or linkID) then
                    return nil, { reason = label .. " contents are restricted or changing", retry = true }
                end
                tab.slots[slot] = { itemID = idValue or linkID, itemString = ref, count = count,
                    name = F.Read(label .. " slot " .. slot .. " name", Field(info, "itemName"), 1, "string", issues),
                    bound = F.Read(label .. " slot " .. slot .. " binding", Field(info, "isBound"), 1, "boolean", issues) }
            end
        end
        tab.free = free
        data.containers[#data.containers + 1] = tab
    end
    table.sort(issues)
    return data, { completeness = #issues > 0 and "partial" or "complete",
        reason = #issues > 0 and table.concat(issues, "; ") or nil, retry = #issues > 0 }
end
