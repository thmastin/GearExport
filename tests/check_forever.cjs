const fs = require('fs');
const assert = require('assert');
const toc = fs.readFileSync('GearExport-Forever.toc', 'utf8');
assert(/^## Interface: 16001$/m.test(toc), 'Forever interface verified on Hallo');
assert(/^## X-WoWSync-Target: Forever$/m.test(toc), 'Explicit Forever routing');
assert(/^## SavedVariables: GearExportDB, WoWSyncDB$/m.test(toc), 'Existing database names');
const files = toc.split(/\r?\n/).filter(line => line && !line.startsWith('#'));
assert.deepStrictEqual(files, ['WoWSyncCompat.lua', 'WoWSyncForever.lua', 'WoWSyncCore.lua',
    'WoWSyncForeverCollectors.lua', 'WoWSyncForeverBags.lua', 'WoWSyncRender.lua', 'WoWSyncUI.lua'], 'Forever observer load order');
for (const file of files) assert(fs.existsSync(file), 'Missing Forever source ' + file);
console.log('PASS: Forever interface 16001, target marker, SavedVariables and limited load order');
