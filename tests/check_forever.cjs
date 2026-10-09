const fs = require('fs');
const assert = require('assert');
const toc = fs.readFileSync('GearExport-Forever.toc', 'utf8');
assert(/^## Interface: 16001$/m.test(toc), 'Forever interface verified on Hallo');
assert(/^## X-WoWSync-Target: Forever$/m.test(toc), 'Explicit Forever routing');
assert(/^## SavedVariables: GearExportDB, WoWSyncDB$/m.test(toc), 'Existing database names');
const files = toc.split(/\r?\n/).filter(line => line && !line.startsWith('#'));
assert.deepStrictEqual(files, ['WoWSyncCompat.lua', 'WoWSyncForever.lua', 'WoWSyncCore.lua',
    'WoWSyncForeverCollectors.lua', 'WoWSyncForever70291.lua', 'WoWSyncForeverBags70291.lua', 'WoWSyncForeverEvidence70291.lua',
    'WoWSyncRender.lua', 'WoWSyncUI.lua'], 'Forever observer load order');
for (const file of ['WoWSyncForeverBags.lua', 'WoWSyncForeverProfessions.lua', 'WoWSyncForeverSpells.lua',
    'WoWSyncForeverBank.lua', 'WoWSyncForeverTrainers.lua']) {
    assert(!files.includes(file), 'Unvalidated 70009 collector is excluded: ' + file);
}
for (const file of files) assert(fs.existsSync(file), 'Missing Forever source ' + file);
assert(/version\s*=\s*"1\.60\.1"/.test(fs.readFileSync('WoWSyncForever.lua', 'utf8'))
    && /build\s*=\s*"70291"/.test(fs.readFileSync('WoWSyncForever.lua', 'utf8'))
    && /interface\s*=\s*16001/.test(fs.readFileSync('WoWSyncForever.lua', 'utf8')),
    'Runtime guard pinned to live version, build, and interface');
assert(/S\.structuredOnly\.forever70291Evidence\s*=\s*true/.test(fs.readFileSync('WoWSyncForever70291.lua', 'utf8')),
    'new raw evidence remains outside strict WOWSYNC v1 text');
console.log('PASS: Forever interface 16001, build-matched guard, target marker, SavedVariables and isolated load order');
