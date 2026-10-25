-- Classic-family progression snapshots. Read-only APIs; absent/failed reads never imply zero.
local _, addon = ...
local S, C = addon.Sync, WoWSyncCompat
if not S or C.IsRetail() then return end
local unpackValues = unpack or table.unpack
local foreverQuests, foreverRecipes = S.collectors.quests, S.collectors.professionRecipes
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return "API_MISSING" end
    local r = { pcall(fn, ...) }; if not r[1] then return "API_ERROR" end
    if r[2] == nil then return "NIL_RESULT" end
    return "OBSERVED", unpackValues(r, 2)
end
local function family()
    local ok, v = pcall(GetBuildInfo); return ok and v or "Classic"
end
local function attempt(key, api)
    local old = S.record and S.record.sections[key]
    if not old or not old.data then S.Attempt(key, api .. " unavailable"); return end
    old.lastAttemptAt, old.lastAttemptError, old.lastAttemptStale = S.Now(), api .. " unavailable", true
    -- Data remains intact; renderers/API consumers identify it as last successfully observed.
end

S.collectors.talents = function()
    local countState, tabCount = safeCall(GetNumTalentTabs)
    if countState ~= "OBSERVED" or type(tabCount) ~= "number" then return nil, { reason = "Talent tabs " .. countState, stale = true } end
    local tabs, total, partial = {}, 0, false
    local legacyTrees = C.IsClassicEra and C.IsClassicEra() and S.record and S.record.sections.character
        and S.record.sections.character.data and S.record.sections.character.data.talents
        and S.record.sections.character.data.talents.status == "OBSERVED"
        and S.record.sections.character.data.talents.trees or nil
    for tab = 1, math.min(tabCount, 10) do
        local nameState, tabID, name, points = addon.TalentTabs.Read(tab)
        if nameState ~= "OBSERVED" then partial = true end
        local row = { tabID = tabID, name = name, pointsSpent = type(points) == "number" and points or nil, talents = {} }
        -- Keep the parser-stable CHARACTER talentTree values authoritative for Era.
        -- The detailed section reuses those exact points whenever that capture succeeded.
        if legacyTrees then
            for _, legacy in ipairs(legacyTrees) do
                if legacy.name == row.name then row.pointsSpent = legacy.pointsSpent; break end
            end
        end
        if row.pointsSpent then total = total + row.pointsSpent end
        local ns, n = safeCall(GetNumTalents, tab)
        if ns ~= "OBSERVED" or type(n) ~= "number" then partial = true
        else for index = 1, math.min(n, 100) do
            local st, tn, _, tier, column, rank, maxRank = safeCall(GetTalentInfo, tab, index)
            if st == "OBSERVED" then row.talents[#row.talents + 1] = { name = tn, tier = tier, column = column, rank = rank, maxRank = maxRank }
            else partial = true end
        end end
        tabs[#tabs + 1] = row
    end
    local unspentState, unspent = safeCall(UnitCharacterPoints, "player")
    return { formatVersion = 1, evidence = "OBSERVED", observedAt = S.Now(), clientFamily = family(), tabs = tabs,
        totalSpent = total,
        unspent = type(unspent) == "number" and unspent or nil,
        totalSpentEvidence = "OBSERVED",
        unspentEvidence = unspentState == "OBSERVED" and "OBSERVED" or "UNKNOWN" },
        { completeness = partial and "partial" or "complete" }
end

S.collectors.quests = function()
    local cs, n = safeCall(GetNumQuestLogEntries)
    if cs ~= "OBSERVED" or type(n) ~= "number" then return nil, { reason = "Quest log " .. cs, stale = true } end
    local rows, partial = {}, false
    for i = 1, math.min(n, 300) do
        local state, title, level, _, _, isHeader, _, isComplete, _, questID = safeCall(GetQuestLogTitle, i)
        if state == "OBSERVED" and not isHeader then
            if type(questID) ~= "number" then local _, fallbackID = safeCall(GetQuestIDForLogIndex, i); questID = fallbackID end
            local objectives = {}; local os, on = safeCall(GetNumQuestLeaderBoards, i)
            if os == "OBSERVED" and type(on) == "number" then
                for j = 1, math.min(on, 50) do local _, text, _, done = safeCall(GetQuestLogLeaderBoard, j, i); objectives[#objectives+1] = { text = text, complete = type(done)=="boolean" and done or nil } end
            else partial = true end
            rows[#rows+1] = { title = title, questID = questID, level = level, complete = isComplete,
                failed = type(IsQuestFailed) == "function" and IsQuestFailed(i) or nil, objectives = objectives }
        elseif state ~= "OBSERVED" then partial = true end
    end
    return { formatVersion = 1, evidence = "OBSERVED", observedAt = S.Now(), clientFamily = family(), quests = rows,
        completedHistory = "SKIPPED: no bounded reliable Classic history API" }, { completeness = partial and "partial" or "complete" }
end

S.collectors.reputation = function()
    local ns, n = safeCall(GetNumFactions)
    if ns ~= "OBSERVED" or type(n) ~= "number" then return nil, { reason = "Faction list " .. ns, stale = true } end
    local collapsed = {}
    for i = 1, math.min(n, 500) do
        local state, name, _, _, _, _, _, _, _, isHeader, isCollapsed = safeCall(GetFactionInfo, i)
        if state == "OBSERVED" and isHeader and isCollapsed and type(ExpandFactionHeader) == "function" then
            collapsed[#collapsed + 1] = name
            pcall(ExpandFactionHeader, i)
        end
    end
    local function restore()
        if type(CollapseFactionHeader) ~= "function" then return end
        for j = #collapsed, 1, -1 do
            local _, currentCount = safeCall(GetNumFactions)
            if type(currentCount) == "number" then
                for i = math.min(currentCount, 500), 1, -1 do
                    local state, name, _, _, _, _, _, _, _, isHeader, isCollapsed = safeCall(GetFactionInfo, i)
                    if state == "OBSERVED" and isHeader and name == collapsed[j] and not isCollapsed then pcall(CollapseFactionHeader, i); break end
                end
            end
        end
    end
    local factions, partial = {}, false
    local _, expandedCount = safeCall(GetNumFactions)
    for i = 1, math.min(type(expandedCount) == "number" and expandedCount or n, 500) do
        local state, name, _, standing, barMin, barMax, barValue, atWar, _, isHeader, isCollapsed = safeCall(GetFactionInfo, i)
        if state ~= "OBSERVED" then partial = true
        else factions[#factions+1] = { name = name, standing = standing, barMin = barMin, barMax = barMax,
            barValue = barValue, atWar = atWar, isHeader = isHeader, isCollapsed = isCollapsed } end
    end
    restore()
    return { formatVersion=1, evidence="OBSERVED", observedAt=S.Now(), clientFamily=family(), factions=factions,
        collapsedHeadersRestored=#collapsed }, { completeness=partial and "partial" or "complete" }
end

S.collectors.professionRecipes = function()
    local open = S.professionRecipeOpen or (TradeSkillFrame and TradeSkillFrame.IsShown and TradeSkillFrame:IsShown())
        or (CraftFrame and CraftFrame.IsShown and CraftFrame:IsShown())
    if not open then return nil, { reason="Profession window closed", stale=true } end
    if S.professionRecipeMode == "CRAFT" then return nil, { reason="Craft window recipe APIs unavailable; capture is UNKNOWN", stale=true } end
    local lineState, professionName = safeCall(GetTradeSkillLine)
    if lineState ~= "OBSERVED" or type(professionName) ~= "string" or professionName == "" then
        return nil, { reason="Profession identity " .. lineState, stale=true }
    end
    local ns, n = safeCall(GetNumTradeSkills)
    if ns ~= "OBSERVED" or type(n) ~= "number" or n <= 0 then return nil, { reason="Recipe list "..ns..(n == 0 and " (empty)" or ""), stale=true } end
    local recipes, partial = {}, false
    for i=1,math.min(n,1000) do
        local state,name,kind,_,_,_,_,_,_,_,link = safeCall(GetTradeSkillInfo,i)
        if state=="OBSERVED" and kind~="header" then
            local rs, rc = safeCall(GetTradeSkillNumReagents,i); local reagents={}
            if rs=="OBSERVED" and type(rc)=="number" then for j=1,math.min(rc,30) do
                local _,rn,_,required,_,rLink=safeCall(GetTradeSkillReagentInfo,i,j)
                reagents[#reagents+1]={name=rn,itemLink=rLink,count=required}
            end else partial=true end
            local itemID=type(link)=="string" and tonumber(link:match("item:(%d+)"))
            recipes[#recipes+1]={name=name,itemID=itemID,itemLink=link,difficulty=kind,reagents=reagents}
        else partial=true end
    end
    return {formatVersion=1,evidence="OBSERVED",observedAt=S.Now(),clientFamily=family(),
        professions={{ name=professionName, professionName=professionName, observedAt=S.Now(), recipes=recipes }}},
        {completeness=partial and "partial" or "complete"}
end
if addon.Forever then
    if foreverQuests then S.collectors.quests = foreverQuests end
    if foreverRecipes then S.collectors.professionRecipes = foreverRecipes end
end

for _, event in ipairs({ "CHARACTER_POINTS_CHANGED", "UPDATE_FACTION", "QUEST_LOG_UPDATE", "QUEST_LOG_CRITERIA_UPDATE" }) do
    pcall(S.eventFrame.RegisterEvent, S.eventFrame, event)
end
