// Usage: node tests/check_lua.cjs PATH_TO_TEMP_NODE_MODULES
const fs = require('fs');
const path = require('path');
const parser = require(path.join(process.argv[2], 'luaparse'));
const files = fs.readdirSync('.').filter(name => name.endsWith('.lua'));
files.push(...fs.readdirSync('tests').filter(name => name.endsWith('.lua')).map(name => 'tests/' + name));
for (const file of files) {
  parser.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.1' });
  if (file.startsWith('WoWSync') || file === 'GearExport.lua') {
    const text = fs.readFileSync(file, 'utf8');
    const forbidden = /\b(?:UseContainerItem|PickupContainerItem|SplitContainerItem|BuyTrainerService|BuyMerchantItem|BuybackItem|SendMail|EquipItemByName|PickupInventoryItem|UseInventoryItem|CastSpellByName|CastSpell|CastSpellByID|CastSpellBookItem|StartAuction|PostAuction|PostItem|PostCommodity|DeleteCursorItem|ClearCursor|ReloadUI|AutoDepositItemsIntoBank|PurchaseBankTab|DepositMoney|WithdrawMoney|AcceptQuest|CompleteQuest|GetQuestReward|CraftRecipe|CraftEnchant|CraftSalvage|SetSpecialization|SetConfigID|CommitConfig|LoadConfig|LearnTalent)\s*\(/;
    if (forbidden.test(text)) throw new Error(`${file}: gameplay/reload action in observer`);
  }
}
console.log(`PASS: ${files.length} files parse as Lua 5.1; no gameplay/reload calls in WoWSync`);
