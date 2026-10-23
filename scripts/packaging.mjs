import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createReadStream } from 'node:fs';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const lockPath = path.join(root, 'scripts/exiftool-lock.json');
export const lock = JSON.parse(await fs.readFile(lockPath, 'utf8'));
export const sha256 = data => createHash('sha256').update(data).digest('hex');
export const lockHash = sha256(await fs.readFile(lockPath));

export async function hashFile(filename) {
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(filename)) hash.update(chunk);
    return hash.digest('hex');
}

export function run(command, args, options = {}) {
    return new Promise((resolve, reject) => {
        const { log, timeout = 180000, ...spawnOptions } = options;
        const child = spawn(command, args, { cwd: root, stdio: log ? ['ignore', log, log] : 'pipe', ...spawnOptions });
        child.stdin?.end();
        const timer = setTimeout(() => child.kill('SIGTERM'), timeout);
        timer.unref();
        let stdout = '', stderr = '';
        child.stdout?.on('data', data => { stdout += data; });
        child.stderr?.on('data', data => { stderr += data; });
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            if (code !== 0) reject(new Error(`${command} failed (${signal ?? code}): ${stderr.slice(-4000)}`));
            else resolve(stdout.trim());
        });
    });
}

export function parseOptions(argv) {
    const result = { platform: process.platform === 'darwin' ? 'macos' : 'windows',
        python: 'python3', offline: false, jobs: 8 };
    for (let index = 0; index < argv.length; index++) {
        const flag = argv[index];
        if (flag === '--offline') result.offline = true;
        else if (flag === '--help') result.help = true;
        else if (['--platform', '--python', '--jobs'].includes(flag) && argv[index + 1] && !argv[index + 1].startsWith('--')) {
            result[flag.slice(2)] = argv[++index];
        } else throw new Error(`Unknown or incomplete option: ${flag}`);
    }
    if (!['macos', 'windows', 'all'].includes(result.platform)) throw new Error('Use --platform macos, windows or all');
    result.jobs = Number(result.jobs);
    if (!Number.isInteger(result.jobs) || result.jobs < 1 || result.jobs > 16) throw new Error('--jobs must be between 1 and 16');
    return result;
}

export function preparedPath(platform) {
    return path.join(root, '.cache/prepared-exiftool', platform === 'macos' ? 'macos-arm64' : 'windows-x64');
}

export async function inventory(directory) {
    const files = [];
    async function walk(folder) {
        for (const entry of (await fs.readdir(folder, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name, 'en'))) {
            const filename = path.join(folder, entry.name);
            if (entry.isSymbolicLink()) throw new Error(`Symlink not allowed: ${filename}`);
            if (entry.isDirectory()) await walk(filename);
            else if (entry.isFile()) {
                const relative = path.relative(directory, filename).split(path.sep).join('/');
                if (relative.includes('\n') || relative.includes('\r')) throw new Error('Control characters in package path');
                files.push({ path: relative, sha256: await hashFile(filename), executable: Boolean((await fs.stat(filename)).mode & 0o111) });
            } else throw new Error(`Non-regular file: ${filename}`);
        }
    }
    await walk(directory);
    return files;
}

export async function verifyInventory(directory, expected) {
    const actual = await inventory(directory);
    if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Prepared files changed or are incomplete: ${directory}`);
}

export async function download(source, offline, directory = path.join(root, '.cache/downloads')) {
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(source.filename) || !/^[a-f0-9]{64}$/.test(source.sha256)
        || !source.url.startsWith('https://')) throw new Error('Invalid pinned archive source');
    await fs.mkdir(directory, { recursive: true });
    const filename = path.join(directory, source.filename);
    try {
        if (await hashFile(filename) !== source.sha256) throw new Error(`SHA-256 mismatch: ${source.filename}`);
        return filename;
    } catch (error) {
        if (error.code !== 'ENOENT') throw error;
    }
    if (offline) throw new Error(`Offline archive missing: ${source.filename}`);
    const temporary = `${filename}.${process.pid}.partial`;
    let handle;
    try {
        const response = await fetch(source.url, { signal: AbortSignal.timeout(120000) });
        if (!response.ok || !response.body) throw new Error(`Download failed: ${response.status} ${source.url}`);
        handle = await fs.open(temporary, 'wx');
        await pipeline(Readable.fromWeb(response.body), handle.createWriteStream());
        if (await hashFile(temporary) !== source.sha256) throw new Error(`SHA-256 mismatch: ${source.filename}`);
        // Publish without replacing any pre-existing archive from another preparation.
        await fs.link(temporary, filename);
        return filename;
    } finally {
        if (handle) {
            await handle.close();
            await fs.rm(temporary, { force: true });
        }
    }
}

export async function copyFile(source, destination) {
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.copyFile(source, destination);
    await fs.chmod(destination, (await fs.stat(source)).mode & 0o111 ? 0o755 : 0o644);
}

export async function copyTree(source, destination) {
    const entries = await inventory(source);
    for (const entry of entries) await copyFile(path.join(source, entry.path), path.join(destination, entry.path));
}

export async function readPrepared(platform) {
    const directory = preparedPath(platform);
    const manifest = JSON.parse(await fs.readFile(path.join(directory, 'prepared.json'), 'utf8'));
    if (manifest.lockHash !== lockHash || manifest.platform !== platform || manifest.arch !== (platform === 'windows' ? 'x64' : 'arm64')
        || manifest.exiftoolVersion !== lock.exiftoolVersion) {
        throw new Error('Prepared payload uses another lock or target; run prepare-exiftool.mjs');
    }
    await verifyInventory(path.join(directory, 'payload'), manifest.files);
    const required = ['THIRD_PARTY_NOTICES/ExifTool-README.txt', 'THIRD_PARTY_NOTICES/Perl-Artistic.txt',
        'THIRD_PARTY_NOTICES/Perl-Copying.txt'];
    if (platform === 'windows') required.push('vendor/windows/exiftool.exe', 'vendor/windows/exiftool_files/LICENSE',
        'vendor/windows/exiftool_files/Licenses_Strawberry_Perl.zip', 'vendor/windows/exiftool_files/lib/Config.pm');
    else {
        required.push('vendor/macos/exiftool', 'vendor/macos/tool/exiftool');
        required.push('vendor/macos/runtime/arm64/bin/perl');
    }
    for (const filename of required) if (!manifest.files.some(file => file.path === filename)) throw new Error(`Prepared dependency missing: ${filename}`);
    return { directory, manifest };
}

export function targets(options) {
    return options.platform === 'all' ? ['windows', 'macos'] : [options.platform];
}
