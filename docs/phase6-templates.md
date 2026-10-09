# Phase 6：テンプレートエンジン

## 範囲と状態

TemplateParser / TokenResolver を純 Lua 5.1 で実装しました。9 トークンとメーカー省略に対応し、既存の統合診断から候補を表示します。macOS の Lightroom 内でトークン展開とメーカー省略が動作したとユーザーから確認報告があります。書き出しは引き続き Phase 1 の `test_<original>.jpg` です。禁止文字・予約名・衝突の処理は Phase 7、テンプレート設定 UI は Phase 8、書き出し統合は Phase 9 に残します。

SDK API の追加はありません。既存の絶対パス `loadfile` と `LrPathUtils.leafName` / `removeExtension` を使用します。API の出典は [Phase 1](phase1-lightroom.md) と [Phase 3](phase3-metadata-sources.md) を参照してください。

## core の契約

- `TemplateParser.parse(template)`：リテラル・トークンの `segments`、使用トークン集合 `tokens` を返す。未知トークン、不正括弧、パス指定、廃止済み Extension は拒否する。
- `TokenResolver` の読み込み時に `{normalizer = ManufacturerNormalizer, metadataResolver = MetadataResolver}` を渡す。SDK・ExifTool・I/O を渡さない。
- `TokenResolver.resolve(parsed, metadata, options)`：Parser の結果、camelCase の内部 Metadata、出力情報を受け取り、`filename` / `missingTokens` / `omittedTokens` を返す。入力テーブルを変更しない。
- 失敗時は `nil, {code, message, token?}` を返す。Parser は `position`（バイト位置）も必要時に返す。

```lua
local parsed = assert(parser.parse('{CameraMaker}_{Camera}_{LensMaker}_{Original}'))
local candidate, err = resolver.resolve(parsed, metadata, {
    original = 'DSCF1234', extension = 'jpg',
    omitDuplicateManufacturer = true,
})
```

`extension` は常に必須で、ドットなしの英数字を小文字で付加します。Original 使用時は元画像の stem が必須です。メーカー省略の既定値は ON です。

## 展開と失敗の規則

形式・欠落規則は [トークン仕様](tokens.md) を正とします。日時検証は MetadataResolver の `isValidCaptureDateTime` を再利用し、日時成分を同じ撮影日時から取り出します。オフセット変換・現在時刻への代替はありません。

省略 ON でも、両方のメーカー値とトークンが存在して正規化キーが一致する場合だけ LensMaker を空にします。同じ文字列がモデル名・レンズ名・リテラルにあっても削除しません。欠落と意図的省略は別の一覧にします。

空欄に隣接するテンプレートの `_` / `-` / 空白だけを整理します。メタデータ内の文字列と無関係のリテラルは保持します。空の候補は `EmptyFilename`、日時欠落は `MissingDateTime`、型不正は `InvalidTokenValue`、元名・連番・拡張子不正はそれぞれのエラーとして返します。候補名はまだファイルシステムへ渡せる安全な名前ではありません。

## macOS 手動確認

1. プラグインマネージャーでこのリポジトリの `src/FujiPhotoRenamer.lrplugin/` を再読み込みし、バージョン `0.5.0.12` を確認する。
2. 「ファイル（またはライブラリ）→ プラグインエクストラ → メタデータ取得 / 入力ファイル探索を検証…」を開く。
3. 「ExifTool でメタデータ取得」→「XMP → RAW → JPG を統合」を選ぶ。
4. 検証用 ExifTool と元 JPG / JPEG / RAF / DNG を選択する。探索方法は診断の既定 `same_then_parent`。
5. 結果の「ファイル名候補（Phase 6）」で固定テンプレートと ON/OFF の候補を比較する。同一メーカーなら ON だけレンズメーカーを省略する。別メーカーなら両方を残す。
6. 空欄・省略一覧、元名、撮影日時を確認する。JPEG を想定した候補であり、ファイルは生成しない。日時不明なら候補だけがエラーとなり、取得結果は表示する。

例：`FUJIFILM / X-H2S / FUJIFILM / XF100-400mm` は ON で `..._FUJIFILM_X-H2S_XF100-400mm_...jpg`、OFF で `..._FUJIFILM_X-H2S_FUJIFILM_XF100-400mm_...jpg`。写真と XMP の SHA-256 不変を必要に応じて前後比較する。

## 自動検証・残課題

純 core 64 件と既存 macOS 合成連携 6 件が成功。9 トークン、構文、欠落、日時・数値、メーカー省略 ON/OFF、区切り、入力不変、共通メニューからの候補表示を確認しました。連携テストは SDK のダブルを使用し、Lightroom の実機証明ではありません。

Windows 実機、SDK による写真の列挙順・実連番、任意テンプレートの UI プレビュー、禁止文字・長さ・衝突は未検証または後続 Phase の範囲です。長い候補は診断ダイアログで見切れる可能性があります。Phase 7 へ進む前に手動結果を記録し、ユーザーの次指示を待ちます。

## 手動確認報告（2026-10-09）

ユーザーが macOS の Lightroom 内で「トークンとメーカー省略が効いている」と報告しました。診断での基本動作の確認として記録します。全 9 トークンの個別結果、異メーカー・欠落・不正構文の手動ケース、使用した写真・SDK・Lightroom の具体的バージョンは未記録です。自動テスト結果や書き出しへの統合確認とは区別します。Phase 6 の基本経路を確認済みとして、次フェーズの指示を待ちます。

## Phase 8 の仕様更新

Extension トークンはユーザー指示により廃止しました。例と解析結果は現在の 9 トークン仕様へ更新しています。内部の出力拡張子は必須で、TokenResolver が常に付加します。

ユーザー指示により ISO / FocalLength も廃止しました。現在は 9 トークンで、これらが含まれるテンプレートはエラーです。

Sequence トークンも廃止済みです。通常名に番号を付けず、衝突時だけ CollisionResolver で連番を付加します。
