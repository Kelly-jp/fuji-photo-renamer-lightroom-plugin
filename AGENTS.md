# Repository Guidelines

## 対象と現在の作業範囲

Adobe Lightroom Classic専用の写真書き出しプラグインです。Lua / Lightroom Classic SDKを使い、Windows x64 / macOS Apple Siliconを対象とします。Intel Macはユーザー指示により対象外です。Phase 12のExifTool同梱・OS別ZIPを実装・自動検証しました。Windows実機は環境がなく保留です。Phase 12の結果報告後は作業を止め、指示なしに公開リリースや対応範囲の拡大を行わないでください。

追加指示により元名の除外文字列・標準透かし・書き出し後の表示/指定アプリ起動を実装しています。除外は元名のstemだけへ適用し、その後にテンプレート展開します。最終JPEGだけを後処理へ渡します。仕様・SDK出典は`docs/filename-cleanup-export-options.md`に従ってください。

## 構成と設計の基準

- `src/FujiPhotoRenamer.lrplugin/`: プラグイン本体。Phase 1 はルートの `Info.lua` と `ExportServiceProvider.lua`、Phase 2 は `infrastructure/ExifTool.lua`、Phase 3 は `infrastructure/MetadataSourceResolver.lua`、Phase 4〜7 は `core/MetadataResolver.lua`、`ManufacturerNormalizer.lua`、`TemplateParser.lua`、`TokenResolver.lua`、`FilenameSanitizer.lua`、`CollisionResolver.lua` と統合診断を使用します。Phase 8 は `ui/ExportDialog.lua` に UI とサンプルプレビューを分離します。Phase 9 はルート登録入口から `lightroom/ExportServiceProvider.lua` に処理を委譲し、`infrastructure/MetadataReader.lua` と `FileSystem.lua` で取得・保存を接続します。Phase 10 は `ExportArtifact.lua` に所有確認、`core/JpegIntegrity.lua` にバイト保持検証を分離し、ExifTool の新規出力だけを処理します。
- `docs/`: 要件、設計、メタデータ解決、トークン、C2PA、配布、テストの仕様。
- `tests/`: 単体・結合テスト。Phase 1 の SDK 境界テストと手動検証は `docs/phase1-lightroom.md` を参照。`fixtures/metadata/`: 匿名化した入力と期待結果。
- `scripts/`: 検証・配布用スクリプト。ExifTool/Perlの取得元・版・SHA-256は`exiftool-lock.json`に固定し、`prepare-exiftool.mjs`で検証後に準備、`package.mjs`で必要ファイルのみZIPへ組み込みます。バイナリをGitへ追加せず、`.cache/`・`build/`・`dist/`に置きます。`CHANGELOG.md`: 変更履歴。

変更前に関連文書を読み、仕様変更時は文書も更新してください。KISS、YAGNI、DRY を優先します。汎用フレームワーク、DI コンテナ、将来用途だけの抽象化は追加しません。core は SDK、ExifTool、ファイル I/O に依存しない純粋な Lua 処理として設計します。

## 開発・検証

LuaテストはLua 5.1、実行補助・アーカイブ処理はPython 3標準ライブラリ、配布スクリプトはNode.js標準機能で実行します。追加のnpm / Pythonパッケージは使いません。`run-tests.py`はファイルごとに独立したプロセスを使い、core / sdk / nativeを分離します。nativeはmacOSと明示したExifToolが必要です。新規Luaテストはスイート一覧へ登録してください。コマンドはREADME、配布検証は`docs/phase12-packaging.md`を参照します。Lua 5.1互換を維持し、SDKダブルや配布CLIテストをLightroom実機の確認と呼ばないでください。第三者のライセンスと原版を保持し、取得・準備済みファイルのハッシュ不一致を無視して再取得・パッケージしません。生成物を暗黙に上書きせず、`git diff --check`等で差分を確認します。Lint・公開リリースの自動化は未導入です。

実装時のインデントはスペース 4 個、モジュール名は `TemplateParser.lua` のように PascalCase、関数・変数は camelCase を基本とします。コメントは設計理由を説明します。テストは `tests/core/*_test.lua` の命名を予定し、正常系、欠落、不正入力、衝突、外部処理失敗を独立して検証します。詳細は `docs/testing.md` に従ってください。

## 必須の安全ルール

元 RAW、元 JPG、XMP、カタログ内の元画像は読み取り専用です。既存ファイルを暗黙に上書きしません。C2PA/JUMBF 削除は、今回生成したことを追跡できる書き出しファイルだけに適用します。任意パスやフォルダ全体を削除対象に渡してはいけません。

SDK API を推測で使用しないでください。不明点は Adobe 公式 SDK リファレンスまたは SDK 同梱サンプルで確認し、バージョン、出典、実機結果を記録します。未確認事項は `docs/testing.md` の技術検証項目として残してください。エラーを握りつぶさず、タイムアウトやキャンセルを明示的に扱います。

## コミットと PR

`feat:`、`fix:`、`docs:`、`test:`、`chore:` と日本語の説明を使用します。例: `docs: 項目単位のメタデータ解決仕様を定義`。変更は単一目的にまとめ、main/master へ直接コミットしません。PR に目的、仕様への影響、検証結果、未検証事項を記載し、関連 Issue、UI 画像、命名の入出力例を必要に応じて添えます。

返答、質問、要約は日本語で行い、識別子、ログ、コマンド出力は原文を維持します。秘密情報や個人情報を含む写真・メタデータはコミットしません。
