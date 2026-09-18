// node scripts/package.cjs Retail|ClassicEra|TBC|Forever
// Build a single-client folder from the shared source; no game installation writes.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..');
const target = process.argv[2];
const targets = { Retail: 'GearExport-Retail.toc', ClassicEra: 'GearExport-ClassicEra.toc', TBC: 'GearExport.toc', Forever: 'GearExport-Forever.toc' };
if (!Object.hasOwn(targets, target)) throw new Error('Choose Retail, ClassicEra, TBC, or Forever');
const toc = fs.readFileSync(path.join(root, targets[target]), 'utf8');
if (target === 'Forever' && (!/^## Interface: 16001\r?$/m.test(toc)
    || !/^## X-WoWSync-Target: Forever\r?$/m.test(toc))) {
    throw new Error('Forever requires verified interface 16001 and explicit target marker');
}
const luaFiles = toc.split(/\r?\n/).filter(line => line.endsWith('.lua'));
if (luaFiles.some(file => path.basename(file) !== file)) throw new Error('Unexpected source path in TOC');
if (target === 'Retail' && luaFiles.includes('BankCleanup.lua')) throw new Error('Retail must exclude BankCleanup');
if (target === 'Forever' && (luaFiles.includes('BankCleanup.lua') || luaFiles.includes('GearExport.lua')
    || luaFiles.includes('WoWSyncCollectors.lua'))) throw new Error('Forever Phase 1 must exclude legacy/deferred modules');
const output = path.join(root, 'dist', target, 'GearExport');
const docs = ['README.md', 'LICENSE', 'WOWSYNC_SCHEMA.md', 'WOWSYNC_ACCEPTANCE.md',
    'RETAIL_COMPATIBILITY.md', 'RETAIL_TEST_PLAN.md', 'BANK_CLEANUP_TESTS.md', 'PLAYTIME_API_AUDIT.md'];
if (target === 'Forever') docs.push('FOREVER_PHASE1.md', 'FOREVER_PHASE2.md', 'FOREVER_BAGS.md');
const assets = ['WoWSyncIcon.tga'];
const expected = [...luaFiles, ...docs, ...assets, 'GearExport.toc', 'package-manifest.json'];
// Reject stale/foreign files rather than silently shipping an obsolete flavor TOC.
if (fs.existsSync(output)) {
    const extra = fs.readdirSync(output).filter(file => !expected.includes(file));
    if (extra.length) throw new Error('Unexpected files in output: ' + extra.join(', '));
}
fs.mkdirSync(output, { recursive: true });
for (const file of [...luaFiles, ...docs, ...assets]) fs.copyFileSync(path.join(root, file), path.join(output, file));
fs.writeFileSync(path.join(output, 'GearExport.toc'), toc);
const hashes = {};
for (const file of [...luaFiles, ...docs, ...assets, 'GearExport.toc'].sort()) {
    hashes[file] = crypto.createHash('sha256').update(fs.readFileSync(path.join(output, file))).digest('hex');
}
fs.writeFileSync(path.join(output, 'package-manifest.json'), JSON.stringify({
    target, interface: Number(toc.match(/^## Interface:\s*(\d+)/m)[1]),
    schema: 'WOWSYNC v1', liveRetailValidation: 'pending', hashes,
}, null, 2) + '\n');
console.log('Built ' + target + ': ' + output);
