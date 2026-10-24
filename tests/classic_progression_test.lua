local sectionStore = {}
local S = { collectors = {}, record = { sections = {} }, Now = function() return 123 end, eventFrame = { RegisterEvent=function() end } }
S.Attempt = function(key, reason, stale) local old=S.record.sections[key]; if not old then old={}; S.record.sections[key]=old end; old.lastAttemptError=reason; old.lastAttemptStale=stale end
local addon = { Sync=S }
WoWSyncCompat={IsRetail=function() return false end}
function GetBuildInfo() return "Classic" end
function GetNumTalentTabs() return 1 end
function GetTalentTabInfo() return "Affliction",nil,3 end
function GetNumTalents() return 1 end
function GetTalentInfo() return "Improved Corruption",nil,1,1,2,5 end
function UnitCharacterPoints() return 2 end
function GetNumQuestLogEntries() return 1 end
function GetQuestLogTitle() return "Test Quest",10,nil,nil,false,nil,false,nil,77 end
function GetQuestIDForLogIndex() return 77 end
function GetNumQuestLeaderBoards() return 1 end
function GetQuestLogLeaderBoard() return "Collect 3",nil,nil,false end
function GetNumFactions() return 1 end
function GetFactionInfo() return "Test Faction",nil,4,0,3000,1000,2000,false,nil,nil,nil,false,false end
TradeSkillFrame={IsShown=function() return true end}
function GetNumTradeSkills() return 1 end
function GetTradeSkillInfo() return "Linen Belt","optimal",1,false,0,1,1,1,0,"item:2589" end
function GetTradeSkillNumReagents() return 1 end
function GetTradeSkillReagentInfo() return "Linen Cloth",nil,2,true,"item:2589" end
assert(loadfile("WoWSyncClassicProgression.lua"))("GearExport",addon)
local d=S.collectors.talents(); assert(d.totalSpent==3 and d.unspent==2 and d.tabs[1].talents[1].rank==2)
assert(loadfile("WoWSyncRender.lua"))("GearExport",addon)
local talentText=S.RenderSection("talents",{schemaVersion=1,sections={talents={data=d,observedAt=123,completeness="complete"}}})
assert(talentText:find("talent\t1\tImproved Corruption\t1\t1\t2\t5",1,true),"exported M5 talent section includes rank-level detail")
S.record.sections.character={data={talents={status="OBSERVED",trees={{name="Affliction",pointsSpent=3}}}}}
d=S.collectors.talents(); assert(d.tabs[1].pointsSpent==3,"rank detail matches the parser-stable Era tree points")
S.record.sections.character=nil
d=S.collectors.quests(); assert(d.quests[1].questID==77 and d.quests[1].objectives[1].text=="Collect 3" and d.completedHistory:find("SKIPPED"))
d=S.collectors.reputation(); assert(d.factions[1].barValue==1000)
d=S.collectors.professionRecipes(); assert(d.recipes[1].itemID==2589 and d.recipes[1].reagents[1].count==2)
for _, key in ipairs({"talents","quests","reputation","professionRecipes"}) do
    S.record.sections[key]={data={sentinel=true},observedAt=99}
end
local funcs={GetNumTalentTabs,GetNumQuestLogEntries,GetNumFactions,GetNumTradeSkills}
GetNumTalentTabs=nil; GetNumQuestLogEntries=nil; GetNumFactions=nil; GetNumTradeSkills=nil
assert(S.collectors.talents()==nil); assert(S.collectors.quests()==nil); assert(S.collectors.reputation()==nil); assert(S.collectors.professionRecipes()==nil)
for _, key in ipairs({"talents","quests","reputation","professionRecipes"}) do
    S.Attempt(key,"failed API",true)
    assert(S.record.sections[key].data.sentinel and S.record.sections[key].lastAttemptStale==true)
end
print("PASS: Classic progression collectors; API missing and failed-read retention")


