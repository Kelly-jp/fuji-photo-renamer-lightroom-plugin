import * as fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { root, hashFile } from './packaging.mjs';
import { pluginVersion } from './package.mjs';

export function releasePlan(tag, info, changelog) {
    // Windows Git checkouts may use CRLF; notes must match the macOS artifact byte-for-byte.
    changelog = changelog.replace(/\r\n/g, '\n');
    if (!/^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$/.test(tag)) {
        throw new Error('Release tag must be vMAJOR.MINOR.PATCH without a suffix');
    }
    const { version } = pluginVersion(info);
    if (tag !== `v${version}`) throw new Error(`Tag ${tag} does not match Info.lua version ${version}. Update the version before creating a new tag.`);
    const sections = [...changelog.matchAll(/^## (?:\[([^\]\r\n]+)\]|([^\s\r\n]+))[^\r\n]*\r?$/gm)];
    const matches = sections.filter(entry => (entry[1] ?? entry[2]) === version);
    if (matches.length !== 1) {
        throw new Error(`CHANGELOG.md must contain exactly one section "## [${version}]" with release notes before pushing ${tag}; found ${matches.length}. Unreleased is not used as release notes. An existing tag still points to its original commit; re-running it will not include changes made later on main.`);
    }
    const entry = matches[0];
    const next = sections.find(candidate => candidate.index > entry.index);
    const notes = changelog.slice(entry.index + entry[0].length, next?.index ?? changelog.length).trim();
    if (!notes) throw new Error('Release notes must not be empty');
    const assets = ['macos', 'windows'].flatMap(platform => {
        const name = `fuji-photo-renamer-lightroom-plugin-${version}-${platform}.zip`;
        return [name, `${name}.sha256`];
    });
    return { tag, version, notes: `${notes}\n`, assets };
}

export async function verifyAssets(directory, plan) {
    // Only the two OS ZIPs, their checksums and matching notes may reach the release job.
    const expected = [...plan.assets, 'release-notes.md'].sort();
    const names = (await fs.readdir(directory)).sort();
    if (JSON.stringify(names) !== JSON.stringify(expected)) throw new Error('Missing or unexpected release assets');
    for (const name of expected) {
        if (!(await fs.lstat(path.join(directory, name))).isFile()) throw new Error('Release assets must be regular files');
    }
    if (await fs.readFile(path.join(directory, 'release-notes.md'), 'utf8') !== plan.notes) {
        throw new Error('Release notes differ from the tagged CHANGELOG');
    }
    for (const name of plan.assets.filter(name => name.endsWith('.zip'))) {
        const checksum = await fs.readFile(path.join(directory, `${name}.sha256`), 'utf8');
        const match = checksum.match(/^([a-f0-9]{64})  ([^\r\n]+)\r?\n?$/);
        if (!match || match[2] !== name || await hashFile(path.join(directory, name)) !== match[1]) {
            throw new Error(`Release asset SHA-256 mismatch: ${name}`);
        }
    }
}

async function main() {
    const [command, tag, directory, ...extra] = process.argv.slice(2);
    if (!['prepare', 'verify'].includes(command) || !tag || !directory || extra.length) {
        throw new Error('Usage: node scripts/release.mjs prepare|verify vMAJOR.MINOR.PATCH <asset-directory>');
    }
    const plan = releasePlan(tag,
        await fs.readFile(path.join(root, 'src/FujiPhotoRenamer.lrplugin/Info.lua'), 'utf8'),
        await fs.readFile(path.join(root, 'CHANGELOG.md'), 'utf8'));
    if (command === 'prepare') {
        await fs.mkdir(directory, { recursive: true });
        await fs.writeFile(path.join(directory, 'release-notes.md'), plan.notes, { flag: 'wx' });
    } else await verifyAssets(directory, plan);
    console.log(`${command}: ${plan.tag}`);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
