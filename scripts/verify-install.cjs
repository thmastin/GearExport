// node scripts/verify-install.cjs Retail|ClassicEra|TBC PATH_TO_INSTALLED_GEAREXPORT
// Read-only: compare the installed addon with a freshly built package.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
const [target, installed] = process.argv.slice(2);
assert(['Retail', 'ClassicEra', 'TBC'].includes(target) && installed,
    'Usage: node scripts/verify-install.cjs Retail|ClassicEra|TBC PATH');
const root = path.resolve(__dirname, '..');
const packagePath = path.join(root, 'dist', target, 'GearExport');
const manifest = JSON.parse(fs.readFileSync(path.join(packagePath, 'package-manifest.json')));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const failures = [];
for (const [file, expected] of Object.entries(manifest.hashes)) {
    const source = file === 'GearExport.toc' ?
        ({ Retail: 'GearExport-Retail.toc', ClassicEra: 'GearExport-ClassicEra.toc', TBC: file })[target] : file;
    if (hash(path.join(root, source)) !== expected) failures.push('Rebuild package: ' + file);
    const destination = path.join(installed, file);
    if (!fs.existsSync(destination) || hash(destination) !== expected) failures.push('Installed file missing/stale: ' + file);
}
assert.deepStrictEqual(failures, [], 'Installation does not match current source');
assert.deepStrictEqual(fs.readdirSync(installed).filter(file => file.endsWith('.toc')), ['GearExport.toc']);
assert.strictEqual(fs.existsSync(path.join(installed, 'BankCleanup.lua')), target !== 'Retail');
console.log('PASS: ' + target + ' installed files match current source/package hashes; reload the client to load them');
