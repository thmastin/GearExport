// Run after building all three targets.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
for (const [target, version] of [['Retail', 120100], ['ClassicEra', 11509], ['TBC', 20506]]) {
    const directory = path.join('dist', target, 'GearExport');
    const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'package-manifest.json')));
    assert.strictEqual(manifest.interface, version);
    assert.strictEqual(manifest.schema, 'WOWSYNC v1');
    assert(manifest.hashes['WoWSyncIcon.tga'], 'Icon included in manifest');
    assert.deepStrictEqual(fs.readFileSync(path.join(directory, 'WoWSyncIcon.tga')),
        fs.readFileSync('WoWSyncIcon.tga'), 'Identical icon for every client');
    assert(fs.readFileSync(path.join(directory, 'GearExport.toc'), 'utf8')
        .includes('## IconTexture: Interface\\AddOns\\GearExport\\WoWSyncIcon.tga'));
    assert.deepStrictEqual(fs.readdirSync(directory).filter(file => file.endsWith('.toc')), ['GearExport.toc']);
    assert.strictEqual(fs.existsSync(path.join(directory, 'BankCleanup.lua')), target !== 'Retail');
    for (const [file, hash] of Object.entries(manifest.hashes)) {
        const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(directory, file))).digest('hex');
        assert.strictEqual(actual, hash, target + ' package hash ' + file);
        if (file.endsWith('.lua')) assert.deepStrictEqual(fs.readFileSync(path.join(directory, file)), fs.readFileSync(file), 'Shared source ' + file);
    }
}
console.log('PASS: three built packages, sole TOCs, manifest hashes, shared Lua bytes and BankCleanup inclusion/exclusion');
