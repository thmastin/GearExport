const fs = require('fs');
const assert = require('assert');
const toc = fs.readFileSync('GearExport-Forever.toc', 'utf8');
assert(/^## Interface: 16001$/m.test(toc), 'Forever interface verified on Hallo');
assert(/^## X-WoWSync-Target: Forever$/m.test(toc), 'Explicit Forever routing');
assert(/^## SavedVariables: GearExportDB, WoWSyncDB$/m.test(toc), 'Existing database names');
const files = toc.split(/\r?\n/).filter(line => line && !line.startsWith('#'));
assert.deepStrictEqual(files, ['WoWSyncCompat.lua', 'WoWSyncForever.lua', 'WoWSyncCore.lua',
    'WoWSyncForeverCollectors.lua', 'WoWSyncForever70291.lua', 'WoWSyncForeverBags70291.lua', 'WoWSyncForeverEvidence70291.lua',
    'WoWSyncForeverBank.lua', 'WoWSyncForeverProfessions.lua', 'WoWSyncForeverSpells.lua',
    'WoWSyncRender.lua', 'WoWSyncUI.lua'], 'Forever observer load order');
assert(!files.includes('WoWSyncForeverTrainers.lua'), 'Unverified legacy trainer tuple adapter remains excluded');
for (const file of ['WoWSyncForeverBags.lua']) assert(!files.includes(file), 'Other-client collector remains excluded: ' + file);
for (const file of files) assert(fs.existsSync(file), 'Missing Forever source ' + file);
const foreverGuard = fs.readFileSync('WoWSyncForever.lua', 'utf8');
assert(/version\s*=\s*"1\.60\.1"/.test(foreverGuard)
    && /interface\s*=\s*16001/.test(foreverGuard)
    && /supportedBuilds\s*=\s*\{\s*\["70291"\]\s*=\s*true,\s*\["70338"\]\s*=\s*true\s*\}/.test(foreverGuard),
    'Runtime guard accepts only the two verified exact Forever builds and interface');
assert(/S\.structuredOnly\.forever70291Evidence\s*=\s*true/.test(fs.readFileSync('WoWSyncForever70291.lua', 'utf8')),
    'new raw evidence remains outside strict WOWSYNC v1 text');
console.log('PASS: Forever interface 16001, build-matched guard, target marker, SavedVariables and isolated load order');
