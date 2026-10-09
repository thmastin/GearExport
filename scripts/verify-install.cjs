// node scripts/verify-install.cjs Retail|ClassicEra|TBC|Forever PATH_TO_INSTALLED_GEAREXPORT
// Read-only: compare the complete installed directory with its exact package and current source.
const path = require('path');
const assert = require('assert');
const { verifyDirectoryAgainstPackage, assertPackageMatchesSource } = require('./package-utils.cjs');
const [target, installed] = process.argv.slice(2);
assert(['Retail', 'ClassicEra', 'TBC', 'Forever'].includes(target) && installed,
    'Usage: node scripts/verify-install.cjs Retail|ClassicEra|TBC|Forever PATH');
const root = path.resolve(__dirname, '..');
const packagePath = path.join(root, 'dist', target, 'GearExport');
const packageInfo = verifyDirectoryAgainstPackage(packagePath, installed, target);
assertPackageMatchesSource(root, packagePath, packageInfo, target);
console.log('PASS: ' + target + ' exact file set and SHA256 hashes match current source/package');
