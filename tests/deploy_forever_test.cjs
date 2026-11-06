// Temporary-fixture integration coverage for the single-command Forever deploy workflow.
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
const { deployForever, detectForeverRunning } = require('../scripts/deploy-forever.cjs');
const { verifyPackage, verifyDirectoryAgainstPackage, validateForeverDestination, resolveForeverClient } = require('../scripts/package-utils.cjs');

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
    'WoWSyncForever.lua': 'local F = { version = "1.60.1", interface = 16001, minimumBuild = 70291, verifiedBuilds = { ["70291"] = true, ["70338"] = true, ["70450"] = true } }\n', 'README.md': 'fixture package\n' }) {
    const directory = path.join(temp, name);
    fs.mkdirSync(directory, { recursive: true });
    const hashes = {};
    for (const [file, contents] of Object.entries(files)) {
        write(path.join(directory, file), contents);
        hashes[file] = hash(path.join(directory, file));
    }
    write(path.join(directory, 'package-manifest.json'), JSON.stringify({ target: 'Forever', interface: 16001,
        clientVersion: '1.60.1', clientBuilds: ['70291', '70338', '70450'], schema: 'WOWSYNC v1', hashes }, null, 2) + '\n');
    return directory;
}
function fixture(name, packagePath, layout = 'classic_beta') {
    const base = path.join(temp, name);
    const flavorFolder = layout === 'forever' ? '_forever_' : '_classic_beta_';
    const clientRoot = path.join(base, 'World', flavorFolder);
    const destination = path.join(clientRoot, 'Interface', 'AddOns', 'GearExport');
    const addons = path.dirname(destination);
    const backupRoot = path.join(base, 'backups');
    fs.mkdirSync(addons, { recursive: true });
    fs.writeFileSync(path.join(clientRoot, layout === 'forever' ? 'Wow.exe' : 'WowB.exe'), 'fixture executable');
    if (layout === 'forever') write(path.join(clientRoot, '.flavor.info'), 'Product Flavor!STRING:0\nwowf\n');
    return { base, clientRoot, destination, addons, backupRoot, packagePath };
}
function deploy(args, hooks, clientBuild = '70291') {
    return deployForever({ ...args, hooks, clientVersion: '1.60.1', clientBuild, buildPackage: false,
        validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') });
}

try {
    const powershellLauncher = fs.readFileSync(path.join(__dirname, '..', 'scripts', 'deploy-forever.ps1'), 'utf8');
    check(/Wow\.exe/.test(powershellLauncher) && /WowB\.exe/.test(powershellLauncher)
        && /\.flavor\.info/.test(powershellLauncher) && /Win32_Process/.test(powershellLauncher),
        'PowerShell launcher selects the client executable from either validated layout and checks running processes');
    const validPackage = makePackage('valid-package');
    const info = verifyPackage(validPackage);
    equal(info.build, { version: '1.60.1', interface: 16001, minimumBuild: 70291, builds: ['70291', '70338', '70450'] }, 'Preserves the minimum and verified runtime build contract');
    equal(info.manifest.clientBuilds, ['70291', '70338', '70450'], 'Manifest clientBuilds remains the verified build set');
    const legacyLayout = fixture('legacy-layout', validPackage);
    equal(resolveForeverClient(legacyLayout.destination).executable, 'WowB.exe', 'Classic beta layout selects WowB.exe');
    const launchLayout = fixture('launch-layout', validPackage, 'forever');
    equal(resolveForeverClient(launchLayout.destination).executable, 'Wow.exe', 'Forever launch layout selects Wow.exe');
    equal(validateForeverDestination(launchLayout.destination, path.join(temp, 'test-repository')), launchLayout.destination,
        'Forever launch layout remains within validated destination rules');
    const wrongFlavor = fixture('wrong-flavor', validPackage, 'forever');
    write(path.join(wrongFlavor.clientRoot, '.flavor.info'), 'Product Flavor!STRING:0\nwowb\n');
    throws(() => validateForeverDestination(wrongFlavor.destination, path.join(temp, 'test-repository')), /does not identify the Forever launch flavor/,
        'Launch layout with another flavor metadata is rejected');
    const wrongPath = fixture('wrong-path', validPackage);
    wrongPath.destination = path.join(wrongPath.base, 'World', '_retail_', 'Interface', 'AddOns', 'GearExport');
    throws(() => validateForeverDestination(wrongPath.destination, path.join(temp, 'test-repository')), /Refusing destination/,
        'Unsupported client folder is rejected');
    const tasklist = (_command, args) => ({ status: 0, stdout: args[1].includes('Wow.exe') ? '"Wow.exe","1234"' : 'INFO: No tasks are running' });
    check(detectForeverRunning(tasklist, 'win32'), 'Running Wow.exe launch client is detected');
    check(detectForeverRunning((_command, args) => ({ status: 0, stdout: args[1].includes('WowB.exe') ? '"WowB.exe","1234"' : 'INFO: No tasks are running' }), 'win32'),
        'Running WowB.exe beta client is detected');
    const legacyGuardPackage = makePackage('legacy-single-build', {
        'GearExport.toc': '## Interface: 16001\n## X-WoWSync-Target: Forever\nWoWSyncForever.lua\n',
        'WoWSyncForever.lua': 'local F = { version = "1.60.1", build = "70291", interface = 16001 }\n',
        'README.md': 'legacy verified package fixture\n',
    });
    const legacyManifestPath = path.join(legacyGuardPackage, 'package-manifest.json');
    const legacyManifest = JSON.parse(fs.readFileSync(legacyManifestPath, 'utf8'));
    delete legacyManifest.clientVersion;
    delete legacyManifest.clientBuilds;
    write(legacyManifestPath, JSON.stringify(legacyManifest));
    equal(verifyPackage(legacyGuardPackage).build.builds, ['70291'], 'Previously generated exact single-build packages remain verifiable');
    const mismatchedManifest = makePackage('manifest-mismatch');
    const manifestPath = path.join(mismatchedManifest, 'package-manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    manifest.clientBuilds = ['70291', '70339'];
    write(manifestPath, JSON.stringify(manifest));
    throws(() => verifyPackage(mismatchedManifest), /manifest build allowlist does not match/, 'Manifest cannot broaden the runtime build allowlist');
    const latestBuildInstall = fixture('latest-build', validPackage);
    equal(deploy(latestBuildInstall, undefined, '70450').status, 'installed', 'Deployment accepts a verified Forever update');
    const newerBuildInstall = fixture('newer-build', validPackage);
    const unverifiedBuildInstall = fixture('unverified-build-70790', validPackage, 'forever');
    const unverifiedResult = deploy(unverifiedBuildInstall, undefined, '70790');
    equal(unverifiedResult.status, 'installed', 'Deployment accepts build 70790 above minimum');
    equal(unverifiedResult.compatibility, 'UNVERIFIED_BUILD', 'Build 70790 remains explicitly unverified');
    check(!info.manifest.clientBuilds.includes('70790'), 'Build 70790 is not added to the verified manifest set');
    equal(deploy(newerBuildInstall, undefined, '70999').compatibility, 'UNVERIFIED_BUILD', 'Newer unlisted build remains unverified');
    const install = fixture('fresh', validPackage);
    const freshResult = deploy(install);
    equal(freshResult.status, 'installed', 'Fresh installation succeeds');
    equal(freshResult.sourceCommit, 'uncommitted-working-tree', 'Local authorized deployment is labelled without inventing a commit SHA');
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
        /Forever client process is running/, 'Running Forever client rejected');
    const mismatch = fixture('guard-mismatch', validPackage);
    throws(() => deployForever({ ...mismatch, clientVersion: '1.60.1', clientBuild: '70009', buildPackage: false,
        validateSource: false, detectProcess: false, requireCommittedSource: false, repositoryRoot: path.join(temp, 'test-repository') }),
        /refusing incompatible deployment/, 'Target executable build below the minimum is refused');
    const unknown = fixture('unknown-guard-build', validPackage);
    throws(() => deploy(unknown, undefined, '70009'), /refusing incompatible deployment/, 'A below-minimum build is refused');

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
