return function(S, check, equal)
  local oldAPI = C_TradeSkillUI
  local oldSection = S.record.sections.professionRecipes
  local function setup(childID, baseID, childName, baseName, expansion, ids, states, associations)
    C_TradeSkillUI = {
      GetChildProfessionInfo = function()
        if not childID then return { professionID = 0, parentProfessionID = 0 } end
        return { professionID = childID, parentProfessionID = baseID, professionName = childName,
          expansionName = expansion, skillLevel = 30, maxSkillLevel = 100 }
      end,
      GetBaseProfessionInfo = function()
        if not childID then return { professionID = 0 } end
        return { professionID = baseID, professionName = baseName }
      end,
      GetAllRecipeIDs = function() return ids end,
      GetFilteredRecipeIDs = function() error("filtered recipes must not be authoritative") end,
      GetRecipeInfo = function(id)
        local state = states[id]
        if state == "ERROR" then error("recipe info failed") end
        if state == "NIL" then return nil end
        return { learned = state }
      end,
      IsRecipeInSkillLine = function(id, lineID)
        equal(lineID, childID, "association tested against identified active tier")
        return associations[id]
      end,
    }
  end

  check(S.collectors.professionRecipes ~= nil, "Retail recipe collector registered")
  setup(nil, nil, nil, nil, nil, {})
  local cold, coldMeta = S.collectors.professionRecipes()
  equal(cold, nil, "no initialized context is not a recipe observation")
  check(coldMeta.retry, "cold context follows bounded readiness retry")
  check(not S.record.sections.professionRecipes or S.record.sections.professionRecipes.data == nil,
    "cold context does not create observed zero coverage")

  local filteredCalls = 0
  setup(2910, 202, "Midnight Engineering", "Engineering", "Midnight", { 10001, 10002, 10003, 10004 },
    { [10001] = true, [10002] = false, [10003] = "NIL", [10004] = "ERROR" },
    { [10001] = true, [10002] = true, [10003] = false, [10004] = false })
  C_TradeSkillUI.GetFilteredRecipeIDs = function() filteredCalls = filteredCalls + 1; error("must not call filtered IDs") end
  local engineering, engineeringMeta = S.collectors.professionRecipes()
  equal(engineeringMeta.completeness, "partial", "enumeration never claims global completeness")
  equal(engineering.coverage.state, "PARTIAL", "successful profession scope is partial coverage")
  equal(engineering.coverage.candidateCompleteness, "UNKNOWN", "global candidate catalogue remains unknown")
  equal(engineering.coverage.learnedTrueCount, 1, "true learned count")
  equal(engineering.coverage.learnedFalseCount, 1, "false learned count")
  equal(engineering.coverage.unknownLearnedCount, 2, "unknown learned count")
  equal(engineering.professions[1].baseSkillLineID, 202, "generic profession identity")
  equal(engineering.professions[1].skillLineID, 2910, "Midnight child skill line identity")
  equal(engineering.professions[1].coverage.returnedRecipeCount, 4, "coverage is scoped to Engineering profession")
  equal(engineering.professions[1].coverage.candidateCompleteness, "UNKNOWN", "profession coverage remains partial")
  equal(engineering.professions[1].recipes[1].learned, true, "learned true remains explicit")
  equal(engineering.professions[1].recipes[1].learnedState, "OBSERVED_TRUE", "learned true evidence")
  equal(engineering.professions[1].recipes[2].learned, false, "learned false remains explicit")
  equal(engineering.professions[1].recipes[2].learnedState, "OBSERVED_FALSE", "learned false evidence")
  equal(engineering.professions[1].recipes[3].learned, nil, "nil learned remains nil")
  equal(engineering.professions[1].recipes[3].learnedState, "UNKNOWN", "nil learned is unknown")
  equal(engineering.professions[1].recipes[3].recipeInfoResult, "NIL_RESULT", "nil recipe info result remains distinct")
  equal(engineering.professions[1].recipes[4].learnedState, "UNKNOWN", "API error learned state is unknown")
  equal(engineering.professions[1].recipes[4].recipeInfoResult, "API_ERROR", "recipe API error remains distinct")
  equal(engineering.professions[1].recipes[1].skillLineIDs[1], 2910, "Midnight association explicitly captured")
  equal(#engineering.professions[1].recipes[2].skillLineIDs, 1, "same tier association for another recipe")
  equal(#engineering.professions[1].recipes[3].skillLineIDs, 0, "negative association not invented")
  equal(engineering.professions[1].recipes[3].skillLineAssociationState, "OBSERVED", "false tier association is explicitly observed")
  equal(filteredCalls, 0, "filtered enumeration is never consulted")
  equal(engineering.client.clientFamily, "Retail", "Retail client scope stored")
  equal(engineering.client.clientBuild, 69814, "Retail numeric build identity stored")
  S.CommitProfessionRecipes(engineering, engineeringMeta)

  setup(2906, 171, "Midnight Alchemy", "Alchemy", "Midnight", { 20001, 20002 },
    { [20001] = true, [20002] = false }, { [20001] = true, [20002] = true })
  local alchemy, alchemyMeta = S.collectors.professionRecipes()
  equal(alchemy.professions[1].skillLineID, 2906, "Alchemy context identity")
  equal(alchemy.professions[1].coverage.returnedRecipeCount, 2, "Alchemy coverage is independent of Engineering")
  S.CommitProfessionRecipes(alchemy, alchemyMeta)
  local stored = S.record.sections.professionRecipes.data.professions
  equal(#stored, 2, "context switch preserves both profession caches")
  local byLine = {}
  for _, profession in ipairs(stored) do byLine[profession.skillLineID] = profession end
  equal(byLine[2910].recipes[1].learned, true, "Alchemy capture does not erase Engineering")
  equal(byLine[2910].evidence, "LAST_SEEN", "inactive Engineering cache becomes LAST_SEEN")
  equal(byLine[2906].evidence, "OBSERVED", "active Alchemy cache is OBSERVED")
  equal(byLine[2906].recipes[2].learnedState, "OBSERVED_FALSE", "Alchemy explicitly unlearned recipe retained")

  setup(2910, 202, "Midnight Engineering", "Engineering", "Midnight", { 10001, 10002, 10003, 10004 },
    { [10001] = true, [10002] = "NIL", [10003] = false, [10004] = false },
    { [10001] = true, [10002] = true, [10003] = false, [10004] = false })
  local reopened, reopenedMeta = S.collectors.professionRecipes()
  S.CommitProfessionRecipes(reopened, reopenedMeta)
  stored = S.record.sections.professionRecipes.data.professions
  byLine = {}
  for _, profession in ipairs(stored) do byLine[profession.skillLineID] = profession end
  equal(byLine[2910].evidence, "OBSERVED", "reopened Engineering refreshes its own context")
  equal(byLine[2906].evidence, "LAST_SEEN", "Engineering refresh does not erase Alchemy")
  equal(byLine[2910].recipes[2].learned, false, "nil refresh preserves prior explicit state")
  equal(byLine[2910].recipes[2].evidence, "LAST_SEEN", "preserved recipe state is labeled LAST_SEEN")
  equal(byLine[2910].recipes[3].learnedState, "OBSERVED_FALSE", "new explicit unlearned state captured")

  setup(2910, 202, "Midnight Engineering", "Engineering", "Midnight", {}, {}, {})
  local empty, emptyMeta = S.collectors.professionRecipes()
  equal(empty, nil, "empty enumeration is not zero recipe coverage")
  check(emptyMeta.retry, "empty enumeration readiness is retried boundedly")
  S.Attempt("professionRecipes", emptyMeta.reason, true)
  equal(byLine[2910].recipes[1].learned, true, "empty capture retains prior explicit evidence")
  equal(byLine[2910].evidence, "OBSERVED", "failed closed-context read preserves this-session observation")
  C_TradeSkillUI.GetAllRecipeIDs = function() error("enumeration API failed") end
  local failed, failedMeta = S.collectors.professionRecipes()
  equal(failed, nil, "failed enumeration is unavailable")
  equal(failedMeta.retry, false, "API errors do not enter an unbounded retry loop")
  S.Attempt("professionRecipes", failedMeta.reason, true)
  equal(S.record.sections.professionRecipes.data.professions[1].recipes[2].learned, false,
    "failed refresh preserves prior unlearned evidence")
  local sessionStartedAt = S.sessionStartedAt
  S.sessionStartedAt = (S.sessionStartedAt or 0) + 1
  S.Attempt("professionRecipes", "cold next-session context", true)
  equal(byLine[2910].evidence, "LAST_SEEN", "cold later session marks previous observation LAST_SEEN")
  S.sessionStartedAt = sessionStartedAt

  S.dirty.professionRecipes = nil
  S.eventFrame.scripts.OnEvent(S.eventFrame, "NEW_RECIPE_LEARNED", 10003)
  check(S.dirty.professionRecipes ~= nil, "NEW_RECIPE_LEARNED dirties only the recipe collector")
  equal(S.dirty.professionRecipes.tries, 0, "recipe event uses existing bounded retry flow")
  S.dirty.professionRecipes = nil
  S.eventFrame.scripts.OnEvent(S.eventFrame, "TRADE_SKILL_SHOW")
  S.eventFrame.scripts.OnEvent(S.eventFrame, "TRADE_SKILL_CLOSE")
  equal(S.dirty.professionRecipes, nil, "bare show and close do not guess recipe context")
  S.eventFrame.scripts.OnEvent(S.eventFrame, "TRADE_SKILL_LIST_UPDATE")
  check(S.dirty.professionRecipes ~= nil, "natural list readiness event schedules capture")
  local tries = S.dirty.professionRecipes.tries
  S.eventFrame.scripts.OnEvent(S.eventFrame, "TRADE_SKILL_LIST_UPDATE")
  equal(S.dirty.professionRecipes.tries, tries, "noisy readiness events coalesce in existing dirty state")
  S.dirty.professionRecipes = nil

  C_TradeSkillUI = oldAPI
  S.record.sections.professionRecipes = oldSection
end
