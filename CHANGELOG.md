# Changelog

## Unreleased

### Added

- Phase 10のC2PA/JUMBF削除をJPEG限定で追加。SDK由来の所有ハンドルから新規作業出力を作り、独立JPEG保持検証とExifTool再読取の成功後だけ保存。
- JPEG core検証、合成・実JPEGコピーのネイティブ検証、ON/OFF・失敗・キャンセルの回帰とADRを追加。元画像は変更せず、実JPEGの非JUMBFバイト・画素・入力SHA-256不変を確認。

- Phase 9 の書き出し統合を追加。元画像から探索・読取・項目統合・テンプレート展開・整形・衝突候補生成を行い、標準保存先へ非上書きコピー。
- 検証用 ExifTool パスと選択写真の非同期プレビューを追加。パイプライン24、プレビュー11、実 ExifTool 合成連携4ケースを検証。元画像の書き込みや C2PA 削除は追加しない。

- Phase 8 の ExportDialog を追加。テンプレート入力・即時サンプルプレビュー・RAW 探索方法・メーカー省略・C2PA 設定とプリセット対象を宣言。標準保存先を継続利用。
- SDK 境界 28 件と手動確認手順を追加。不正設定と未実装の C2PA ON は書き出しを拒否し、監視を終了時に解除。実写真取得と命名保存への統合は未実装。

- Phase 7 の純 Lua FilenameSanitizer / CollisionResolver を追加。禁止文字、制御文字除去、UTF-8・予約名・長さ制約、既存名と予約名からの連番候補に対応。
- Phase 7 core 76 件と統合診断の整形・仮想衝突例を検証。実保存と Phase 8 以降は未実装。

- Phase 6 の純 Lua TemplateParser / TokenResolver を追加。13 トークン、意味に基づくメーカー省略、欠落区切り整理と診断候補 ON/OFF に対応。
- Phase 6 core 64 件と既存連携の候補表示・入力不変を検証。書き出し統合と Phase 7 以降は未着手。

- Phase 5 の純 Lua ManufacturerNormalizer と比較表示を追加。既知の FUJIFILM 別名、TAMRON / SIGMA、未知メーカーのキー比較に対応。元 Metadata は不変。
- Phase 5 core の 32 件と統合診断の比較表示を検証し、仕様・手動手順を追加。出力省略と Phase 6 は未実装。

- Phase 4 の純 Lua MetadataResolver と統合診断を追加。XMP → RAW → JPG の項目別採用、型・数値・日時検証、採用元・欠落・不採用理由を記録。
- Phase 4 の core 59 件・macOS 合成連携 6 件のテストと仕様文書を追加。Phase 5 以降は未着手。

- Phase 3 の読み取り専用 MetadataSourceResolver と探索診断メニューを追加。3 モード、RAF / DNG、XMP、拡張子大小文字、曖昧性検出に対応。
- Phase 3 の境界 43 件・macOS 合成配置 9 件のテストと検証記録を追加。Phase 4 以降は未着手。

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

- 前回設定で元名 JPEG とテンプレート名 JPEG が残る経路に対処し、検証済み SDK 生成ファイルだけを非上書きで移動。最終名一致は再コピーせず、生成 JPEG の読取元除外と保存先退避の再適用を追加。

- トークン値の前後・連続空白を整理してハイフン化し、大小文字とテンプレートのリテラルを保持。Rust 版の既知 FilmSim 表示名に合わせて CLASSIC-Neg、PRO-Neg-Std 等へ変換。元 Metadata は不変。

- ユーザー指示により Sequence トークン・ボタン・セッション連番を廃止。通常は番号なし、衝突時だけ _001 / _002 を付与。旧末尾のトークンを UI で移行。

- ユーザー指示により ISO / FocalLength トークンとボタンを削除し、10 トークンへ整理。SDK 14.3 の公開 API でキャレット挿入を確認できないため、末尾追加を維持。

- ユーザー指示により Extension を廃止し、拡張子を常に自動付加。旧プリセット末尾のトークンを移行し、12 個のトークンを末尾へ追加するボタンを追加。

- DNG / JPG の既知編集プロファイルを旧 MakerNotes より優先し、FilmSim の採用ファイル・タグを統合診断へ追加。ユーザーが DNG 書き出しの実ケースで変更後 FilmSim 取得成功を確認。

- 新規 Phase3Diagnostic が SDK に認識されないエラーへ対処し、既存 Phase2Diagnostic を共通入口に変更。読取・探索処理は別ファイルを絶対パスで読み込む方式へ統一。

- fphoto-renamer の取得ロジックを参考に、XMP の CRS LookName / CameraProfile から既知の FilmSim を解決。実 XMP の PROVIA 取得と RAW / XMP の SHA-256 不変を確認。未知名の誤認防止を含め Phase 2 テストを 83 件へ拡張。

- SDK の ExifToolLoader 名前検索エラーを回避するため、検証メニューと依存モジュールの読み込みを絶対パスの loadfile に統一。名前検索失敗を再現する回帰テストを追加。

- Lightroom 独自 require へサブフォルダー名を渡して発生するエラーを修正。ルートの ExifToolLoader と dkjson を使用し、テストにも script name 制約を追加。

- Phase 2 の単体診断を File / Library 両方のプラグインエクストラへ登録し、読み込み版確認用に `0.1.5.6` へ更新。

- Phase 1 の保存先を標準の「書き出し場所」へ変更。特定フォルダー、元画像と同じフォルダー、サブフォルダー等を利用できるようにし、一時レンダリングと非上書きコピーは維持。境界テストは 66 件に拡張。

- AGENTS.md と README.md をプロジェクト固有の開発・安全ルールに更新。
- .gitignore を生成物、第三者配布物、秘密情報、非公開テスト素材向けに整理。
