// Run after building all four targets, or pass a single target to validate it.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
const targets = [['Retail', 120100], ['ClassicEra', 11509], ['TBC', 20506], ['Forever', 16001]];
const selected = process.argv[2] ? targets.filter(([target]) => target === process.argv[2]) : targets;
assert(selected.length, 'Unknown package target');
for (const [target, version] of selected) {
    const directory = path.join('dist', target, 'GearExport');
    const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'package-manifest.json')));
    assert.strictEqual(manifest.interface, version);
    assert.strictEqual(manifest.target, target);
    assert.strictEqual(manifest.schema, 'WOWSYNC v1');
    assert(manifest.hashes['WoWSyncIcon.tga'], 'Icon included in manifest');
    assert.deepStrictEqual(fs.readFileSync(path.join(directory, 'WoWSyncIcon.tga')),
        fs.readFileSync('WoWSyncIcon.tga'), 'Identical icon for every client');
    assert(fs.readFileSync(path.join(directory, 'GearExport.toc'), 'utf8')
        .includes('## IconTexture: Interface\\AddOns\\GearExport\\WoWSyncIcon.tga'));
    assert.deepStrictEqual(fs.readdirSync(directory).filter(file => file.endsWith('.toc')), ['GearExport.toc']);
    assert.strictEqual(fs.existsSync(path.join(directory, 'BankCleanup.lua')), target === 'TBC' || target === 'ClassicEra');
    const sourceToc = { Retail: 'GearExport-Retail.toc', ClassicEra: 'GearExport-ClassicEra.toc', TBC: 'GearExport.toc', Forever: 'GearExport-Forever.toc' }[target];
    assert.deepStrictEqual(fs.readFileSync(path.join(directory, 'GearExport.toc')), fs.readFileSync(sourceToc));
    assert.deepStrictEqual(fs.readdirSync(directory).sort(), [...Object.keys(manifest.hashes), 'package-manifest.json'].sort());
    if (target === 'Forever') {
        assert(manifest.hashes['FOREVER_PHASE1.md']);
        assert(manifest.hashes['FOREVER_PHASE2.md']);
        for (const file of ['GearExport.lua', 'BankCleanup.lua', 'WoWSyncCollectors.lua']) {
            assert(!fs.existsSync(path.join(directory, file)), 'Forever excludes ' + file);
        }
    }
    for (const [file, hash] of Object.entries(manifest.hashes)) {
        const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(directory, file))).digest('hex');
        assert.strictEqual(actual, hash, target + ' package hash ' + file);
        if (file.endsWith('.lua')) assert.deepStrictEqual(fs.readFileSync(path.join(directory, file)), fs.readFileSync(file), 'Shared source ' + file);
    }
}
console.log('PASS: ' + selected.length + ' built packages, sole TOCs, manifest hashes, shared Lua bytes and BankCleanup inclusion/exclusion');
