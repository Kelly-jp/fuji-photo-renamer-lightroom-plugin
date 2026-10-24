# 開発ガイド

基本的な機能と配布ZIPのビルド方法は[README](../README.md)を参照してください。開発前に[要件](requirements.md)、[アーキテクチャ](architecture.md)、[技術検証項目](testing.md#技術検証項目)と[AGENTS.md](../AGENTS.md)を確認します。

## 開発用プラグインの読み込み

Lightroom Classicのプラグインマネージャーで`src/FujiPhotoRenamer.lrplugin/`を追加します。ソースにはExifToolのバイナリを含めないため、書き出し設定で開発用ExifToolの絶対パスを指定します。PATHからの自動探索はしません。同梱環境を検証する場合は、ビルドしたZIPを解凍して登録し、ExifToolパスを空欄にします。

更新後はプラグインマネージャーで再読み込みし、書き出し画面を開き直してください。登録パスと表示バージョンは`Info.lua`に一致させます。診断機能は「ファイル（またはライブラリ）→ プラグインエクストラ → メタデータ取得 / 入力ファイル探索を検証…」から利用できます。診断の契約やSDK出典は[文書一覧](README.md)の各Phase記録を参照してください。

## テスト一式の実行

Python 3、Lua / luac 5.1 を用意します。外部Pythonパッケージは不要です。macOSで実ExifToolも含める場合は、リポジトリのルートで次を実行します。

```sh
python3 scripts/run-tests.py --exiftool /absolute/path/to/exiftool
python3 tests/run_tests_test.py
```

LuaがPATH上にない場合は `--lua /absolute/path/to/lua --luac /absolute/path/to/luac` を指定します。ExifTool不要の純coreだけは `--suite core`、SDK境界だけは `--suite sdk`、macOSの実ExifTool連携だけは `--suite native --exiftool /absolute/path/to/exiftool` で実行できます。SDK境界テストはLightroom実機テストではありません。

`--shuffle-seed 11` で実行順を再現可能に入れ替えます。各ファイルは別プロセスで動き、失敗・時間超過・成功要約の欠落は非ゼロ終了になります。既定の各プロセス上限は180秒です。個人写真は自動探索せず、必須スイートは合成素材だけを使います。許諾済み実写真の任意確認は従来の個別コマンドで行います。

## 個別のLuaテスト

プラグインは Lightroom 内で実行します。配布ZIPは既存スクリプトで生成します。Lintの自動化はありません。Lua 5.1 の実行環境を用意した場合、リポジトリのルートで以下を実行できます（Lua 本体は配布物に同梱しません）。

```sh
lua -v
luac -p src/FujiPhotoRenamer.lrplugin/Info.lua src/FujiPhotoRenamer.lrplugin/ExportServiceProvider.lua
lua tests/core/jpeg_integrity_test.lua
lua tests/integration/export_artifact_test.lua
lua tests/integration/metadata_reader_test.lua
lua tests/integration/c2pa_native_test.lua /absolute/path/to/exiftool
lua tests/integration/export_pipeline_test.lua
lua tests/integration/export_preview_test.lua
lua tests/integration/export_pipeline_native_test.lua /absolute/path/to/exiftool
lua tests/integration/export_dialog_test.lua
lua tests/integration/phase1_provider_test.lua
lua tests/core/filename_safety_test.lua
lua tests/core/template_engine_test.lua
lua tests/core/manufacturer_normalizer_test.lua
lua tests/core/metadata_resolver_test.lua
lua tests/integration/metadata_resolver_native_test.lua /absolute/path/to/exiftool
lua tests/integration/metadata_source_resolver_test.lua
lua tests/integration/metadata_source_resolver_native_test.lua
lua tests/integration/exiftool_read_test.lua /absolute/path/to/exiftool /absolute/path/to/test-copy.RAF
```

`lua -v` が Lua 5.1 であることを確認してください。Phase 2 のネイティブテストには io.popen を利用できる POSIX 対応 Lua が必要です。RAF 引数なしでは合成データを使い、個人写真を自動探索しません。境界テストは SDK の実装を置き換え、エラーと安全な呼び出し順を検証するもので、JPEG の生成や SDK の非上書き動作は確認できません。差分確認には次を使います。

```sh
git status --short
git diff
git diff --check
```

## リポジトリ構成

```text
fuji-photo-renamer-lightroom-plugin/
├── AGENTS.md
├── README.md
├── CHANGELOG.md
├── LICENSE
├── .gitignore
├── docs/
│   ├── requirements.md
│   ├── architecture.md
│   ├── metadata-resolution.md
│   ├── tokens.md
│   ├── c2pa.md
│   ├── packaging.md
│   ├── testing.md
│   ├── phase1-lightroom.md
│   ├── phase2-exiftool.md
│   ├── phase3-metadata-sources.md
│   ├── phase4-metadata-merge.md
│   ├── phase5-manufacturers.md
│   ├── phase6-templates.md
│   ├── phase7-filename-safety.md
│   ├── phase8-export-dialog.md
│   ├── phase9-export-integration.md
│   ├── phase10-c2pa.md
│   ├── phase11-testing.md
│   ├── phase12-packaging.md
│   └── adr/                          # 削除方式・同梱方式の判断
├── src/
│   └── FujiPhotoRenamer.lrplugin/
│       ├── Info.lua
│       ├── ExportServiceProvider.lua
│       ├── Phase2Diagnostic.lua
│       ├── Phase2MetadataDiagnostic.lua
│       ├── Phase3Diagnostic.lua
│       ├── Phase4Diagnostic.lua
│       ├── ExifToolLoader.lua
│       ├── dkjson.lua
│       ├── third_party/
│       ├── THIRD_PARTY_NOTICES/
│       ├── core/
│       ├── infrastructure/
│       ├── ui/
│       └── lightroom/
├── tests/
│   ├── core/
│   ├── integration/
│   └── run_tests_test.py
├── fixtures/
│   └── metadata/
└── scripts/                         # run-tests.py、prepare-exiftool.mjs、package.mjs等
```

空ディレクトリは `.gitkeep` で保持します。製品版の推奨ファイル配置は [設計](architecture.md#推奨ファイル配置) に記載しています。ルートの provider は SDK の登録入口で、Phase 9 の処理は lightroom/ 配下に委譲します。
