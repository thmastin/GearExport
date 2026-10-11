const fs = require('fs');
const assert = require('assert');
const toc = fs.readFileSync('GearExport-Forever.toc', 'utf8');
assert(/^## Interface: \d+$/m.test(toc), 'Forever TOC keeps a numeric Interface declaration for WoW load policy');
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
    && /function C\.IsForeverVersion\s*\(/.test(foreverGuard)
    && !/supportedBuilds\s*=/.test(foreverGuard)
    && !/IsSupportedForeverBuild/.test(foreverGuard),
    'Runtime isolation uses the Forever target/version contract without an exact build allowlist');
assert(/S\.structuredOnly\.forever70291Evidence\s*=\s*true/.test(fs.readFileSync('WoWSyncForever70291.lua', 'utf8')),
    'new raw evidence remains outside strict WOWSYNC v1 text');
console.log('PASS: Forever numeric TOC metadata, target/version guard without build allowlist, SavedVariables and isolated load order');
