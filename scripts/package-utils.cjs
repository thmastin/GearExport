// Shared package and installation verification for the package and deploy scripts.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const hashFile = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const tocSources = { Retail: 'GearExport-Retail.toc', ClassicEra: 'GearExport-ClassicEra.toc', TBC: 'GearExport-BCC.toc', Forever: 'GearExport-Forever.toc' };

function readForeverRuntimeContract(source) {
    const match = source.match(/local\s+F\s*=\s*\{[^\r\n]*\bversion\s*=\s*["']([^"']+)["']/);
    if (!match || /\bsupportedBuilds\s*=/.test(source) || /IsSupportedForeverBuild/.test(source)
        || !/function\s+C\.IsForeverVersion\s*\(/.test(source)) return null;
    return { version: match[1] };
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
        if (!/^## X-WoWSync-Target: Forever\r?$/m.test(toc)) {
            throw new Error('Package TOC does not carry the Forever interface/target markers');
        }
        const interfaceMatch = toc.match(/^## Interface:\s*(\d+)\s*$/m);
        const runtime = readForeverRuntimeContract(guard);
        if (!interfaceMatch) throw new Error('Forever package TOC has no numeric Interface declaration');
        if (!runtime) throw new Error('Forever runtime identity/version contract is missing or contains an exact build allowlist');
        if (manifest.interface !== Number(interfaceMatch[1])) throw new Error('Forever manifest interface does not match its TOC');
        if (manifest.clientVersion !== runtime.version) throw new Error('Forever manifest version does not match the runtime guard');
        if (Object.hasOwn(manifest, 'clientBuilds')) throw new Error('Forever manifest must not contain a client build allowlist');
        runtime.tocInterface = Number(interfaceMatch[1]);
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
    tocSources, readForeverRuntimeContract,
};
