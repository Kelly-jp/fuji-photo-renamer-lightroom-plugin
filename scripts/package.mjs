import * as fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { root, lock, parseOptions, targets, readPrepared, copyFile, copyTree, inventory, hashFile, run } from './packaging.mjs';
import { signMacRuntime } from './sign-macos.mjs';

export function runtimeFile(filename) {
    if (filename.split('/').some(part => part.startsWith('.'))) return false;
    const rootFiles = ['Info.lua', 'ExportServiceProvider.lua', 'ExifToolLoader.lua', 'dkjson.lua',
        'Phase2Diagnostic.lua', 'Phase2MetadataDiagnostic.lua', 'Phase3Diagnostic.lua', 'Phase4Diagnostic.lua'];
    return rootFiles.includes(filename) || /^(?:core|infrastructure|ui|lightroom)\/[^/]+\.lua$/.test(filename)
        || /^infrastructure\/ExifToolRead\.(?:sh|ps1)$/.test(filename)
        || filename === 'third_party/dependencies.json' || /^THIRD_PARTY_NOTICES\/[^/]+\.txt$/.test(filename);
}

export function pluginVersion(info) {
    const match = info.match(/VERSION\s*=\s*\{\s*major\s*=\s*(\d+),\s*minor\s*=\s*(\d+),\s*revision\s*=\s*(\d+),\s*build\s*=\s*(\d+)\s*\}/);
    if (!match) throw new Error('Cannot read the plugin version from Info.lua');
    return { version: match.slice(1, 4).join('.'), build: Number(match[4]) };
}

function notices(platform) {
    return `# Third-party notices

This plugin's own code is MIT licensed; see LICENSE. Bundled dependencies retain their own terms.

- dkjson 2.11: MIT. See THIRD_PARTY_NOTICES/dkjson-LICENSE.txt and third_party/dependencies.json.
- ExifTool ${lock.exiftoolVersion}, Copyright Phil Harvey: same terms as Perl (Artistic License or GPL). See THIRD_PARTY_NOTICES/ExifTool-README.txt and Perl-Artistic.txt / Perl-Copying.txt.
- Official ExifTool source: ${lock.sources.exiftool.url}
${platform === 'macos' ? `- Perl ${lock.perlVersion}: unmodified upstream source, compiled with relocatable library paths and a static libperl. Runtime module notices are retained; additional license texts are in vendor/macos/runtime/*/licenses.
- Perl source and original build instructions: ${lock.sources.perl.url}
- Build configuration and packaging source: https://github.com/Kelly-jp/fuji-photo-renamer-lightroom-plugin/tree/main/scripts
` : `- Windows runtime: the upstream 64-bit package's Strawberry Perl 5.32.1 and tiny launcher by Oliver Betz. See vendor/windows/exiftool_files/readme_windows.txt, LICENSE, and Licenses_Strawberry_Perl.zip for upstream notices and dependency terms. The upstream executable is renamed from exiftool(-k).exe to exiftool.exe; its bytes and the dependency directory are unchanged.
- Upstream Windows package: ${lock.sources.windows.url}
`}
The project license does not replace these notices. Source archive SHA-256 values are recorded in PACKAGE_MANIFEST.json. No Adobe SDK files are distributed.
`;
}

export async function packageTarget(platform, options) {
    const prepared = await readPrepared(platform);
    const source = path.join(root, 'src/FujiPhotoRenamer.lrplugin');
    const version = pluginVersion(await fs.readFile(path.join(source, 'Info.lua'), 'utf8'));
    const target = platform;
    const filename = `fuji-photo-renamer-lightroom-plugin-${version.version}-${target}.zip`;
    const dist = path.join(root, 'dist');
    await fs.mkdir(dist, { recursive: true });
    for (const name of [filename, `${filename}.sha256`]) {
        try { await fs.access(path.join(dist, name)); throw new Error(`Refusing to replace existing distribution: ${name}`); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    const build = path.join(root, 'build');
    await fs.mkdir(build, { recursive: true });
    const workspace = await fs.mkdtemp(path.join(build, 'package-'));
    const plugin = path.join(workspace, 'FujiPhotoRenamer.lrplugin');
    await fs.mkdir(plugin);
    try {
        for (const entry of await inventory(source)) {
            if (runtimeFile(entry.path)) await copyFile(path.join(source, entry.path), path.join(plugin, entry.path));
        }
        const dependency = JSON.parse(await fs.readFile(path.join(plugin, 'third_party/dependencies.json'), 'utf8')).dkjson;
        if (await hashFile(path.join(plugin, 'dkjson.lua')) !== dependency.sha256) throw new Error('dkjson differs from its pinned upstream source');
        await copyTree(path.join(prepared.directory, 'payload'), plugin);
        // Sign only staging copies; preserve the verified preparation cache's original hashes.
        const macosSigning = platform === 'macos' ? await signMacRuntime(plugin) : null;
        await copyFile(path.join(root, 'LICENSE'), path.join(plugin, 'LICENSE'));
        await fs.writeFile(path.join(plugin, 'THIRD_PARTY_NOTICES.md'), notices(platform));
        await fs.writeFile(path.join(plugin, 'INSTALL.md'), `# インストールと検証

1. ZIPを解凍し、FujiPhotoRenamer.lrpluginを任意の場所へ置きます。
2. Lightroom Classicの「ファイル → プラグインマネージャー → 追加」でこのフォルダーを選びます。
3. 書き出し先「Fuji Photo Renamer — 開発検証版」を選択します。
4. ExifToolのパス欄を空欄にします。以前のプリセットに外部ツールのパスが残っている場合も消してください。
5. テンプレートと保存先を設定し、複製した素材で書き出しを確認します。

対象CPU: ${platform === 'windows' ? 'Windows x64（実機未検証）' : 'macOS Apple Siliconのみ（Intel Macは対象外）'}。
この配布物は開発検証版です。${platform === 'macos' ? '同梱Perlとネイティブモジュールにはad-hoc署名を付けています。Developer ID署名・Appleの公証はなく、Gatekeeperによる個別許可が必要になる場合があります。' : 'Windows実機での起動は未検証です。'}
クリーン環境とLightroomでの同梱起動には追加確認が必要です。
ExifTool ${lock.exiftoolVersion}と実行依存を同梱しています。ユーザーによるPerl / ExifToolの追加インストールは不要です。
元画像と既存出力の前後ハッシュ確認を行ってください。C2PA削除は既定OFFです。
詳細: https://github.com/Kelly-jp/fuji-photo-renamer-lightroom-plugin
`);
        const files = await inventory(plugin);
        const manifest = { schemaVersion: 1, ...version, platform, arch: prepared.manifest.arch,
            exiftoolVersion: lock.exiftoolVersion, perlVersion: prepared.manifest.perlVersion,
            lockHash: prepared.manifest.lockHash, sources: prepared.manifest.sources, macosSigning, files };
        await fs.writeFile(path.join(plugin, 'PACKAGE_MANIFEST.json'), JSON.stringify(manifest, null, 2) + '\n');
        const archive = path.join(workspace, filename);
        await run(options.python, [path.join(root, 'scripts/archive.py'), 'zip', plugin, archive]);
        const digest = await hashFile(archive);
        const checksum = path.join(workspace, `${filename}.sha256`);
        await fs.writeFile(checksum, `${digest}  ${filename}\n`);
        await fs.link(archive, path.join(dist, filename));
        await fs.link(checksum, path.join(dist, `${filename}.sha256`));
        await fs.rm(workspace, { recursive: true });
        console.log(`Packaged: dist/${filename}\nSHA-256: ${digest}`);
        return path.join(dist, filename);
    } catch (error) {
        throw new Error(`${error.message}\nUnpublished build retained for inspection: ${workspace}`);
    }
}

async function main() {
    const options = parseOptions(process.argv.slice(2));
    if (options.help) {
        console.log('node scripts/package.mjs --platform macos|windows|all [--python python3]');
        return;
    }
    for (const platform of targets(options)) await packageTarget(platform, options);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
