import * as fs from 'node:fs/promises';
import { openSync, closeSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { root, lock, lockHash, parseOptions, targets, preparedPath, readPrepared,
    download, run, copyFile, copyTree, inventory } from './packaging.mjs';

export const macLauncher = `#!/bin/sh
set -eu
PATH=/usr/bin:/bin
export PATH
unset PERL5LIB PERLLIB PERL5OPT PERL_LOCAL_LIB_ROOT PERL_MB_OPT PERL_MM_OPT
base=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
case $(/usr/bin/uname -m) in
    arm64) ;;
    *) printf '%s\\n' 'Bundled ExifTool requires an Apple Silicon Mac' >&2; exit 1 ;;
esac
if [ ! -x "$base/runtime/arm64/bin/perl" ]; then
    printf '%s\\n' 'Bundled Perl is missing for arm64' >&2
    exit 1
fi
exec "$base/runtime/arm64/bin/perl" "$base/tool/exiftool" "$@"
`;

async function extract(archive, destination, options) {
    await run(options.python, [path.join(root, 'scripts/archive.py'), 'extract', archive, destination]);
}

function buildEnvironment() {
    const environment = { ...process.env, PATH: '/usr/bin:/bin:/usr/sbin:/sbin', LC_ALL: 'C' };
    for (const key of Object.keys(environment)) {
        if (key.startsWith('PERL') || key.startsWith('DYLD_') || ['CPATH', 'LIBRARY_PATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH'].includes(key)) delete environment[key];
    }
    return environment;
}

async function buildPerl(archive, destination, options) {
    const arch = 'arm64';
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), `fuji-perl-${arch}-`));
    const logs = path.join(root, 'build/perl-logs', arch);
    await fs.mkdir(logs, { recursive: true });
    const source = path.join(workspace, `source/perl-${lock.perlVersion}`);
    const prefix = path.join(workspace, 'installed');
    await extract(archive, path.join(workspace, 'source'), options);
    const compilerArch = 'arm64';
    const flags = `-arch ${compilerArch} -mmacosx-version-min=11.0`;
    const env = buildEnvironment();
    env.SDKROOT = await run('/usr/bin/xcrun', ['--show-sdk-path'], { env });
    env.MACOSX_DEPLOYMENT_TARGET = '11.0';
    const compiler = await run('/usr/bin/xcrun', ['--find', 'clang'], { env });
    async function step(name, command, args) {
        console.log(`Perl ${arch}: ${name} (log: build/perl-logs/${arch}/${name}.log)`);
        const descriptor = openSync(path.join(logs, `${name}.log`), 'w');
        try { await run(command, args, { cwd: source, env, log: descriptor, timeout: 1800000 }); }
        catch (error) { throw new Error(`${error.message}; see ${logs}/${name}.log. Build retained: ${workspace}`); }
        finally { closeSync(descriptor); }
    }
    await step('configure', '/bin/sh', ['Configure', '-des', `-Dprefix=${prefix}`, '-Duserelocatableinc',
        '-Uuseshrplib', '-Dman1dir=none', '-Dman3dir=none', `-Dcc=${compiler}`,
        `-Dccflags=${flags} -DHAS_BROKEN_LANGINFO_CODESET`, `-Dldflags=${flags}`, '-Dotherlibdirs=', '-Doptimize=-O2']);
    await step('build', '/usr/bin/make', [`-j${options.jobs}`]);
    await step('test', '/usr/bin/make', ['test_harness', `TEST_JOBS=${options.jobs}`]);
    await step('install', '/usr/bin/make', ['install']);
    await finishPerlRuntime(prefix, source, destination, env);
    // This directory was created by mkdtemp and contains only this preparation's build.
    await fs.rm(workspace, { recursive: true });
}

export async function copyPerlLicenses(source, licenses) {
    for (const name of ['Artistic', 'Copying', 'README', 'INSTALL']) {
        if (!(await fs.lstat(path.join(source, name))).isFile()) throw new Error(`Non-regular license: ${name}`);
        await copyFile(path.join(source, name), path.join(licenses, name));
    }
    async function moduleLicenses(folder) {
        for (const entry of await fs.readdir(folder, { withFileTypes: true })) {
            const filename = path.join(folder, entry.name);
            if (entry.isDirectory()) await moduleLicenses(filename);
            else if (/^(?:LICENSE(?:\.[^/]*)?|COPYING(?:\.[^/]*)?|LICENCE(?:\.[^/]*)?)$/i.test(entry.name)) {
                if (!entry.isFile()) throw new Error(`Non-regular license: ${filename}`);
                await copyFile(filename, path.join(licenses, 'modules', path.relative(source, filename)));
            }
        }
    }
    await moduleLicenses(source);
}

export async function finishPerlRuntime(prefix, source, destination, env = buildEnvironment()) {
    // Only the interpreter and its standard libraries are runtime dependencies.
    await copyFile(path.join(prefix, 'bin/perl'), path.join(destination, 'bin/perl'));
    await copyTree(path.join(prefix, 'lib'), path.join(destination, 'lib'));
    await copyPerlLicenses(source, path.join(destination, 'licenses'));
    // Test relocated @INC while the original install prefix still exists; every search path must point into this copy.
    const perl = path.join(destination, 'bin/perl');
    const version = await run(perl, ['-e', 'print $^V'], { env });
    if (version !== `v${lock.perlVersion}`) throw new Error(`Unexpected Perl version: ${version}`);
    const inc = await run(perl, ['-e', 'print join("\\n", @INC)'], { env });
    if (inc.split('\n').some(item => !path.resolve(item).startsWith(path.resolve(destination) + path.sep))) {
        throw new Error(`Perl @INC is not self-contained: ${inc}`);
    }
    const format = await run('/usr/bin/file', ['-b', perl]);
    if (!format.includes('arm64')) throw new Error(`Wrong Perl architecture: ${format}`);
    for (const entry of await inventory(destination)) {
        if (entry.path === 'bin/perl' || /\.(?:bundle|dylib)$/.test(entry.path)) {
            const dependencies = await run('/usr/bin/otool', ['-L', path.join(destination, entry.path)]);
            for (const line of dependencies.split('\n').slice(1)) {
                const library = line.trim().split(' (')[0];
                if (library && !library.startsWith('/usr/lib/') && !library.startsWith('/System/Library/')) {
                    throw new Error(`External dynamic library: ${library}`);
                }
            }
        }
    }
}

export async function prepare(platform, options) {
    const arch = platform === 'windows' ? 'x64' : 'arm64';
    const destination = preparedPath(platform);
    try {
        const existing = await readPrepared(platform);
        console.log(`Verified prepared payload: ${destination}`);
        return existing;
    } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        try { await fs.access(destination); throw new Error(`Incomplete payload exists; inspect and remove it before retrying: ${destination}`); }
        catch (existsError) { if (existsError.code !== 'ENOENT') throw existsError; }
    }
    if (platform === 'macos') {
        if (process.platform !== 'darwin' || process.arch !== 'arm64') throw new Error('Build the macOS Perl runtime on an Apple Silicon Mac');
    }
    const exiftoolArchive = await download(lock.sources.exiftool, options.offline);
    const perlArchive = await download(lock.sources.perl, options.offline);
    const windowsArchive = platform === 'windows' ? await download(lock.sources.windows, options.offline) : null;
    const parent = path.dirname(destination);
    await fs.mkdir(parent, { recursive: true });
    const workspace = await fs.mkdtemp(path.join(parent, '.preparing-'));
    const payload = path.join(workspace, 'payload');
    const vendor = path.join(payload, 'vendor', platform);
    try {
        await extract(exiftoolArchive, path.join(workspace, 'exiftool-source'), options);
        await extract(perlArchive, path.join(workspace, 'perl-source'), options);
        const source = path.join(workspace, 'exiftool-source', `Image-ExifTool-${lock.exiftoolVersion}`);
        const perlSource = path.join(workspace, 'perl-source', `perl-${lock.perlVersion}`);
        const notices = path.join(payload, 'THIRD_PARTY_NOTICES');
        await copyFile(path.join(source, 'README'), path.join(notices, 'ExifTool-README.txt'));
        await copyFile(path.join(perlSource, 'Artistic'), path.join(notices, 'Perl-Artistic.txt'));
        await copyFile(path.join(perlSource, 'Copying'), path.join(notices, 'Perl-Copying.txt'));
        if (platform === 'windows') {
            await extract(windowsArchive, path.join(workspace, 'windows'), options);
            const original = path.join(workspace, 'windows', `exiftool-${lock.exiftoolVersion}_64`);
            await copyFile(path.join(original, 'exiftool(-k).exe'), path.join(vendor, 'exiftool.exe'));
            await copyTree(path.join(original, 'exiftool_files'), path.join(vendor, 'exiftool_files'));
            await copyFile(path.join(original, 'README.txt'), path.join(notices, 'ExifTool-Windows-README.txt'));
            for (const required of ['LICENSE', 'Licenses_Strawberry_Perl.zip', 'readme_windows.txt']) {
                await fs.access(path.join(vendor, 'exiftool_files', required));
            }
        } else {
            await copyFile(path.join(source, 'exiftool'), path.join(vendor, 'tool/exiftool'));
            await copyTree(path.join(source, 'lib'), path.join(vendor, 'tool/lib'));
            await buildPerl(perlArchive, path.join(vendor, 'runtime/arm64'), options);
            await fs.writeFile(path.join(vendor, 'exiftool'), macLauncher, { mode: 0o755, flag: 'wx' });
            const version = await run(path.join(vendor, 'exiftool'), ['-config', '', '-ver'], { env: buildEnvironment() });
            if (version !== lock.exiftoolVersion) throw new Error(`Unexpected bundled ExifTool: ${version}`);
        }
        const manifest = { schemaVersion: 1, platform, arch, exiftoolVersion: lock.exiftoolVersion,
            perlVersion: platform === 'macos' ? lock.perlVersion : '5.32.1 (upstream Windows package)',
            lockHash, sources: lock.sources, files: await inventory(payload) };
        await fs.writeFile(path.join(workspace, 'prepared.json'), JSON.stringify(manifest, null, 2) + '\n');
        // The published cache contains runtime files only, not extraction or build trees.
        await fs.rm(path.join(workspace, 'exiftool-source'), { recursive: true });
        await fs.rm(path.join(workspace, 'perl-source'), { recursive: true });
        if (windowsArchive) await fs.rm(path.join(workspace, 'windows'), { recursive: true });
        await fs.rename(workspace, destination);
        console.log(`Prepared: ${destination}`);
        return readPrepared(platform);
    } catch (error) {
        throw new Error(`${error.message}\nUnpublished preparation retained for inspection: ${workspace}`);
    }
}

async function main() {
    const options = parseOptions(process.argv.slice(2));
    if (options.help) {
        console.log('node scripts/prepare-exiftool.mjs --platform macos|windows|all [--offline] [--python python3] [--jobs 8]');
        return;
    }
    for (const platform of targets(options)) await prepare(platform, options);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
