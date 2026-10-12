// Temporary-fixture integration coverage for the single-command Forever deploy workflow.
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
const { deployForever, isForeverVersion } = require('../scripts/deploy-forever.cjs');
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
function makePackage(name, files = { 'GearExport.toc': '## Interface: 16001\n## AllowLoadGameType: camelot\n## X-WoWSync-Target: Forever\nWoWSyncForever.lua\n',
    'WoWSyncForever.lua': 'local F = { family = "Forever", knownProfiles = { ["1.60.1:70291:16001"] = true, ["1.60.1:70338:16001"] = true } }\n', 'README.md': 'fixture package\n' }) {
    const directory = path.join(temp, name);
    fs.mkdirSync(directory, { recursive: true });
    const hashes = {};
    for (const [file, contents] of Object.entries(files)) {
        write(path.join(directory, file), contents);
        hashes[file] = hash(path.join(directory, file));
    }
    write(path.join(directory, 'package-manifest.json'), JSON.stringify({ target: 'Forever', interface: 16001,
        validatedProfiles: ['1.60.1:70291:16001', '1.60.1:70338:16001'], schema: 'WOWSYNC v1', hashes }, null, 2) + '\n');
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
    const validPackage = makePackage('valid-package');
    check(isForeverVersion('1.60.2') && isForeverVersion('1.75.0'), 'Routine Forever 1.6x+ patch lines are recognized');
    check(!isForeverVersion('1.15.9') && !isForeverVersion('2.5.6'), 'Classic Era and TBC version families are rejected');
    const info = verifyPackage(validPackage);
    equal(info.build, { family: 'Forever', profiles: ['1.60.1:70291:16001', '1.60.1:70338:16001'] }, 'Preserves exact previously validated client profiles');
    const legacyGuardPackage = makePackage('legacy-single-build', {
        'GearExport.toc': '## Interface: 16001\n## AllowLoadGameType: camelot\n## X-WoWSync-Target: Forever\nWoWSyncForever.lua\n',
        'WoWSyncForever.lua': 'local F = { version = "1.60.1", build = "70291", interface = 16001 }\n',
        'README.md': 'legacy verified package fixture\n',
    });
    const legacyManifestPath = path.join(legacyGuardPackage, 'package-manifest.json');
    const legacyManifest = JSON.parse(fs.readFileSync(legacyManifestPath, 'utf8'));
    delete legacyManifest.validatedProfiles;
    write(legacyManifestPath, JSON.stringify(legacyManifest));
    throws(() => verifyPackage(legacyGuardPackage), /runtime must identify the Forever family/, 'Legacy exact-build package guard rejected for rebuild until migrated');
    const mismatchedManifest = makePackage('manifest-mismatch');
    const manifestPath = path.join(mismatchedManifest, 'package-manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    manifest.validatedProfiles = ['1.60.1:70291:16001', '1.60.1:70339:16001'];
    write(manifestPath, JSON.stringify(manifest));
    throws(() => verifyPackage(mismatchedManifest), /validated profile evidence does not match/, 'Manifest cannot forge compatibility evidence');
    const mismatchedProfileInterface = makePackage('profile-interface-mismatch', {
        'GearExport.toc': '## Interface: 16001\n## AllowLoadGameType: camelot\n## X-WoWSync-Target: Forever\nWoWSyncForever.lua\n',
        'WoWSyncForever.lua': 'local F = { family = "Forever", knownProfiles = { ["1.60.1:70291:16002"] = true } }\n',
        'README.md': 'fixture package\n',
    });
    throws(() => verifyPackage(mismatchedProfileInterface), /profile interface does not match package interface/,
        'Verified client profile cannot claim an interface different from the package TOC');
    const latestBuildInstall = fixture('latest-build', validPackage);
    equal(deploy(latestBuildInstall, undefined, '70338').status, 'installed', 'Deployment accepts an exactly allowlisted Forever update');
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
    const updateVersion = fixture('routine-update-version', validPackage);
    equal(deployForever({ ...updateVersion, clientVersion: '1.60.2', clientBuild: '70400', buildPackage: false,
        validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') }).status,
        'installed', 'Guarded installer does not reject routine version/build updates for the Forever target');
    for (const [clientVersion, clientBuild] of [['12.1.0', '120100'], ['1.15.9', '11509'], ['2.5.6', '20506'], ['1.60.1', 'bad']]) {
        const rejected = fixture('invalid-executable-' + clientVersion.replaceAll('.', '-'), validPackage);
        throws(() => deployForever({ ...rejected, clientVersion, clientBuild, buildPackage: false,
            validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') }),
            /not a Forever 1\.60/, 'Malformed/non-Forever executable identity is rejected');
    }

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
