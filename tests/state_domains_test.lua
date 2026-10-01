return function(S, check, equal)
  local oldSpecialization, oldInfo, oldClass = GetSpecialization, GetSpecializationInfo, UnitClass
  local oldClassTalents, oldTraits, oldSkills, oldProfessions, oldProfessionInfo, oldProfSpecs, oldRep, oldGossip = C_ClassTalents, C_Traits, C_TradeSkillUI, GetProfessions, GetProfessionInfo, C_ProfSpecs, C_Reputation, C_GossipInfo
  GetSpecialization = function() return 2 end
  GetSpecializationInfo = function() return 263, "Enhancement", "", 1, "DAMAGER" end
  UnitClass = function() return "Shaman", "SHAMAN", 7 end
  C_ClassTalents = { GetActiveConfigID = function() return 99679859 end, GetActiveHeroTalentSpec = function() return 55 end }
  C_Traits = { GetSubTreeInfo = function(_, id) equal(id, 55, "Hero Talent subtree name lookup"); return { name = "Totemic" } end }
  local combat, meta = S.collectors.combatSpecialization()
  equal(combat.activeSpec.specID, 263, "combat specialization stable ID")
  equal(combat.activeSpec.classID, 7, "combat specialization class ID")
  equal(combat.talentConfig.configID, 99679859, "active config identity")
  equal(combat.heroTalent.subtreeID, 55, "Hero Talent subtree identity")
  equal(combat.heroTalent.name, "Totemic", "Hero Talent display name")
  S.Commit("combatSpecialization", combat, meta)
  C_ClassTalents.GetActiveConfigID = function() return nil end
  C_ClassTalents.GetActiveHeroTalentSpec = function() return nil end
  local unavailable = S.collectors.combatSpecialization()
  S.Commit("combatSpecialization", unavailable, { completeness = "partial" })
  equal(S.record.sections.combatSpecialization.data.talentConfig.configID, 99679859, "failed talent read does not erase last valid config")
  equal(S.record.sections.combatSpecialization.data.talentConfig.evidence, "LAST_SEEN", "retained talent config provenance")

  GetProfessions = function() return 1, 2, 3 end
  GetProfessionInfo = function(i)
    local name = i == 1 and "Herbalism" or i == 2 and "Mining" or "Cooking"
    local line = i == 1 and 182 or i == 2 and 186 or 185
    return name, nil, i == 1 and 45 or i == 2 and 37 or 1, 100, nil, nil, line
  end
  C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function() return { 2912, 2916, 3000 } end,
    GetProfessionInfoBySkillLineID = function(id)
      if id == 2912 then return { parentProfessionID = 182, professionID = 2912, expansionName = "Midnight" } end
      if id == 2916 then return { parentProfessionID = 186, professionID = 2916, expansionName = "Midnight" } end
      return { parentProfessionID = 999, professionID = 3000, expansionName = "Other" }
    end,
  }
  local cfg = { [2912] = 108309675, [2916] = 108309770 }
  C_ProfSpecs = {
    SkillLineHasSpecialization = function(id) return id == 182 or id == 186 end,
    GetConfigIDForSkillLine = function(id) return cfg[id] end,
    GetSpecTabIDsForSkillLine = function(id) return id == 2912 and { 1074, 1073 } or { 1107, 1105 } end,
    GetStateForTab = function(id) return id % 2 == 0 and 1 or 2 end,
  }
  C_Traits = {
    GetConfigInfo = function(id) return { configID = id, treeIDs = id == 108309675 and { 1074, 1073 } or { 1107, 1105 } } end,
    GetTreeCurrencyInfo = function() return { { traitCurrencyID = 3778, quantity = 0, spent = 22 } } end,
    GetTreeNodes = function(tree) return { tree + 1 } end,
    GetNodeInfo = function(_, id) return { ranksPurchased = id == 1075 and 19 or 12, currentRank = id == 1075 and 19 or 12, activeRank = id == 1075 and 19 or 12, maxRanks = 41, entryIDsWithCommittedRanks = { id + 10000 }, isAvailable = true, isVisible = true } end,
  }
  C_ProfSpecs.GetStateForTab = function(id) return "UNLOCKED_" .. id end
  local professions, professionMeta = S.collectors.professionSpecializations()
  equal(professionMeta.completeness, "complete", "complete profession tree scan")
  equal(#professions.professions, 3, "all observed base professions retained")
  equal(professions.professions[1].tiers[1].skillLineID, 2912, "base to Midnight tier resolution")
  equal(#professions.professions[1].tiers[1].currencies, 1, "same currency deduplicated across trees")
  equal(professions.professions[1].tiers[1].currencies[1].quantity, 0, "zero profession currency remains observed")
  equal(professions.professions[1].tiers[1].trees[1].nodes[1].ranksPurchased, 19, "node rank captured")
  equal(professions.professions[1].tiers[1].trees[1].nodes[1].maxRanks, 41, "node max rank captured")
  equal(professions.professions[1].tiers[1].trees[1].tabState, "UNLOCKED_1074", "explicit tree tab state captured")
  local cooking = professions.professions[1].baseSkillLineID == 185 and professions.professions[1] or professions.professions[2].baseSkillLineID == 185 and professions.professions[2] or professions.professions[3]
  equal(cooking.specializationState, "NOT_APPLICABLE", "explicit unsupported profession specialization state")

  C_Reputation = {
    GetFactionDataByID = function(id)
      if id == 5 then return { factionID = 5, name = "Test faction", currentStanding = 100, isChild = true, isAccountWide = true } end
      if id == 6 then return { factionID = 6, name = "Generic zero", currentStanding = 0, isChild = false } end
    end,
    IsAccountWideReputation = function(id) return id == 5 end,
    IsFactionParagon = function() return false end,
  }
  C_GossipInfo = { GetFriendshipReputation = function(id) return { friendshipFactionID = id == 5 and 5 or 0, standing = 0 } end }
  C_MajorFactions = {
    GetMajorFactionIDs = function() return { 7000 } end,
    GetMajorFactionData = function() return { factionID = 7000, expansionID = 11, name = "Test Major", isUnlocked = true } end,
    GetMajorFactionRenownInfo = function() return { renownLevel = 4, renownLevelThreshold = 2500, renownReputationEarned = 100 } end,
  }
  local reputation, repMeta = S.collectors.reputation()
  equal(repMeta.completeness, "partial", "bounded Retail reputation never claims global completeness")
  equal(reputation.coverage.candidatesQueried, 4000, "bounded candidate coverage declared")
  equal(reputation.factions[1].ownerScope, "ACCOUNT_WARBAND", "explicit account scope retained")
  equal(reputation.factions[1].friendship.evidence, "OBSERVED", "substantive Friendship captured")
  equal(#reputation.majorFactions, 1, "Major Faction enumerated independently of candidate range")
  equal(reputation.majorFactions[1].majorFactionID, 7000, "Major Faction identity kept separate")
  check(reputation.majorFactions[1].renown.level == 4, "Renown projection source captured")
  S.Commit("reputation", reputation, repMeta)
  equal(S.account.sections.reputation.data.factions[1].factionID, 5, "account-wide reputation stored at account scope")
  equal(#S.record.sections.reputation.data.factions, 1, "account-wide reputation is excluded from character-owned copy")

  GetSpecialization, GetSpecializationInfo, UnitClass = oldSpecialization, oldInfo, oldClass
  C_ClassTalents, C_Traits, C_TradeSkillUI = oldClassTalents, oldTraits, oldSkills
  GetProfessions, GetProfessionInfo, C_ProfSpecs, C_Reputation, C_GossipInfo = oldProfessions, oldProfessionInfo, oldProfSpecs, oldRep, oldGossip
end
