local _, addon = ...
local S, readers = addon.Sync, addon.Readers
local Compat = WoWSyncCompat or {}

local function Optional(fn, ...)
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

function S.Item(link, itemID)
    itemID = itemID or (link and tonumber(link:match("item:(%d+)")))
    local item = { itemID = itemID, itemString = link and link:match("(item:[^|]+)") }
    local name, _, quality, level, requiredLevel, _, _, _, _, _, vendor = Compat.GetItemInfo(link or itemID)
    if Compat.GetItemLevel and link then level = Compat.GetItemLevel(link, level) end
    if not name then Compat.RequestItemData(itemID) end
    item.name, item.quality, item.itemLevel, item.requiredLevel = name, quality, level, requiredLevel
    item.vendorCopper = vendor
    return item
end

S.collectors.character = function()
    local _, class = UnitClass("player")
    local version, build, _, interface = GetBuildInfo()
    local data = { name = UnitName("player"), realm = GetRealmName(), class = class,
        level = UnitLevel("player"), faction = Optional(UnitFactionGroup, "player"),
        moneyCopper = GetMoney(), xp = Optional(UnitXP, "player"), xpMax = Optional(UnitXPMax, "player"),
        clientVersion = version, clientBuild = build, interface = interface,
        clientFamily = Compat.IsRetail() and "Retail" or nil }
    if not data.name or not class or data.level < 1 then return nil, { reason = "Character not ready", retry = true } end
    local played = S.played
    if played and played.guid == UnitGUID("player") then
        data.playedSeconds = played.total
        if played.level == data.level then data.levelPlayedSeconds = played.levelSeconds end
    end
    return data
end

S.collectors.location = function()
    if Compat.GetLocation then return Compat.GetLocation() end
    return { zone = Optional(GetRealZoneText), subzone = Optional(GetSubZoneText) }
end

local function Containers(bank, scope)
    if bank and not S.bankOpen then return nil, { reason = "Bank closed" } end
    local slots = Compat.GetContainerSlotCount
    local freeSlots = Compat.GetContainerFreeSlots
    local getInfo = Compat.GetContainerInfo
    if not slots or not getInfo then
        return nil, { reason = "Container APIs unavailable" }
    end
    local bagRanges, bankRanges = Compat.GetBankRanges(scope)
    local bags = bagRanges
    if bank then bags = bankRanges end
    if not bags then return nil, { reason = "Container view unavailable", retry = true } end
    local data = { containers = {}, coverage = bank and Compat.GetBankCoverage(scope) or nil }
    if bank then data.ownerScope = scope == "ACCOUNT" and "ACCOUNT_WARBAND" or "CHARACTER" end
    local incomplete, locked, seenContainers = false, false, {}
    for _, bag in ipairs(bags) do
        if seenContainers[bag] then return nil, { reason = "Duplicate bank tab ID", retry = true } end
        seenContainers[bag] = true
        local count = slots(bag)
        if count == nil or (Compat.ContainerRequiresCapacity(bag, bank) and count == 0) then
            return nil, { reason = "Container capacity not ready", retry = true }
        end
        local free, family
        if freeSlots then free, family = freeSlots(bag) end
        local container = { id = bag, capacity = count, free = free, family = family, slots = {} }
        container.storage = Compat.GetContainerCategory(bag, bank, scope)
        local link, equippedID, equippedTexture
        if Compat.GetContainerBagIdentity then
            link, equippedID, equippedTexture = Compat.GetContainerBagIdentity(bag)
        end
        if bag > 0 and (link or equippedID or equippedTexture) then
            local equipped = link or equippedID or equippedTexture
            if equipped and count == 0 then
                return nil, { reason = "Equipped bag capacity pending", retry = true }
            end
            if link then container.bag = S.Item(link); if not container.bag.name then incomplete = true end end
            if not link and count > 0 then incomplete = true end
        end
        local occupied = 0
        for slot = 1, count do
            local info
            info = getInfo(bag, slot)
            if info then
                occupied = occupied + 1
                local link = info.hyperlink or (Compat.GetContainerLink and Compat.GetContainerLink(bag, slot))
                local id = info.itemID or link and tonumber(link:match("item:(%d+)"))
                if not id or not info.stackCount then return nil, { reason = "Item identity/quantity pending", retry = true } end
                local item = S.Item(link, id)
                item.count, item.bound = info.stackCount, info.isBound
                container.slots[slot] = item
                if not item.name or not item.itemString then incomplete = true end
                if info.isLocked then locked = true end
            end
        end
        if free ~= nil and occupied ~= count - free then
            return nil, { reason = "Container contents still settling", retry = true }
        end
        data.containers[#data.containers + 1] = container
    end
    if locked or GetCursorInfo() then return nil, { reason = "Inventory movement in progress", retry = true } end
    if bank then
        data.visit = S.Copy((scope == "ACCOUNT" and S.account and S.account.visits or S.record.visits).bank)
        local count, kind = Compat.GetPurchasedBankSlots(scope)
        if kind == "tabs" then
            data.purchasedTabs = count
            if count == nil or count ~= #bags then return nil, { reason = "Purchased bank tabs pending", retry = true } end
        else data.purchasedBagSlots = count end
    end
    return data, { completeness = incomplete and "partial" or "complete",
        reason = incomplete and "Item metadata pending" or nil, retry = incomplete }
end
S.collectors.bags = function() return Containers(false) end
S.collectors.bank = function() return Containers(true) end
if Compat.IsRetail and Compat.IsRetail() then
    S.collectors.accountBank = function() return Containers(true, "ACCOUNT") end

    local function GuildTrace(text)
        local trace = S.guildTrace or {}
        trace[#trace + 1] = text
        while #trace > 16 do table.remove(trace, 1) end
        S.guildTrace = trace
    end

    local function GuildIdentity()
        local identity, reason = Compat.GetGuildBankIdentity()
        if not identity then return nil, reason end
        local record = S.guilds[identity.key]
        if type(record) ~= "table" then record = {}; S.guilds[identity.key] = record end
        record.identity = identity
        record.sections = type(record.sections) == "table" and record.sections or {}
        record.visits = type(record.visits) == "table" and record.visits or {}
        S.guild, S.guildError = record, nil
        return record
    end

    local function GuildItem(slot)
        local item = S.Item(slot.link)
        item.count = slot.count
        return item
    end

    local function GuildData(capture)
        local data = { ownerScope = "GUILD", guild = S.Copy(capture.identity), tabs = {}, containers = {},
            coverage = "All tabs currently reported viewable were serialized through QueryGuildBankTab; inaccessible tabs were not scanned.",
            visit = S.Copy(S.guild.visits.bank) }
        local allObserved, viewable = true, 0
        for _, tab in ipairs(capture.tabs or {}) do
            local result = capture.results[tab.id]
            local entry = { id = tab.id, name = tab.name, icon = tab.icon, canView = tab.canView,
                canDeposit = tab.canDeposit, withdrawals = tab.withdrawals, remainingWithdrawals = tab.remainingWithdrawals }
            if not tab.canView then entry.state = "INACCESSIBLE"
            elseif result and result.container and not result.incomplete then
                viewable = viewable + 1
                entry.state = "OBSERVED"
                local container = result.container
                for slot, raw in pairs(container.slots) do container.slots[slot] = GuildItem(raw) end
                data.containers[#data.containers + 1] = container
            else
                if tab.canView then viewable = viewable + 1 end
                entry.state = "UNKNOWN"; entry.reason = result and result.reason or "Not queried"
                allObserved = false
            end
            data.tabs[#data.tabs + 1] = entry
        end
        -- No viewable tabs means no item contents were observed; do not let the
        -- generic inventory renderer call that an empty Guild Bank.
        data.emptyKnown = allObserved and viewable > 0
        return data, allObserved
    end

    local function FinalizeGuildCapture(reason)
        local capture = S.guildCapture
        if not capture or capture.finalized then return end
        capture.finalized = true
        if not S.guild then
            S.guildError = reason or capture.lastReason or "Guild Bank identity was not ready"
            GuildTrace("init-failed=" .. S.guildError)
            S.guildCapture = nil
            return
        end
        local data, complete = GuildData(capture)
        if complete then
            S.Commit("guildBank", data, { completeness = "complete" })
            GuildTrace("complete")
        else
            if not reason then
                for _, tab in ipairs(capture.tabs or {}) do
                    local result = capture.results[tab.id]
                    if tab.canView and result and result.reason then reason = result.reason; break end
                end
            end
            reason = reason or "One or more viewable Guild Bank tabs were not confirmed"
            local old = S.guild.sections.bank
            if not old or old.completeness ~= "complete" then
                S.Commit("guildBank", data, { completeness = "partial", reason = reason })
                GuildTrace("partial=" .. tostring(reason))
            else
                S.Attempt("guildBank", reason)
                GuildTrace("retained=" .. tostring(reason))
            end
        end
        S.guildCapture = nil
    end

    local function RequestNextGuildTab()
        local capture = S.guildCapture
        if not capture or capture.pending then return end
        local tab = capture.queue[capture.next]
        if not tab then FinalizeGuildCapture(); return end
        capture.next = capture.next + 1
        capture.pending = tab
        GuildTrace("query=" .. tab)
        local ok, reason = Compat.QueryGuildBankTab(tab)
        if not ok then
            GuildTrace("query-failed=" .. tab)
            capture.results[tab] = { reason = "Query failed: " .. tostring(reason) }
            capture.pending = nil
            capture.nextQueryAt = GetTime() + 0.15
            return
        end
        capture.deadline = GetTime() + 2.5
    end

    -- Both the documented events and Blizzard_GuildBankUI's actual frame lifecycle
    -- can signal one interaction.  Starting twice would create competing tab
    -- queries, so the lifecycle entry point deliberately coalesces duplicates.
    function S.GuildBankOpened(source)
        S.guildLifecycle = S.guildLifecycle or { starts = 0, closes = 0, shows = 0, hides = 0 }
        S.guildLifecycle.starts = S.guildLifecycle.starts + 1
        if S.guildBankOpen then
            GuildTrace("start-ignored=" .. tostring(source or "event"))
            return
        end
        S.guildBankOpen = true
        S.guildError = nil
        S.guildLastValidation = {}
        S.guildTrace = { "opened=" .. tostring(source or "event") }
        local now = GetTime()
        -- A Guild Bank lifecycle signal can precede Club initialization or complete
        -- tab permissions. Keep the bank open and retry setup briefly; no tab query
        -- is issued until identity and every tab's canView metadata are present.
        S.guildCapture = { startAt = now + 0.25, initDeadline = now + 3, queue = {}, next = 1, results = {} }
        S.Wake()
    end

    -- Blizzard_GuildBankUI is LoadOnDemand.  The frame may be absent when this
    -- addon loads, or already visible by the time it becomes discoverable from a
    -- bank update event.  HookScript preserves Blizzard's handlers and the shown
    -- check covers that latter case without requiring the player to reopen it.
    function S.InstallGuildBankHooks()
        if S.guildHooksInstalled then return true end
        local bankFrame = GuildBankFrame
        if not bankFrame or type(bankFrame.HookScript) ~= "function" then return false end
        local ok = pcall(function()
            bankFrame:HookScript("OnShow", function()
                S.guildLifecycle = S.guildLifecycle or { starts = 0, closes = 0, shows = 0, hides = 0 }
                S.guildLifecycle.shows = S.guildLifecycle.shows + 1
                S.GuildBankOpened("frame-show")
            end)
            bankFrame:HookScript("OnHide", function()
                S.guildLifecycle = S.guildLifecycle or { starts = 0, closes = 0, shows = 0, hides = 0 }
                S.guildLifecycle.hides = S.guildLifecycle.hides + 1
                S.GuildBankClosed("frame-hide")
            end)
        end)
        if not ok then return false end
        S.guildHooksInstalled, S.guildHooksFrame = true, bankFrame
        if type(bankFrame.IsShown) == "function" and bankFrame:IsShown() then S.GuildBankOpened("frame-already-shown") end
        return true
    end

    function S.ResolveGuildBankOwner()
        if S.guild then return S.guild end
        return GuildIdentity()
    end

    function S.GuildBankEvent(event)
        -- A Guild Bank UI update is a safe discovery opportunity only.  It never
        -- acts as a query response unless a serialized explicit request exists.
        if not S.guildHooksInstalled then S.InstallGuildBankHooks() end
        local capture = S.guildCapture
        if not capture then return end
        if event == "GUILDBANKBAGSLOTS_CHANGED" and capture.pending then
            local tab = capture.pending
            GuildTrace("response=" .. tab)
            local container, incomplete, validation = Compat.ReadGuildBankTab(tab)
            S.guildLastValidation = S.guildLastValidation or {}
            S.guildLastValidation[tab] = { state = incomplete and "partial" or "observed", detail = validation }
            local detailReason = validation and ("Guild Bank " .. validation.reason .. " at slot " .. validation.slot) or nil
            capture.results[tab] = container and { container = container, incomplete = incomplete,
                reason = incomplete and (detailReason or "Guild Bank slot identity/quantity pending") or nil }
                or { reason = tostring(incomplete) }
            capture.pending, capture.deadline = nil, nil
            GuildTrace("read=" .. tab .. (incomplete and ":partial:" .. tostring(validation and validation.reason or "unknown") or ":observed"))
            capture.nextQueryAt = GetTime() + 0.15
        elseif event == "GUILDBANK_UPDATE_TABS" and not capture.started then
            capture.startAt = GetTime()
        end
    end

    function S.GuildBankTick(now)
        local capture = S.guildCapture
        if not capture then return end
        if not capture.started and now >= capture.startAt then
            local record, identityReason = GuildIdentity()
            if not record then
                capture.lastReason = identityReason or "Guild identity unavailable"
                GuildTrace("identity-wait")
                if now >= capture.initDeadline then FinalizeGuildCapture(capture.lastReason)
                else capture.startAt = now + 0.25 end
                return
            end
            if not capture.visitStarted then S.BeginVisit("guildBank"); capture.visitStarted = true end
            local tabs, reason = Compat.GetGuildBankTabs()
            if not tabs then
                capture.lastReason = reason or "Guild Bank tab metadata unavailable"
                GuildTrace("tabs-wait")
                if now >= capture.initDeadline then FinalizeGuildCapture(capture.lastReason)
                else capture.startAt = now + 0.25 end
                return
            end
            capture.identity = S.Copy(record.identity)
            capture.tabs, capture.started = tabs, true
            for _, tab in ipairs(tabs) do if tab.canView then capture.queue[#capture.queue + 1] = tab.id end end
            GuildTrace("queue=" .. table.concat(capture.queue, ","))
            capture.nextQueryAt = now
        elseif capture.started and not capture.pending and capture.nextQueryAt and now >= capture.nextQueryAt then
            capture.nextQueryAt = nil
            RequestNextGuildTab()
        elseif capture.pending and now >= capture.deadline then
            GuildTrace("timeout=" .. capture.pending)
            capture.results[capture.pending] = { reason = "Guild Bank query response timed out" }
            capture.pending, capture.deadline = nil, nil
            capture.nextQueryAt = now + 0.15
        end
    end

    function S.GuildBankClosed(source)
        S.guildLifecycle = S.guildLifecycle or { starts = 0, closes = 0, shows = 0, hides = 0 }
        S.guildLifecycle.closes = S.guildLifecycle.closes + 1
        if not S.guildBankOpen then return end
        local capture = S.guildCapture
        if capture then
            if capture.pending then capture.results[capture.pending] = { reason = "Guild Bank closed before query response" }; capture.pending = nil end
            FinalizeGuildCapture("Guild Bank closed before every viewable tab was confirmed")
        end
        S.guildBankOpen = false
        if S.guild then S.EndVisit("guildBank") end
    end

    function S.GuildBankActive() return S.guildCapture ~= nil end
end

S.collectors.equipment = function()
    local data, incomplete = { slots = {} }, false
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        local id = Optional(GetInventoryItemID, "player", slot)
        if link or id then
            local item = S.Item(link, id)
            if link then
                local ready
                item.stats, ready = Compat.GetEquipmentStats(link, slot, readers.EquipmentStats)
                if not ready then incomplete = true end
            end
            data.slots[slot] = item
            if not link or not item.name or not item.itemLevel then incomplete = true end
        elseif (Optional(GetInventoryItemTexture, "player", slot)) then
            return nil, { reason = "Equipment identity pending", retry = true }
        end
    end
    return data, { completeness = incomplete and "partial" or "complete",
        reason = incomplete and "Item metadata or equipped tooltip pending" or nil, retry = incomplete }
end

S.collectors.professions = function()
    return Compat.GetProfessionState(readers.Professions)
end

S.collectors.spells = function()
    local entries, seen, incomplete = {}, {}, false
    local tabs, spellError = Compat.EnumerateSpellbook and Compat.EnumerateSpellbook()
    if not tabs then return nil, { reason = spellError or "Spellbook not ready", retry = true } end
    for _, tab in ipairs(tabs) do
        for _, entry in ipairs(tab.entries) do
            if entry.name then
                local key = entry.spellID and tostring(entry.spellID) or entry.name .. "\031" .. (entry.rank or "")
                if not seen[key] then
                    entries[#entries + 1] = { spellID = entry.spellID, name = entry.name,
                        rank = entry.rank, kind = entry.kind }
                    seen[key] = true
                end
                if not entry.spellID then incomplete = true end
            else incomplete = true end
        end
    end
    table.sort(entries, function(a, b)
        if a.spellID ~= b.spellID then return (a.spellID or math.huge) < (b.spellID or math.huge) end
        if a.name ~= b.name then return a.name < b.name end
        return (a.rank or "") < (b.rank or "")
    end)
    return { entries = entries, coverage = Compat.IsRetail()
        and "Retail player/profession spellbook and known flyouts; active spec, passives and racials; no ranks; excludes future/off-spec spells, recipe catalogues and pet spellbook"
        or "player spellbook; exposed ranks; excludes recipe catalogues and pet spellbook" },
        { completeness = incomplete and "partial" or "complete", reason = incomplete and "Some spell identities pending" or nil, retry = incomplete }
end

S.collectors.trainer = function()
    if not S.trainerOpen then return nil, { reason = "Trainer closed" } end
    local report = readers.Trainer(function(service, index)
        local skill, rank, met = Optional(GetTrainerServiceSkillReq, index)
        if skill then service.skillRequirement = { name = skill, rank = rank, met = met } end
        local requirements = Optional(GetTrainerServiceNumAbilityReq, index)
        if requirements and requirements > 0 then
            service.abilityRequirements = {}
            for req = 1, requirements do
                local name, has = Optional(GetTrainerServiceAbilityReq, index, req)
                service.abilityRequirements[#service.abilityRequirements + 1] = { name = name, met = has }
            end
        end
        -- Service indices are UI positions, never stable spell IDs. No name guessing.
    end)
    if not report then return nil, { reason = "Trainer UI/data not ready", retry = true } end
    local filters, collapsed, missing = {}, false, false
    for _, status in ipairs({ "available", "unavailable", "used" }) do
        filters[status] = Optional(GetTrainerServiceTypeFilter, status)
    end
    for index = 1, GetNumTrainerServices() do
        local service = Compat.GetTrainerService and Compat.GetTrainerService(index)
        local name, kind, expanded = service and service.name, service and service.status, service and service.expanded
        if not name then missing = true end
        if kind == "header" and not expanded then collapsed = true end
    end
    for _, service in ipairs(report.services) do
        if service.cost == nil or service.requiredLevel == nil then missing = true end
    end
    table.sort(report.services, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if (a.rank or "") ~= (b.rank or "") then return (a.rank or "") < (b.rank or "") end
        if (a.status or "") ~= (b.status or "") then return (a.status or "") < (b.status or "") end
        return (a.cost or -1) < (b.cost or -1)
    end)
    local category = Compat.TrainerCategory and Compat.TrainerCategory(report) or "UNKNOWN"
    S.trainerCategory = category
    local visit = S.currentTrainerVisit or S.record.visits.trainers[category]
    if visit then S.record.visits.trainers[category] = visit end
    local data = { visit = S.Copy(visit), name = report.trainer.name,
        trainerType = report.trainer.type, services = report.services, filters = filters,
        collapsed = collapsed, moneyAtVisit = report.character.money,
        coverage = "visible filtered services; spell IDs unavailable" }
    -- A zero-row response can mean filtered-out entries OR data still arriving.
    local empty = #report.services == 0
    local complete = not missing and not empty and not collapsed and filters.available and filters.unavailable and filters.used
    return { category = category, snapshot = data }, { completeness = complete and "complete" or "partial",
        reason = missing and "Trainer fields pending" or empty and "No visible services; completeness unknown"
            or not complete and "Filtered/collapsed trainer list" or nil,
        retry = missing or empty }
end
