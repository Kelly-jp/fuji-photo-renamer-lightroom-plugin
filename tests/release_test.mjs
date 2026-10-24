import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { releasePlan, verifyAssets } from '../scripts/release.mjs';
import { sha256 } from '../scripts/packaging.mjs';

const info = 'VERSION = { major = 0, minor = 10, revision = 3, build = 27 }';
const changelog = '# Changelog\n\n## Unreleased\n\nFuture work.\n\n## [0.10.3] - 2026-10-24\n\n### Fixed\n\n- Release change.\n\n## 0.10.2\n\n- Older change.\n';
const plan = () => releasePlan('v0.10.3', info, changelog);

test('extracts only the selected release notes and generates the four exact asset names', () => {
    const result = plan();
    assert.equal(result.notes, '### Fixed\n\n- Release change.\n');
    assert.equal(result.version, '0.10.3');
    assert.deepEqual(result.assets, [
        'fuji-photo-renamer-lightroom-plugin-0.10.3-macos.zip',
        'fuji-photo-renamer-lightroom-plugin-0.10.3-macos.zip.sha256',
        'fuji-photo-renamer-lightroom-plugin-0.10.3-windows.zip',
        'fuji-photo-renamer-lightroom-plugin-0.10.3-windows.zip.sha256',
    ]);
});
test('accepts an unbracketed version section and CRLF', () => {
    assert.equal(releasePlan('v0.10.3', info, '## 0.10.3\r\n\r\nChanges.\r\n').notes, 'Changes.\n');
    assert.deepEqual(releasePlan('v0.10.3', info, changelog.replace(/\n/g, '\r\n')), plan());
});
for (const tag of ['v0.10.2', '0.10.3', 'v00.10.3', 'v0.10.3-beta', 'v0.10.3\n', 'v0.10.3; echo bad']) {
    test(`rejects a mismatched or unsafe tag: ${JSON.stringify(tag)}`, () => {
        assert.throws(() => releasePlan(tag, info, changelog));
    });
}
test('requires exactly one nonempty release section, not Unreleased', () => {
    for (const text of ['## Unreleased\nChanges.', '## 0.10.3\n\n## 0.10.2\nOld.',
        '## 0.10.3\nFirst.\n## [0.10.3]\nDuplicate.']) {
        assert.throws(() => releasePlan('v0.10.3', info, text));
    }
});

async function fixture(callback) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'fuji-release-test-'));
    try {
        for (const name of plan().assets.filter(name => name.endsWith('.zip'))) {
            const payload = Buffer.from(name);
            await fs.writeFile(path.join(directory, name), payload);
            await fs.writeFile(path.join(directory, `${name}.sha256`), `${sha256(payload)}  ${name}\n`);
        }
        await fs.writeFile(path.join(directory, 'release-notes.md'), plan().notes);
        await callback(directory);
    } finally { await fs.rm(directory, { recursive: true, force: true }); }
}
test('verifies a complete asset set', () => fixture(directory => verifyAssets(directory, plan())));
test('refuses a changed ZIP without changing its checksum', () => fixture(async directory => {
    await fs.writeFile(path.join(directory, plan().assets[0]), 'changed');
    await assert.rejects(verifyAssets(directory, plan()), /SHA-256/);
}));
test('refuses checksum files naming a different asset', () => fixture(async directory => {
    const checksum = path.join(directory, plan().assets[1]);
    await fs.writeFile(checksum, (await fs.readFile(checksum, 'utf8')).replace('-macos.zip', '-windows.zip'));
    await assert.rejects(verifyAssets(directory, plan()), /SHA-256/);
}));
test('refuses missing files', () => fixture(async directory => {
    await fs.unlink(path.join(directory, plan().assets[3]));
    await assert.rejects(verifyAssets(directory, plan()), /Missing/);
}));
test('refuses unintended files in the release upload directory', () => fixture(async directory => {
    await fs.writeFile(path.join(directory, 'private-photo.jpg'), 'not an asset');
    await assert.rejects(verifyAssets(directory, plan()), /unexpected/);
}));
test('refuses a directory instead of a file', () => fixture(async directory => {
    const name = path.join(directory, plan().assets[0]);
    await fs.unlink(name); await fs.mkdir(name);
    await assert.rejects(verifyAssets(directory, plan()), /regular files/);
}));
test('refuses altered release notes', () => fixture(async directory => {
    await fs.writeFile(path.join(directory, 'release-notes.md'), 'Not the tagged notes');
    await assert.rejects(verifyAssets(directory, plan()), /notes differ/);
}));
