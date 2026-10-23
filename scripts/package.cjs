// node scripts/package.cjs Retail|ClassicEra|TBC|Forever
// Build a single-client folder from the shared source; no game installation writes.
const fs = require('fs');
const path = require('path');
const { hashFile, readForeverBuildGuard, verifyPackage } = require('./package-utils.cjs');
const root = path.resolve(__dirname, '..');
const target = process.argv[2];
const targets = { Retail: 'GearExport-Retail.toc', ClassicEra: 'GearExport-ClassicEra.toc', TBC: 'GearExport-BCC.toc', Forever: 'GearExport-Forever.toc' };
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
    || luaFiles.includes('WoWSyncCollectors.lua'))) throw new Error('Forever must exclude legacy/action modules');
const runtimeGuard = target === 'Forever'
    ? readForeverBuildGuard(fs.readFileSync(path.join(root, 'WoWSyncForever.lua'), 'utf8'))
    : null;
if (target === 'Forever' && (!runtimeGuard || runtimeGuard.interface !== 16001)) {
    throw new Error('Forever requires an exact, interface-matched runtime build allowlist');
}
const output = path.join(root, 'dist', target, 'GearExport');
const docs = ['README.md', 'LICENSE', 'WOWSYNC_SCHEMA.md', 'WOWSYNC_ACCEPTANCE.md',
    'RETAIL_COMPATIBILITY.md', 'RETAIL_TEST_PLAN.md', 'BANK_CLEANUP_TESTS.md', 'PLAYTIME_API_AUDIT.md'];
if (target === 'Forever') docs.push('FOREVER_PHASE1.md', 'FOREVER_PHASE2.md', 'FOREVER_PHASE3.md', 'FOREVER_BAGS.md', 'FOREVER_PROFESSIONS.md', 'FOREVER_SPELLS.md', 'FOREVER_REMAINING.md', 'FOREVER_EVIDENCE_70245.md', 'FOREVER_EVIDENCE_70291.md', 'FOREVER_CAPTURE_RELIABILITY_70338.md');
const assets = ['WoWSyncIcon.tga'];
const parent = path.dirname(output);
fs.mkdirSync(parent, { recursive: true });
const stage = fs.mkdtempSync(path.join(parent, '.GearExport-build-'));
const previous = output + '.previous-' + path.basename(stage).slice('.GearExport-build-'.length);
let previousMoved = false;
try {
    for (const file of [...luaFiles, ...docs, ...assets]) fs.copyFileSync(path.join(root, file), path.join(stage, file));
    fs.writeFileSync(path.join(stage, 'GearExport.toc'), toc);
    const hashes = {};
    for (const file of [...luaFiles, ...docs, ...assets, 'GearExport.toc'].sort()) {
        hashes[file] = hashFile(path.join(stage, file));
    }
    fs.writeFileSync(path.join(stage, 'package-manifest.json'), JSON.stringify({
        target, interface: Number(toc.match(/^## Interface:\s*(\d+)/m)[1]),
        ...(runtimeGuard && { clientVersion: runtimeGuard.version, clientBuilds: runtimeGuard.builds }),
        schema: 'WOWSYNC v1', liveRetailValidation: 'pending', hashes,
    }, null, 2) + '\n');
    verifyPackage(stage, target);
    if (fs.existsSync(output)) {
        if (fs.existsSync(previous)) fs.rmSync(previous, { recursive: true, force: true });
        fs.renameSync(output, previous);
        previousMoved = true;
    }
    fs.renameSync(stage, output);
    if (previousMoved) {
        try { fs.rmSync(previous, { recursive: true, force: true }); }
        catch (error) { console.warn('Built package is valid; previous package cleanup remains at ' + previous + ': ' + error.message); }
    }
    console.log('Built ' + target + ': ' + output);
} catch (error) {
    if (previousMoved && !fs.existsSync(output) && fs.existsSync(previous)) fs.renameSync(previous, output);
    if (fs.existsSync(stage)) fs.rmSync(stage, { recursive: true, force: true });
    throw error;
}
