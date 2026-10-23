import * as fs from 'node:fs/promises';
import path from 'node:path';
import { inventory, run } from './packaging.mjs';

const machOMagic = new Set(['feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']);

export async function isMachO(filename) {
    const handle = await fs.open(filename, 'r');
    try {
        const bytes = Buffer.alloc(4);
        const { bytesRead } = await handle.read(bytes, 0, 4, 0);
        return bytesRead === 4 && machOMagic.has(bytes.toString('hex'));
    } finally { await handle.close(); }
}

export async function signMacRuntime(plugin) {
    if (process.platform !== 'darwin') throw new Error('macOS ad-hoc signing requires macOS');
    const relative = 'vendor/macos/runtime/arm64';
    const runtime = path.join(plugin, relative);
    const actualPlugin = await fs.realpath(plugin);
    if (!(await fs.lstat(runtime)).isDirectory() || await fs.realpath(runtime) !== path.join(actualPlugin, relative)) {
        throw new Error('Signing runtime must be inside the staged plugin without aliases');
    }
    const files = [];
    for (const entry of await inventory(runtime)) {
        if (await isMachO(path.join(runtime, entry.path))) files.push(`${relative}/${entry.path}`);
    }
    const interpreter = `${relative}/bin/perl`;
    if (!files.includes(interpreter)) throw new Error('No Mach-O Perl interpreter to sign');
    // Sign each native module individually; .lrplugin is not a standard macOS code bundle.
    files.sort((a, b) => (a === interpreter ? 1 : b === interpreter ? -1 : a.localeCompare(b, 'en')));
    for (const filename of files) {
        const identifier = 'jp.kelly.fuji-photo-renamer.' + filename.slice(relative.length + 1).replace(/[^a-zA-Z0-9.-]/g, '_');
        await run('/usr/bin/codesign', ['--force', '--sign', '-', '--timestamp=none', '--identifier', identifier, path.join(plugin, filename)]);
        await run('/usr/bin/codesign', ['--verify', '--strict', '--verbose=2', path.join(plugin, filename)]);
    }
    return { type: 'ad-hoc', identity: '-', notarized: false, files };
}
