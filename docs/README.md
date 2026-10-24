# ドキュメント一覧

利用方法・ビルドの入口は[リポジトリのREADME](../README.md)を参照してください。このディレクトリでは仕様、設計、検証結果、開発経緯を管理します。Phase文書は段階ごとの記録として読み、現在の対応状況と区別してください。

## 開発ガイド

- [開発環境・テスト実行・リポジトリ構成](development.md)
- [READMEから移した段階別の開発・検証経緯](development-history.md)
- [C2PA作業出力の所有に関する判断](adr/0001-c2pa-private-output.md)
- [ExifTool・Perlの同梱に関する判断](adr/0002-bundled-exiftool.md)
- [変更履歴](../CHANGELOG.md)

## 仕様・設計・検証記録


| 文書 | 内容 |
| --- | --- |
| [要件](requirements.md) | 対象、主要機能、安全要件、受け入れ条件 |
| [アーキテクチャ](architecture.md) | 責務、依存方向、書き出しフロー |
| [メタデータ解決](metadata-resolution.md) | 入力探索、項目単位の優先順位、採用元 |
| [トークン](tokens.md) | 構文、表示形式、メーカー比較、衝突 |
| [除外文字列・書き出し操作](filename-cleanup-export-options.md) | 元名の事前整形、標準透かし、保存後の操作 |
| [C2PA](c2pa.md) | 削除対象の制限と検証 |
| [配布](packaging.md) | ExifTool 同梱、依存、ライセンス |
| [テスト](testing.md) | テスト方針と技術検証 6 項目 |
| [Phase 1](phase1-lightroom.md) | 最小 SDK 実装、API 出典、手動検証と判定 |
| [Phase 2](phase2-exiftool.md) | ExifTool 単体読み取り、内部モデル、実データ検証 |
| [Phase 3](phase3-metadata-sources.md) | 入力探索、曖昧性、探索診断と検証 |
| [Phase 4](phase4-metadata-merge.md) | 項目別の有効値採用、日時検証、採用元 |
| [Phase 5](phase5-manufacturers.md) | メーカーの比較キー・表示名・同一判定 |
| [Phase 6](phase6-templates.md) | テンプレート構文・9 トークン・メーカー省略・命名候補 |
| [Phase 7](phase7-filename-safety.md) | ファイル名整形・予約名・長さ制約・衝突候補 |
| [Phase 8](phase8-export-dialog.md) | 書き出し設定・サンプルプレビュー・プリセット宣言 |
| [Phase 9](phase9-export-integration.md) | 実写真の取得・テンプレート保存・非上書き境界・実写真プレビュー |
| [Phase 10](phase10-c2pa.md) | C2PA削除・作業出力の所有・JPEG保持検証 |
| [Phase 11](phase11-testing.md) | 必須ケース対応表・一括実行・手動Integration Test・残課題 |
| [Phase 12](phase12-packaging.md) | 固定版ExifTool/Perlの同梱・OS別ZIP・ライセンス・配布検証 |
