const fs = require('fs');
const assert = require('assert');
const crypto = require('crypto');
const source = fs.readFileSync('assets/WoWSyncIcon-source.png');
assert.strictEqual(crypto.createHash('sha256').update(source).digest('hex'),
    '49c857b2a9f6d3d83ce555b6e605d9942f422fadf697b516a6411832933f3eab',
    'Supplied source artwork must remain byte-for-byte unchanged');
const icon = fs.readFileSync('WoWSyncIcon.tga');
assert.strictEqual(icon[0], 0, 'No image ID');
assert.strictEqual(icon[1], 0, 'No color map');
assert.strictEqual(icon[2], 2, 'Uncompressed true-color TGA');
assert.strictEqual(icon.readUInt16LE(12), 256);
assert.strictEqual(icon.readUInt16LE(14), 256);
assert.strictEqual(icon[16], 32, '32-bit BGRA');
assert.strictEqual(icon[17], 8, 'Eight alpha bits, bottom-left origin');
assert.strictEqual(icon.length, 18 + 256 * 256 * 4, 'Complete pixel payload');
for (const file of ['GearExport.toc', 'GearExport-ClassicEra.toc', 'GearExport-Classic.toc', 'GearExport-Retail.toc']) {
    const toc = fs.readFileSync(file, 'utf8');
    assert.strictEqual(toc.split(/\r?\n/).filter(line => line.startsWith('## IconTexture:')).join('\n'),
        '## IconTexture: Interface\\AddOns\\GearExport\\WoWSyncIcon.tga', file);
}
console.log('PASS: original artwork hash, compatible TGA payload, and all TOC icon paths');
