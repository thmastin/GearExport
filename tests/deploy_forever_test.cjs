// Temporary-fixture integration coverage for the single-command Forever deploy workflow.
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
const { deployForever } = require('../scripts/deploy-forever.cjs');
const { verifyPackage, verifyDirectoryAgainstPackage, validateForeverDestination } = require('../scripts/package-utils.cjs');

const obsolete = [
    'WoWSyncForeverBags.lua', 'WoWSyncForeverBank.lua', 'WoWSyncForeverProfessions.lua',
    'WoWSyncForeverSpells.lua', 'WoWSyncForeverTrainers.lua',
    'WoWSyncForever70245.lua', 'WoWSyncForeverBags70245.lua', 'WoWSyncForeverEvidence70245.lua',
];
let assertions = 0;
function check(value, message) { assertions++; assert(value, message); }
function equal(actual, expected, message) { assertions++; assert.deepStrictEqual(actual, expected, message); }
function throws(fn, pattern, message) { assertions++; assert.throws(fn, pattern, message); }
function hash(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'forever-deploy-fixtures-'));
function write(file, value) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, value); }
function makePackage(name, files = { 'GearExport.toc': '## Interface: 16001\n## X-WoWSync-Target: Forever\nWoWSyncForever.lua\n',
    'WoWSyncForever.lua': 'local F = { version = "1.60.1", tocInterface = 16001 }\nfunction C.IsForeverVersion(version, family) return family == "Forever" and version == F.version end\n', 'README.md': 'fixture package\n' }) {
    const directory = path.join(temp, name);
    fs.mkdirSync(directory, { recursive: true });
    const hashes = {};
    for (const [file, contents] of Object.entries(files)) {
        write(path.join(directory, file), contents);
        hashes[file] = hash(path.join(directory, file));
    }
    const interfaceValue = Number(fs.readFileSync(path.join(directory, 'GearExport.toc'), 'utf8').match(/^## Interface: (\d+)$/m)[1]);
    write(path.join(directory, 'package-manifest.json'), JSON.stringify({ target: 'Forever', interface: interfaceValue,
        clientVersion: '1.60.1', schema: 'WOWSYNC v1', hashes }, null, 2) + '\n');
    return directory;
}
function fixture(name, packagePath) {
    const base = path.join(temp, name);
    const destination = path.join(base, 'World', '_classic_beta_', 'Interface', 'AddOns', 'GearExport');
    const addons = path.dirname(destination);
    const backupRoot = path.join(base, 'backups');
    fs.mkdirSync(addons, { recursive: true });
    return { base, destination, addons, backupRoot, packagePath };
}
function deploy(args, hooks, clientBuild = '70291') {
    return deployForever({ ...args, hooks, clientVersion: '1.60.1', clientBuild, buildPackage: false,
        validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') });
}

try {
    const powershellLauncher = fs.readFileSync(path.join(__dirname, '..', 'scripts', 'deploy-forever.ps1'), 'utf8');
    check(/for\s*\(\$level\s*=\s*0;\s*\$level\s*-lt\s*3;\s*\$level\+\+\)/.test(powershellLauncher),
        'PowerShell launcher resolves WowB.exe from the Forever installation root');
    const futureInterfacePackage = makePackage('future-interface-package', {
        'GearExport.toc': '## Interface: 16002\n## X-WoWSync-Target: Forever\nWoWSyncForever.lua\n',
        'WoWSyncForever.lua': 'local F = { version = "1.60.1", tocInterface = 16002 }\nfunction C.IsForeverVersion(version, family) return family == "Forever" and version == F.version end\n',
        'README.md': 'future TOC metadata fixture\n',
    });
    equal(verifyPackage(futureInterfacePackage).build, { version: '1.60.1', tocInterface: 16002 },
        'Package verifier accepts updated numeric Forever TOC metadata without a code allowlist');
    const validPackage = makePackage('valid-package');
    const info = verifyPackage(validPackage);
    equal(info.build, { version: '1.60.1', tocInterface: 16001 }, 'Package records Forever version and TOC metadata without build allowlisting');
    const legacyGuardPackage = makePackage('legacy-single-build', {
        'GearExport.toc': '## Interface: 16001\n## X-WoWSync-Target: Forever\nWoWSyncForever.lua\n',
        'WoWSyncForever.lua': 'local F = { version = "1.60.1", build = "70291", interface = 16001 }\n',
        'README.md': 'legacy exact-build package fixture\n',
    });
    throws(() => verifyPackage(legacyGuardPackage), /runtime identity\/version contract.*exact build allowlist/,
        'Package verifier refuses to ship the old runtime exact-build gate');
    const malformedLegacyManifest = makePackage('malformed-legacy-manifest');
    const manifestPath = path.join(malformedLegacyManifest, 'package-manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    manifest.clientBuilds = ['next'];
    write(manifestPath, JSON.stringify(manifest));
    throws(() => verifyPackage(malformedLegacyManifest), /must not contain a client build allowlist/, 'Any legacy build-list metadata is rejected');
    const staleAllowlist = makePackage('stale-build-list');
    const staleManifestPath = path.join(staleAllowlist, 'package-manifest.json');
    const staleManifest = JSON.parse(fs.readFileSync(staleManifestPath, 'utf8'));
    staleManifest.clientBuilds = ['70291', '70338'];
    write(staleManifestPath, JSON.stringify(staleManifest));
    throws(() => verifyPackage(staleAllowlist), /must not contain a client build allowlist/, 'A plausible stale allowlist cannot ship as package metadata');
    for (const clientBuild of ['70291', '70338', '70412']) {
        const buildInstall = fixture('build-' + clientBuild, validPackage);
        equal(deploy(buildInstall, undefined, clientBuild).status, 'installed', 'Deployment accepts Forever build ' + clientBuild + ' when the version matches');
    }
    const install = fixture('fresh', validPackage);
    const freshResult = deploy(install);
    equal(freshResult.status, 'installed', 'Fresh installation succeeds');
    verifyDirectoryAgainstPackage(validPackage, install.destination);
    check(fs.existsSync(path.join(freshResult.backup, 'backup-manifest.json')), 'Fresh install writes a recovery record');

    const upgrade = fixture('upgrade', validPackage);
    for (const file of obsolete) write(path.join(upgrade.destination, file), 'obsolete ' + file);
    write(path.join(upgrade.destination, 'GearExport.toc'), 'old package');
    const beforeSaved = 'SavedVariables must remain unchanged';
    write(path.join(upgrade.base, 'World', '_classic_beta_', 'WTF', 'Account', 'SavedVariables', 'GearExport.lua'), beforeSaved);
    const unrelated = path.join(upgrade.addons, 'UnrelatedAddon', 'keep.lua');
    write(unrelated, 'keep');
    const upgradeResult = deploy(upgrade);
    verifyDirectoryAgainstPackage(validPackage, upgrade.destination);
    check(obsolete.every(file => !fs.existsSync(path.join(upgrade.destination, file))), 'Actual 70245-to-70291 fixture removes all eight obsolete modules');
    check(fs.readFileSync(unrelated, 'utf8') === 'keep', 'Unrelated addon directory is preserved');
    check(fs.readFileSync(path.join(upgrade.base, 'World', '_classic_beta_', 'WTF', 'Account', 'SavedVariables', 'GearExport.lua'), 'utf8') === beforeSaved,
        'SavedVariables remain untouched');
    const backupAddon = path.join(upgradeResult.backup, 'GearExport');
    check(obsolete.every(file => fs.existsSync(path.join(backupAddon, file))), 'Verified backup preserves all old modules');

    const badMissing = makePackage('missing-package');
    fs.rmSync(path.join(badMissing, 'README.md'));
    throws(() => verifyPackage(badMissing), /file set mismatch.*README\.md/, 'Missing package file rejected');
    const badExtra = makePackage('extra-package');
    write(path.join(badExtra, 'unexpected.lua'), 'unexpected');
    throws(() => verifyPackage(badExtra), /unexpected=\[unexpected\.lua\]/, 'Unexpected package file rejected');
    const badHash = makePackage('bad-hash-package');
    write(path.join(badHash, 'README.md'), 'corrupted');
    throws(() => verifyPackage(badHash), /Package hash mismatch/, 'Package hash mismatch rejected');
    for (const malformed of [badMissing, badExtra, badHash]) {
        const guarded = fixture('reject-' + path.basename(malformed), malformed);
        write(path.join(guarded.destination, 'existing.lua'), 'unchanged');
        throws(() => deploy(guarded), /file set mismatch|hash mismatch/i, 'Malformed package rejected before install mutation');
        check(fs.readFileSync(path.join(guarded.destination, 'existing.lua'), 'utf8') === 'unchanged', 'Preflight rejection preserves installation');
    }

    throws(() => validateForeverDestination(path.join(temp, 'Retail', 'Interface', 'AddOns', 'GearExport'), temp), /Refusing destination/,
        'Wrong client destination rejected');
    const wrong = fixture('wrong-destination', validPackage);
    wrong.destination = path.join(wrong.base, 'Retail', 'Interface', 'AddOns', 'GearExport');
    fs.mkdirSync(path.dirname(wrong.destination), { recursive: true });
    throws(() => deploy(wrong), /Refusing destination/, 'Wrong destination is rejected in preflight');
    const running = fixture('running', validPackage);
    throws(() => deployForever({ ...running, clientRunning: true, buildPackage: false, validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') }),
        /Forever client .* is running/, 'Running Forever client rejected');
    const mismatch = fixture('version-mismatch', validPackage);
    throws(() => deployForever({ ...mismatch, clientVersion: '1.61.0', clientBuild: '70412', buildPackage: false,
        validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') }),
        /different WoW client version/, 'A different client version is rejected to preserve strict version isolation');
    const malformedBuild = fixture('malformed-build', validPackage);
    throws(() => deployForever({ ...malformedBuild, clientVersion: '1.60.1', clientBuild: 'next', buildPackage: false,
        validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') }),
        /not a numeric build identifier/, 'Malformed executable build evidence is rejected without an allowlist');

    const broken = fixture('rollback', validPackage);
    write(path.join(broken.destination, 'old.lua'), 'preserve me');
    const failed = (() => {
        try { deploy(broken, { afterInstall() { throw new Error('fixture deployment failure'); } }); }
        catch (error) { return error; }
    })();
    check(failed && failed.rollbackStatus === 'restored-and-verified', 'Deployment failure automatically rolls back and verifies');
    check(fs.readFileSync(path.join(broken.destination, 'old.lua'), 'utf8') === 'preserve me', 'Rollback restores previous contents');

    const beforeMutation = fixture('stage-failure', validPackage);
    write(path.join(beforeMutation.destination, 'old.lua'), 'untouched');
    const stageFailure = (() => {
        try { deploy(beforeMutation, { afterStage() { throw new Error('fixture stage failure'); } }); }
        catch (error) { return error; }
    })();
    check(stageFailure && stageFailure.rollbackStatus === 'restored-and-verified', 'Stage failure verifies original install without replacing it');
    check(fs.readFileSync(path.join(beforeMutation.destination, 'old.lua'), 'utf8') === 'untouched', 'Stage failure leaves installed directory unchanged');

    const failedRollback = fixture('failed-rollback', validPackage);
    write(path.join(failedRollback.destination, 'old.lua'), 'preserve me');
    const failedRestore = (() => {
        try { deploy(failedRollback, { afterInstall() { throw new Error('deploy fail'); }, beforeRollback() { throw new Error('restore fail'); } }); }
        catch (error) { return error; }
    })();
    check(failedRestore && failedRestore.rollbackStatus === 'failed-recovery-artifacts-preserved', 'Failed rollback is reported');
    check(fs.existsSync(failedRestore.message.match(/Recovery backup: (.+?)(?:\. Previous-install artifact:|$)/)[1]), 'Failed rollback backup artifact is preserved');

    const repeat = deploy(install);
    equal(repeat.status, 'installed', 'Idempotent redeployment succeeds');
    verifyDirectoryAgainstPackage(validPackage, install.destination);
    console.log('PASS: ' + assertions + ' Forever deployment fixture assertions; no live installation touched');
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
