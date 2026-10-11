// Shared package and installation verification for the package and deploy scripts.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const hashFile = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const tocSources = { Retail: 'GearExport-Retail.toc', ClassicEra: 'GearExport-ClassicEra.toc', TBC: 'GearExport-BCC.toc', Forever: 'GearExport-Forever.toc' };

function readForeverBuildGuard(source) {
    const match = source.match(/local\s+F\s*=\s*\{[^\r\n]*\bversion\s*=\s*["']([^"']+)["'][^\r\n]*\binterface\s*=\s*(\d+)[^\r\n]*\bsupportedBuilds\s*=\s*\{([^}]*)\}/);
    if (match) {
        const builds = [...match[3].matchAll(/\["(\d+)"\]\s*=\s*true/g)].map(entry => entry[1]);
        const remainder = match[3].replace(/\["\d+"\]\s*=\s*true/g, '').replace(/[\s,]/g, '');
        if (!builds.length || remainder || new Set(builds).size !== builds.length) return null;
        return { version: match[1], interface: Number(match[2]), builds: builds.sort() };
    }
    const legacy = source.match(/local\s+F\s*=\s*\{[^\r\n]*\bversion\s*=\s*["']([^"']+)["'][^\r\n]*\bbuild\s*=\s*["'](\d+)["'][^\r\n]*\binterface\s*=\s*(\d+)/);
    return legacy ? { version: legacy[1], interface: Number(legacy[3]), builds: [legacy[2]] } : null;
}

function listTree(directory) {
    const entries = [];
    function visit(current, relative) {
        for (const item of fs.readdirSync(current, { withFileTypes: true })) {
            const rel = relative ? relative + '/' + item.name : item.name;
            const full = path.join(current, item.name);
            const stat = fs.lstatSync(full);
            if (stat.isSymbolicLink()) throw new Error('Symbolic links are not allowed in packages or addon directories: ' + rel);
            if (stat.isDirectory()) {
                entries.push(rel + '/');
                visit(full, rel);
            } else if (stat.isFile()) entries.push(rel);
            else throw new Error('Unsupported filesystem entry: ' + rel);
        }
    }
    visit(directory, '');
    return entries.sort();
}

function readManifest(packagePath, expectedTarget) {
    const manifestPath = path.join(packagePath, 'package-manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    if (!manifest || !Object.hasOwn(tocSources, manifest.target) || !Number.isInteger(manifest.interface) || manifest.schema !== 'WOWSYNC v1') {
        throw new Error('Package manifest must identify a supported target, interface, and WOWSYNC v1');
    }
    if (expectedTarget && manifest.target !== expectedTarget) throw new Error('Expected ' + expectedTarget + ' package, found ' + manifest.target);
    if (!manifest.hashes || typeof manifest.hashes !== 'object' || Array.isArray(manifest.hashes) || !Object.keys(manifest.hashes).length) {
        throw new Error('Package manifest has no file hash map');
    }
    for (const [file, expected] of Object.entries(manifest.hashes)) {
        if (path.basename(file) !== file || file === 'package-manifest.json' || !/^[a-f0-9]{64}$/i.test(expected)) {
            throw new Error('Invalid package manifest entry: ' + file);
        }
    }
    return manifest;
}

function expectedPackageEntries(manifest) {
    return [...Object.keys(manifest.hashes), 'package-manifest.json'].sort();
}

function assertExactEntries(directory, expected, description) {
    const actual = listTree(directory);
    const missing = expected.filter(entry => !actual.includes(entry));
    const extra = actual.filter(entry => !expected.includes(entry));
    if (missing.length || extra.length) {
        throw new Error(description + ' file set mismatch; missing=[' + missing.join(', ') + '], unexpected=[' + extra.join(', ') + ']');
    }
}

function verifyPackage(packagePath, target = 'Forever') {
    const manifest = readManifest(packagePath, target);
    assertExactEntries(packagePath, expectedPackageEntries(manifest), 'Package');
    const failures = [];
    for (const [file, expected] of Object.entries(manifest.hashes)) {
        const actual = hashFile(path.join(packagePath, file));
        if (actual.toLowerCase() !== expected.toLowerCase()) failures.push(file + ': expected ' + expected + ', got ' + actual);
    }
    if (failures.length) throw new Error('Package hash mismatch: ' + failures.join('; '));
    if (manifest.target === 'Forever') {
        const toc = fs.readFileSync(path.join(packagePath, 'GearExport.toc'), 'utf8');
        const guard = fs.readFileSync(path.join(packagePath, 'WoWSyncForever.lua'), 'utf8');
        if (manifest.interface !== 16001 || !/^## Interface: 16001\r?$/m.test(toc) || !/^## X-WoWSync-Target: Forever\r?$/m.test(toc)) {
            throw new Error('Package TOC does not carry the Forever interface/target markers');
        }
        const runtime = readForeverBuildGuard(guard);
        if (!runtime) throw new Error('Forever runtime guard is missing or does not contain an exact build allowlist');
        if (runtime.interface !== manifest.interface) throw new Error('Forever manifest interface does not match the runtime guard');
        if (manifest.clientVersion !== undefined && manifest.clientVersion !== runtime.version) throw new Error('Forever manifest version does not match the runtime guard');
        if (manifest.clientBuilds !== undefined) {
            if (!Array.isArray(manifest.clientBuilds) || manifest.clientBuilds.some(build => typeof build !== 'string')
                || JSON.stringify([...manifest.clientBuilds].sort()) !== JSON.stringify(runtime.builds)) {
                throw new Error('Forever manifest build allowlist does not match the runtime guard');
            }
        }
        return { manifest, build: runtime, entries: expectedPackageEntries(manifest) };
    }
    return { manifest, build: null, entries: expectedPackageEntries(manifest) };
}

function verifyDirectoryAgainstPackage(packagePath, directory, target = 'Forever') {
    const packageInfo = verifyPackage(packagePath, target);
    assertExactEntries(directory, packageInfo.entries, 'Installed addon');
    const failures = [];
    for (const [file, expected] of Object.entries(packageInfo.manifest.hashes)) {
        const actual = hashFile(path.join(directory, file));
        if (actual.toLowerCase() !== expected.toLowerCase()) failures.push(file + ': expected ' + expected + ', got ' + actual);
    }
    const packageManifestHash = hashFile(path.join(packagePath, 'package-manifest.json'));
    if (hashFile(path.join(directory, 'package-manifest.json')) !== packageManifestHash) failures.push('package-manifest.json differs from reviewed package');
    if (failures.length) throw new Error('Installed addon hash mismatch: ' + failures.join('; '));
    return packageInfo;
}

function assertPackageMatchesSource(root, packagePath, packageInfo, target = 'Forever') {
    const tocSource = path.join(root, tocSources[target]);
    if (!fs.existsSync(tocSource) || !fs.readFileSync(tocSource).equals(fs.readFileSync(path.join(packagePath, 'GearExport.toc')))) {
        throw new Error('Package TOC does not match the Forever source TOC');
    }
    for (const [file, expected] of Object.entries(packageInfo.manifest.hashes)) {
        const source = path.join(root, file === 'GearExport.toc' ? tocSources[target] : file);
        if (!fs.existsSync(source) || hashFile(source).toLowerCase() !== expected.toLowerCase()) {
            throw new Error('Package does not match current source: ' + file);
        }
    }
    return true;
}

function validateForeverDestination(destination, repositoryRoot) {
    const resolved = path.resolve(destination);
    const parts = resolved.split(path.sep).filter(Boolean).map(part => part.toLowerCase());
    const suffix = ['_classic_beta_', 'interface', 'addons', 'gearexport'];
    if (parts.length < suffix.length || !suffix.every((part, index) => parts[parts.length - suffix.length + index] === part)) {
        throw new Error('Refusing destination outside *_classic_beta_/Interface/AddOns/GearExport: ' + resolved);
    }
    const repo = path.resolve(repositoryRoot).toLowerCase();
    if (resolved.toLowerCase() === repo || resolved.toLowerCase().startsWith(repo + path.sep.toLowerCase())) {
        throw new Error('Refusing to deploy into the repository: ' + resolved);
    }
    const addons = path.dirname(resolved);
    if (!fs.existsSync(addons) || !fs.statSync(addons).isDirectory()) throw new Error('Forever AddOns parent directory does not exist: ' + addons);
    // Reject symlink/junction redirection in any existing path component, not only GearExport itself.
    const parsed = path.parse(resolved);
    let current = parsed.root;
    for (const component of resolved.slice(parsed.root.length).split(path.sep).filter(Boolean)) {
        current = path.join(current, component);
        if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) {
            throw new Error('Refusing redirected (symlink/junction) deployment path component: ' + current);
        }
    }
    if (fs.existsSync(resolved) && !fs.statSync(resolved).isDirectory()) {
        throw new Error('Destination must be a real GearExport directory: ' + resolved);
    }
    return resolved;
}

module.exports = {
    hashFile, listTree, readManifest, expectedPackageEntries, verifyPackage,
    verifyDirectoryAgainstPackage, assertPackageMatchesSource, validateForeverDestination,
    tocSources, readForeverBuildGuard,
};
