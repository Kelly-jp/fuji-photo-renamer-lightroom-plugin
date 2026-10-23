import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { download, inventory, verifyInventory, parseOptions, sha256, run } from '../scripts/packaging.mjs';
import { runtimeFile, pluginVersion } from '../scripts/package.mjs';
import { macLauncher, copyPerlLicenses } from '../scripts/prepare-exiftool.mjs';
import { isMachO, signMacRuntime } from '../scripts/sign-macos.mjs';

async function temporary(callback) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'fuji-packaging-test-'));
    try { await callback(directory); }
    finally { await fs.rm(directory, { recursive: true, force: true }); }
}
const payload = Buffer.from('verified archive fixture');
const source = { filename: 'fixture.tar.gz', url: 'https://example.invalid/fixture.tar.gz', sha256: sha256(payload) };

test('cache reuse verifies SHA-256 without making a network request', () => temporary(async directory => {
    await fs.writeFile(path.join(directory, source.filename), payload);
    const oldFetch = globalThis.fetch;
    globalThis.fetch = () => { throw new Error('Unexpected download'); };
    try { assert.equal(await download(source, false, directory), path.join(directory, source.filename)); }
    finally { globalThis.fetch = oldFetch; }
}));
test('rejects changed cache contents instead of downloading over them', () => temporary(async directory => {
    await fs.writeFile(path.join(directory, source.filename), 'changed');
    await assert.rejects(download(source, false, directory), /SHA-256 mismatch/);
    assert.equal(await fs.readFile(path.join(directory, source.filename), 'utf8'), 'changed');
}));
test('offline preparation refuses a missing archive', () => temporary(async directory => {
    await assert.rejects(download(source, true, directory), /Offline archive missing/);
}));
test('downloaded bytes must match the pinned hash before publishing', () => temporary(async directory => {
    const oldFetch = globalThis.fetch; globalThis.fetch = async () => new Response('wrong bytes');
    try {
        await assert.rejects(download(source, false, directory), /SHA-256 mismatch/);
        assert.deepEqual(await fs.readdir(directory), []);
    } finally { globalThis.fetch = oldFetch; }
}));
test('verified download publishes the original byte sequence', () => temporary(async directory => {
    const oldFetch = globalThis.fetch; globalThis.fetch = async () => new Response(payload);
    try { assert.deepEqual(await fs.readFile(await download(source, false, directory)), payload); }
    finally { globalThis.fetch = oldFetch; }
}));
test('an existing partial file is refused and never removed by cleanup', () => temporary(async directory => {
    const partial = path.join(directory, `${source.filename}.${process.pid}.partial`);
    await fs.writeFile(partial, 'existing partial');
    const oldFetch = globalThis.fetch; globalThis.fetch = async () => new Response(payload);
    try {
        await assert.rejects(download(source, false, directory), error => error.code === 'EEXIST');
        assert.equal(await fs.readFile(partial, 'utf8'), 'existing partial');
    } finally { globalThis.fetch = oldFetch; }
}));
test('HTTP failure is an error and does not create a cache artifact', () => temporary(async directory => {
    const oldFetch = globalThis.fetch; globalThis.fetch = async () => new Response('not found', { status: 404 });
    try { await assert.rejects(download(source, false, directory), /Download failed/); assert.deepEqual(await fs.readdir(directory), []); }
    finally { globalThis.fetch = oldFetch; }
}));
test('archive source rejects traversal and invalid hash or protocol', () => temporary(async directory => {
    for (const entry of [{ ...source, filename: '../escape' }, { ...source, sha256: 'bad' }, { ...source, url: 'http://example.invalid' }]) {
        await assert.rejects(download(entry, true, directory), /Invalid pinned archive source/);
    }
}));
test('prepared inventory detects changes, missing files and unexpected extra files', () => temporary(async directory => {
    await fs.writeFile(path.join(directory, 'runtime'), 'original');
    const expected = await inventory(directory); await verifyInventory(directory, expected);
    await fs.writeFile(path.join(directory, 'runtime'), 'changed'); await assert.rejects(verifyInventory(directory, expected), /changed/);
    await fs.unlink(path.join(directory, 'runtime')); await assert.rejects(verifyInventory(directory, expected), /incomplete/);
    await fs.writeFile(path.join(directory, 'runtime'), 'original'); await fs.writeFile(path.join(directory, 'extra'), 'unexpected');
    await assert.rejects(verifyInventory(directory, expected), /changed/);
}));
test('prepared inventory refuses symlinks', () => temporary(async directory => {
    await fs.writeFile(path.join(directory, 'original'), 'data');
    await fs.symlink('original', path.join(directory, 'alias')); await assert.rejects(inventory(directory), /Symlink/);
}));
test('Perl license collection ignores generated source links but preserves original notices', () => temporary(async directory => {
    const source = path.join(directory, 'source'), destination = path.join(directory, 'licenses');
    await fs.mkdir(path.join(source, 'cpan/Foo'), { recursive: true });
    for (const name of ['Artistic', 'Copying', 'README', 'INSTALL']) await fs.writeFile(path.join(source, name), name + ' original');
    await fs.writeFile(path.join(source, 'cpan/Foo/LICENSE'), 'module license original');
    await fs.symlink('README', path.join(source, 'opmini.c'));
    await copyPerlLicenses(source, destination);
    assert.equal(await fs.readFile(path.join(destination, 'modules/cpan/Foo/LICENSE'), 'utf8'), 'module license original');
    assert.equal(await fs.readFile(path.join(destination, 'Artistic'), 'utf8'), 'Artistic original');
    await fs.symlink('../../README', path.join(source, 'cpan/Foo/COPYING'));
    await assert.rejects(copyPerlLicenses(source, destination), /Non-regular license/);
}));
test('runtime allowlist excludes tests, private fixtures, hidden files and preexisting vendor payloads', () => {
    for (const name of ['Info.lua', 'core/TokenResolver.lua', 'infrastructure/ExifToolRead.sh', 'third_party/dependencies.json', 'THIRD_PARTY_NOTICES/dkjson-LICENSE.txt']) assert.equal(runtimeFile(name), true);
    for (const name of ['tests/private.lua', 'fixtures/private/photo.jpg', 'core/.private.lua', '../secret.lua', 'vendor/macos/exiftool', '.DS_Store', 'README.md', 'core/test.lua.bak']) assert.equal(runtimeFile(name), false);
});
test('plugin version is taken from Info.lua and invalid declarations fail', () => {
    assert.deepEqual(pluginVersion('VERSION = { major = 0, minor = 9, revision = 1, build = 22 }'), { version: '0.9.1', build: 22 });
    assert.throws(() => pluginVersion('VERSION = {}'), /Cannot read/);
});
test('invalid target, architecture, build parallelism and incomplete options fail', () => {
    for (const args of [['--platform', 'linux'], ['--arch', 'other'], ['--arch', 'x64'], ['--arch', 'universal'], ['--jobs', '0'], ['--jobs', '17'], ['--platform'], ['--unknown']]) assert.throws(() => parseOptions(args));
    assert.equal(parseOptions(['--platform', 'all', '--offline']).offline, true);
});
test('macOS launcher rejects Intel rather than falling back to a system interpreter', () => {
    assert.match(macLauncher, /requires an Apple Silicon Mac/);
    assert.doesNotMatch(macLauncher, /x86_64|runtime\/x64|\/usr\/bin\/perl/);
});
test('subprocess failure cannot be mistaken for success', async () => {
    await assert.rejects(run(process.execPath, ['-e', 'process.exit(7)']), /failed \(7\)/);
    await assert.rejects(run('/nonexistent/fuji-tool', []), /ENOENT/);
});
test('macOS launcher uses the bundled interpreter, keeps paths as arguments and ignores external Perl settings', () => temporary(async directory => {
    const folder = path.join(directory, "日本語 plugin's folder");
    const arch = process.arch === 'arm64' ? 'arm64' : 'x64';
    await fs.mkdir(path.join(folder, 'runtime', arch, 'bin'), { recursive: true });
    await fs.writeFile(path.join(folder, 'exiftool'), macLauncher, { mode: 0o755 });
    await fs.writeFile(path.join(folder, 'runtime', arch, 'bin/perl'), '#!/bin/sh\n[ -z "${PERL5OPT-}" ] || exit 7\nprintf "%s\\n" "$@"\n', { mode: 0o755 });
    const filename = "photo's name;$(not-a-command).jpg";
    const output = await run(path.join(folder, 'exiftool'), [filename], { env: { ...process.env, PERL5OPT: '-MNonexistentModule', PERL5LIB: '/nonexistent/lib' } });
    assert.deepEqual(output.split('\n'), [path.join(await fs.realpath(folder), 'tool/exiftool'), filename]);
}));
test('Mach-O detection uses the file header instead of suffixes', () => temporary(async directory => {
    const file = path.join(directory, 'library.bundle');
    await fs.writeFile(file, 'not native code'); assert.equal(await isMachO(file), false);
    await fs.writeFile(file, Buffer.from('cffaedfe', 'hex')); assert.equal(await isMachO(file), true);
    await fs.writeFile(file, ''); assert.equal(await isMachO(file), false);
}));
test('ad-hoc signing covers native modules and Perl and detects later modification', () => temporary(async directory => {
    const plugin = path.join(directory, "日本語 signed plugin's folder");
    const runtime = path.join(plugin, 'vendor/macos/runtime/arm64');
    await fs.mkdir(path.join(runtime, 'bin'), { recursive: true });
    await fs.mkdir(path.join(runtime, 'lib'), { recursive: true });
    const source = path.join(directory, 'sample.c');
    await fs.writeFile(source, 'int main(void) { return 0; }\n');
    const compiler = await run('/usr/bin/xcrun', ['--find', 'clang']);
    const env = { ...process.env, SDKROOT: await run('/usr/bin/xcrun', ['--show-sdk-path']) };
    await run(compiler, [source, '-o', path.join(runtime, 'bin/perl')], { env });
    await run(compiler, ['-bundle', source, '-o', path.join(runtime, 'lib/module.native')], { env });
    await fs.writeFile(path.join(runtime, 'lib/notes.txt'), 'data remains unchanged');
    const signed = await signMacRuntime(plugin);
    assert.equal(signed.type, 'ad-hoc'); assert.equal(signed.notarized, false);
    assert.deepEqual(signed.files, ['vendor/macos/runtime/arm64/lib/module.native', 'vendor/macos/runtime/arm64/bin/perl']);
    assert.equal(await fs.readFile(path.join(runtime, 'lib/notes.txt'), 'utf8'), 'data remains unchanged');
    const file = await fs.open(path.join(runtime, 'bin/perl'), 'r+');
    try {
        const byte = Buffer.alloc(1); await file.read(byte, 0, 1, 1024);
        byte[0] ^= 1; await file.write(byte, 0, 1, 1024);
    } finally { await file.close(); }
    await assert.rejects(run('/usr/bin/codesign', ['--verify', '--strict', path.join(runtime, 'bin/perl')]), /failed/);
}));
test('signing refuses missing interpreters and aliases outside staging', () => temporary(async directory => {
    const plugin = path.join(directory, 'plugin'), runtime = path.join(plugin, 'vendor/macos/runtime/arm64');
    await fs.mkdir(runtime, { recursive: true });
    await assert.rejects(signMacRuntime(plugin), /No Mach-O Perl/);
    await fs.rmdir(runtime); await fs.mkdir(path.join(directory, 'external'));
    await fs.symlink(path.join(directory, 'external'), runtime);
    await assert.rejects(signMacRuntime(plugin), /inside the staged plugin/);
}));
