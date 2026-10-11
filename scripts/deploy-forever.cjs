// Build, preflight, back up, and exactly synchronize the Forever package.
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const {
    hashFile, listTree, verifyPackage, verifyDirectoryAgainstPackage,
    assertPackageMatchesSource, validateForeverDestination,
} = require('./package-utils.cjs');

const root = path.resolve(__dirname, '..');
const defaultDestination = 'D:\\World of Warcraft\\_classic_beta_\\Interface\\AddOns\\GearExport';
const defaultBackupRoot = path.join(process.env.LOCALAPPDATA || os.homedir(), 'GearExport', 'ForeverDeploymentBackups');
const uuid = () => crypto.randomUUID();
const die = message => { throw new Error(message); };

function ensureBackupOutsideAddons(backupRoot, destination) {
    const backup = path.resolve(backupRoot);
    const addons = path.dirname(destination).toLowerCase() + path.sep.toLowerCase();
    if (backup.toLowerCase().startsWith(addons) || backup.toLowerCase() === destination.toLowerCase()) {
        die('Backup root must be outside the Forever AddOns directory: ' + backup);
    }
    return backup;
}

function snapshot(directory) {
    const entries = listTree(directory);
    const files = {};
    for (const entry of entries) if (!entry.endsWith('/')) files[entry] = hashFile(path.join(directory, entry));
    return { entries, files };
}

function verifySnapshot(directory, expected) {
    const actual = snapshot(directory);
    if (JSON.stringify(actual.entries) !== JSON.stringify(expected.entries)) throw new Error('Backup file set does not match original installation');
    const bad = Object.keys(expected.files).filter(file => actual.files[file] !== expected.files[file]);
    if (bad.length) throw new Error('Backup hash mismatch: ' + bad.join(', '));
}

function copyTree(source, destination) {
    fs.cpSync(source, destination, { recursive: true, errorOnExist: true, force: false, dereference: false });
}

function removeTree(directory) {
    if (fs.existsSync(directory)) fs.rmSync(directory, { recursive: true, force: true });
}

function detectForeverRunning() {
    if (process.platform !== 'win32') return false;
    const result = spawnSync('tasklist.exe', ['/FI', 'IMAGENAME eq WowB.exe', '/FO', 'CSV', '/NH'], { encoding: 'utf8' });
    if (result.error || result.status !== 0) throw new Error('Could not check for the Forever process; refusing deployment. ' + (result.error?.message || result.stderr || ''));
    return /^\s*"WowB\.exe"/im.test(result.stdout || '');
}

function getCommittedSource(rootPath) {
    const status = spawnSync('git', ['status', '--porcelain', '--untracked-files=no'], { cwd: rootPath, encoding: 'utf8' });
    if (status.error || status.status !== 0) throw new Error('Could not verify the committed source state: ' + (status.error?.message || status.stderr || ''));
    if ((status.stdout || '').trim()) throw new Error('Tracked source changes are present. Commit the reviewed source before deploying. Untracked files are preserved and do not block deployment.');
    const commit = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: rootPath, encoding: 'utf8' });
    if (commit.error || commit.status !== 0) throw new Error('Could not read the source commit: ' + (commit.error?.message || commit.stderr || ''));
    return commit.stdout.trim();
}

function deployForever({ destination, backupRoot, clientRunning = false, hooks = {},
    repositoryRoot = root, packagePath = path.join(repositoryRoot, 'dist', 'Forever', 'GearExport'),
    buildPackage = true, validateSource = true, detectProcess = true, requireCommittedSource = true,
    clientVersion, clientBuild }) {
    const projectRoot = path.resolve(repositoryRoot);
    const packageDirectory = path.resolve(packagePath);
    const install = validateForeverDestination(destination, projectRoot);
    const backups = ensureBackupOutsideAddons(backupRoot, install);
    if (clientRunning || (detectProcess && detectForeverRunning())) die('Forever client (WowB.exe) is running. Close Forever completely and retry.');
    const sourceCommit = requireCommittedSource ? getCommittedSource(projectRoot) : 'fixture';

    // Package once through the repository's existing builder, then validate its complete manifest contract.
    if (buildPackage) {
        const build = spawnSync(process.execPath, [path.join(projectRoot, 'scripts', 'package.cjs'), 'Forever'], { cwd: projectRoot, encoding: 'utf8' });
        if (build.error || build.status !== 0) die('Forever package build failed: ' + (build.stderr || build.error?.message || 'unknown error'));
        if (build.stdout) process.stdout.write(build.stdout);
    }
    const packageInfo = verifyPackage(packageDirectory);
    if (validateSource) assertPackageMatchesSource(projectRoot, packageDirectory, packageInfo);
    if (requireCommittedSource && (!clientVersion || !clientBuild)) die('Target WowB.exe version/build evidence was not supplied by the PowerShell launcher.');
    if (clientVersion && clientBuild && (clientVersion !== packageInfo.build.version || !packageInfo.build.builds.includes(String(clientBuild)))) {
        die('Target Forever client is ' + clientVersion + '/' + clientBuild + ' but package guard allows ' +
            packageInfo.build.version + '/' + packageInfo.build.builds.join(',') + '; refusing incompatible deployment.');
    }
    if (hooks.afterPreflight) hooks.afterPreflight({ packagePath: packageDirectory, install, packageInfo });

    fs.mkdirSync(backups, { recursive: true });
    const recoveryId = new Date().toISOString().replace(/[:.]/g, '-') + '-' + uuid();
    const recovery = path.join(backups, recoveryId);
    const backupAddon = path.join(recovery, 'GearExport');
    const backupManifest = path.join(recovery, 'backup-manifest.json');
    const existed = fs.existsSync(install);
    let originalSnapshot = null;
    fs.mkdirSync(recovery, { recursive: true });
    try {
        if (existed) {
            originalSnapshot = snapshot(install);
            copyTree(install, backupAddon);
            verifySnapshot(backupAddon, originalSnapshot);
            fs.writeFileSync(backupManifest, JSON.stringify({ createdAt: new Date().toISOString(), sourceCommit,
                packageManifestSHA256: hashFile(path.join(packageDirectory, 'package-manifest.json')),
                entries: originalSnapshot.entries, hashes: originalSnapshot.files }, null, 2) + '\n');
            const persisted = JSON.parse(fs.readFileSync(backupManifest, 'utf8'));
            verifySnapshot(backupAddon, { entries: persisted.entries, files: persisted.hashes });
        } else {
            fs.writeFileSync(backupManifest, JSON.stringify({ createdAt: new Date().toISOString(), sourceCommit,
                packageManifestSHA256: hashFile(path.join(packageDirectory, 'package-manifest.json')),
                destinationPreviouslyExisted: false }, null, 2) + '\n');
        }
        if (hooks.afterBackup) hooks.afterBackup({ recovery, backupAddon, originalSnapshot, existed });
    } catch (error) {
        throw new Error('Pre-deployment backup failed; installation was not touched. Recovery record: ' + recovery + '. ' + error.message);
    }

    const stage = path.join(path.dirname(install), '.GearExport-stage-' + uuid());
    const previous = path.join(path.dirname(install), '.GearExport-previous-' + uuid());
    let oldRenamed = false;
    let newInstalled = false;
    try {
        copyTree(packageDirectory, stage);
        verifyDirectoryAgainstPackage(packageDirectory, stage);
        if (hooks.afterStage) hooks.afterStage({ stage, packageInfo });
        if (existed) {
            fs.renameSync(install, previous);
            oldRenamed = true;
        }
        fs.renameSync(stage, install);
        newInstalled = true;
        if (hooks.afterInstall) hooks.afterInstall({ install, packageInfo });
        verifyDirectoryAgainstPackage(packageDirectory, install);
        let cleanupWarning = null;
        if (oldRenamed) {
            try { removeTree(previous); } catch (error) { cleanupWarning = 'Verified installation is live; previous-install cleanup remains at ' + previous + ': ' + error.message; }
        }
        return {
            status: 'installed', install, backup: recovery, sourceCommit, files: packageInfo.entries.length,
            manifestHash: hashFile(path.join(packageDirectory, 'package-manifest.json')),
            guard: packageInfo.build, cleanupWarning,
        };
    } catch (deploymentError) {
        let rollbackStatus = 'not-needed';
        let rollbackError = null;
        try {
            if (hooks.beforeRollback) hooks.beforeRollback({ install, previous, backupAddon, existed });
            if (oldRenamed && fs.existsSync(previous)) {
                if (fs.existsSync(install)) removeTree(install);
                fs.renameSync(previous, install);
                verifySnapshot(install, originalSnapshot);
                rollbackStatus = 'restored-and-verified';
            } else if (existed && !newInstalled) {
                verifySnapshot(install, originalSnapshot);
                rollbackStatus = 'restored-and-verified';
            } else if (existed) {
                if (fs.existsSync(install)) removeTree(install);
                copyTree(backupAddon, install);
                verifySnapshot(install, originalSnapshot);
                rollbackStatus = 'restored-and-verified';
            } else {
                if (newInstalled && fs.existsSync(install)) removeTree(install);
                if (fs.existsSync(install)) throw new Error('Fresh-install rollback left an installation directory');
                rollbackStatus = 'fresh-install-removed';
            }
        } catch (error) {
            rollbackStatus = 'failed-recovery-artifacts-preserved';
            rollbackError = error.message;
        }
        if (rollbackStatus !== 'failed-recovery-artifacts-preserved') {
            try { removeTree(previous); removeTree(stage); } catch (_) { /* Leave any remaining recovery artifact in place. */ }
        }
        const result = new Error('Deployment failed: ' + deploymentError.message + '. Rollback: ' + rollbackStatus +
            (rollbackError ? ' (' + rollbackError + ')' : '') + '. Recovery backup: ' + recovery +
            (fs.existsSync(previous) ? '. Previous-install artifact: ' + previous : '') +
            (fs.existsSync(stage) ? '. Staging artifact: ' + stage : ''));
        result.deploymentStatus = 'failed';
        result.rollbackStatus = rollbackStatus;
        throw result;
    }
}

function parseArgs(args) {
    const values = { destination: defaultDestination, backupRoot: defaultBackupRoot, clientVersion: undefined, clientBuild: undefined };
    for (let index = 0; index < args.length; index++) {
        const arg = args[index];
        if (arg === '--destination') values.destination = args[++index];
        else if (arg === '--backup-root') values.backupRoot = args[++index];
        else if (arg === '--client-version') values.clientVersion = args[++index];
        else if (arg === '--client-build') values.clientBuild = args[++index];
        else throw new Error('Unknown option: ' + arg);
        if (!values.destination && arg === '--destination') throw new Error('--destination requires a path');
        if (!values.backupRoot && arg === '--backup-root') throw new Error('--backup-root requires a path');
        if (['--client-version', '--client-build'].includes(arg) && !args[index]) throw new Error(arg + ' requires a value');
    }
    return values;
}

if (require.main === module) {
    try {
        const result = deployForever(parseArgs(process.argv.slice(2)));
        console.log('INSTALLATION STATUS: SUCCESS - exact file set and SHA256 hashes verified.');
        console.log(JSON.stringify(result, null, 2));
    } catch (error) {
        console.error((error.deploymentStatus ? 'INSTALLATION STATUS: FAILED; ' : 'PREFLIGHT STATUS: FAILED; ') + error.message);
        process.exitCode = 1;
    }
}

module.exports = { deployForever, parseArgs, snapshot, verifySnapshot, detectForeverRunning };
