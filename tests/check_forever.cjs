const fs = require('fs');
const assert = require('assert');
const toc = fs.readFileSync('GearExport-Forever.toc', 'utf8');
assert(/^## Interface: 16001$/m.test(toc), 'Forever interface verified on Hallo');
assert(/^## AllowLoadGameType: camelot$/m.test(toc), 'Forever package is restricted to the Camelot game type');
assert(/^## X-WoWSync-Target: Forever$/m.test(toc), 'Explicit Forever routing');
assert(/^## SavedVariables: GearExportDB, WoWSyncDB$/m.test(toc), 'Existing database names');
const files = toc.split(/\r?\n/).filter(line => line && !line.startsWith('#'));
assert.deepStrictEqual(files, ['WoWSyncCompat.lua', 'WoWSyncForever.lua', 'WoWSyncCore.lua',
    'WoWSyncForeverCollectors.lua', 'WoWSyncForever70291.lua', 'WoWSyncForeverQuests.lua', 'WoWSyncForeverBags70291.lua', 'WoWSyncForeverEvidence70291.lua',
    'WoWSyncForeverBank.lua', 'WoWSyncForeverProfessions.lua', 'WoWSyncForeverRecipes.lua', 'WoWSyncForeverSpells.lua',
    'WoWSyncRender.lua', 'WoWSyncUI.lua'], 'Forever observer load order');
assert(!files.includes('WoWSyncForeverTrainers.lua'), 'Unverified legacy trainer tuple adapter remains excluded');
for (const file of ['WoWSyncForeverBags.lua']) assert(!files.includes(file), 'Other-client collector remains excluded: ' + file);
for (const file of files) assert(fs.existsSync(file), 'Missing Forever source ' + file);
const foreverGuard = fs.readFileSync('WoWSyncForever.lua', 'utf8');
assert(/family\s*=\s*"Forever"/.test(foreverGuard)
    && /knownProfiles\s*=\s*\{\s*\["1\.60\.1:70291:16001"\]\s*=\s*true,\s*\["1\.60\.1:70338:16001"\]\s*=\s*true,?\s*\}/.test(foreverGuard),
    'Runtime identifies Forever independently and records exact profiles as verified evidence');
assert(/WOW_PROJECT_CAMELOT/.test(foreverGuard) && /projectID == 18/.test(foreverGuard),
    'Runtime prefers the client project constant and uses only the observed constrained fallback');
assert(/S\.structuredOnly\.forever70291Evidence\s*=\s*true/.test(fs.readFileSync('WoWSyncForever70291.lua', 'utf8')),
    'new raw evidence remains outside strict WOWSYNC v1 text');
console.log('PASS: Forever interface 16001, project-isolated runtime profiles, target marker, SavedVariables and load order');
