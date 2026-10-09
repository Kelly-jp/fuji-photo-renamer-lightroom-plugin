# Changelog

## Unreleased

### Added

- Phase 2 の読み取り専用 ExifTool ラッパー、OS 別の期限付き runner、単体診断メニューを追加。
- dkjson 2.11 を公式 SHA-256・ライセンス付きで固定し、合成フィクスチャと Phase 2 テスト・検証記録を追加。
- ExifTool 13.55 で許諾済み X-H2S RAF の必要項目取得と SHA-256 不変を確認。Phase 2 は 83 件、Phase 1 の回帰は 66 件成功。

- Phase 1 の JPEG 一時レンダリング・固定命名・保存先選択に限定した最小 SDK プラグインを追加。
- Lua 5.1 の SDK 境界テストと Phase 1 の手動検証・API 出典・未解決事項の記録を追加。実機での成立性は未確認。

- 開発用ディレクトリとドキュメントの雛形を追加。
- Lightroom Classic 専用の要件、責務分離、メタデータ解決、13 トークン、C2PA 削除、ExifTool 同梱、テスト方針を定義。
- 未検証の技術検証 6 項目と、その手順・合格条件を記載。
- core / infrastructure / ui / lightroom と単体・結合テストのディレクトリを追加。本体コードは未実装。

### Changed

- fphoto-renamer の取得ロジックを参考に、XMP の CRS LookName / CameraProfile から既知の FilmSim を解決。実 XMP の PROVIA 取得と RAW / XMP の SHA-256 不変を確認。未知名の誤認防止を含め Phase 2 テストを 83 件へ拡張。

- SDK の ExifToolLoader 名前検索エラーを回避するため、検証メニューと依存モジュールの読み込みを絶対パスの loadfile に統一。名前検索失敗を再現する回帰テストを追加。

- Lightroom 独自 require へサブフォルダー名を渡して発生するエラーを修正。ルートの ExifToolLoader と dkjson を使用し、テストにも script name 制約を追加。

- Phase 2 の単体診断を File / Library 両方のプラグインエクストラへ登録し、読み込み版確認用に `0.1.5.6` へ更新。

- Phase 1 の保存先を標準の「書き出し場所」へ変更。特定フォルダー、元画像と同じフォルダー、サブフォルダー等を利用できるようにし、一時レンダリングと非上書きコピーは維持。境界テストは 66 件に拡張。

- AGENTS.md と README.md をプロジェクト固有の開発・安全ルールに更新。
- .gitignore を生成物、第三者配布物、秘密情報、非公開テスト素材向けに整理。
