// Usage: node tests/check_lua.cjs PATH_TO_TEMP_NODE_MODULES
const fs = require('fs');
const path = require('path');
const parser = require(path.join(process.argv[2], 'luaparse'));
const files = fs.readdirSync('.').filter(name => name.endsWith('.lua'));
files.push('tests/wowsync_test.lua');
for (const file of files) {
  parser.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.1' });
  if (file.startsWith('WoWSync')) {
    const text = fs.readFileSync(file, 'utf8');
    const forbidden = /\b(?:UseContainerItem|PickupContainerItem|SplitContainerItem|BuyTrainerService|BuyMerchantItem|SendMail|EquipItemByName|CastSpellByName|CastSpell|StartAuction|PostAuction|DeleteCursorItem|ClearCursor|ReloadUI)\s*\(/;
    if (forbidden.test(text)) throw new Error(`${file}: gameplay/reload action in observer`);
  }
}
console.log(`PASS: ${files.length} files parse as Lua 5.1; no gameplay/reload calls in WoWSync`);
