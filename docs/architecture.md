# アーキテクチャ

## 方針と依存方向

KISS、YAGNI、DRY を優先し、小さな Lua モジュールと明示的な入力・戻り値で構成します。汎用プラグイン基盤、DI コンテナ、イベントバスは導入しません。この文書は責務の設計であり、SDK API の呼び出し仕様ではありません。

```text
ui/ExportDialog ───────────────> core（プレビュー）
lightroom/ExportServiceProvider > core（命名・解決）
lightroom/ExportServiceProvider > infrastructure（取得・保存）
infrastructure ───────────────> SDK / ExifTool / OS
core ─────────────────────────> 純粋な Lua データのみ
```

core は Lightroom のオブジェクト、プロセス、実ファイルパスへのアクセスを持ちません。adapter が入力を普通のテーブルに変換します。SDK の詳細は adapter、UI 構築、SDK を使うインフラ境界に限定します。

## モジュールの責務

| 層 / モジュール | 責務 | 入力 → 出力 |
| --- | --- | --- |
| core / TemplateParser | 固定トークン構文の検証と分解 | テンプレート → リテラル・トークン列または構文エラー |
| core / TokenResolver | 型付き項目の表示化、連番、メーカー省略、区切り整理 | トークン列・項目・設定・連番 → 候補名または欠落エラー |
| core / ManufacturerNormalizer | 既知別名を正規化して比較 | メーカー文字列 → 比較キー・表示名 |
| core / MetadataResolver | XMP → RAW → JPG の項目別採用 | 各入力の項目テーブル → 解決値・採用元・欠落一覧 |
| core / FilenameSanitizer | OS 共通の禁止名・文字・長さ規則 | 候補名・制約 → 安全な名前またはエラー |
| core / CollisionResolver | 衝突候補名を決定 | 安全な名前・既知使用名・試行番号 → 次の名前 |
| infrastructure / ExifTool | 同梱ツールの読取・限定した JUMBF 削除、JSON 解釈とタグ対応 | 確定済み読取パスまたは所有済み出力 → 項目・結果・診断 |
| infrastructure / MetadataSourceResolver | 元画像に対応する XMP / RAW / JPG の探索 | 元パス・探索設定 → 候補パス・曖昧性 |
| infrastructure / FileSystem | 実体同一性、所有ファイル、作業コピー、非上書き保存、清掃 | パス・セッション所有記録 → 結果 |
| infrastructure / Platform | OS 判定、同梱ツールの絶対パス、引数処理、プロセス制限 | 環境 → 実行設定 |
| ui / ExportDialog | 設定入力、検証表示、プレビュー、処理状態 | ユーザー入力 → 設定 |
| lightroom / ExportServiceProvider | SDK 登録、レンダリング待ち、処理順序、成功・失敗通知 | SDK 書き出しコンテキスト → セッション結果 |

タグの名前を理解するのは ExifTool 境界です。core へは `cameraMaker`、`lensMaker`、`captureDateTime` などの項目を渡し、値に sourceKind・sourcePath・tag を付けて採用元を追跡します。メタデータに ExifTool のエラーを紛れ込ませません。

## 書き出しフロー（検証前の設計）

1. 設定、出力先、トークン構文、同梱ツールの起動可否を検証する。
2. SDK から元画像のパスを読み取り、安全な読取元として確定する。
3. 入力候補を探索し、ExifTool で読み取り、項目別に解決する。
4. レンダリング完了を待ち、今回生成された一時出力の由来を記録する。
5. 一時出力から専用作業領域にコピーし、テンプレート展開・整形を行う。
6. 削除 ON なら、その作業コピーだけから JUMBF を削除し結果を検証する。
7. 出力候補を決め、既存ファイルを置換しない方法で保存する。保存時の衝突は候補を再生成する。
8. 確定結果を SDK へ通知し、所有する不要作業ファイルだけを清掃する。

SDK が任意保存先・一時出力・成功通知をどう提供するか、手順 4 と 7 の保証は [技術検証 1](testing.md#技術検証項目) で確定します。事前の存在確認だけでは上書き防止になりません。安全な確定保存を保証できなければ書き出しを失敗にします。

## プレビューと失敗処理

プレビューも同じ core のパイプラインを使います。取得は UI をブロックしない方式を SDK で確認し、連続編集時は古い結果を破棄します。書き出し開始時に再取得して入力を固定し、プレビューとの差を報告できるようにします。

Missing（項目欠落）と ReadError（読取失敗）を区別します。読み取り失敗を欠落として隠しません。削除 ON で削除失敗なら完成ファイルを公開しません。キャンセルでは新規処理を止め、既に確定した出力は残し、未確定の所有作業ファイルを清掃します。失敗は写真単位で記録し、全体成功と誤表示しません。

## 推奨ファイル配置

以下は将来追加するファイルです。現段階で Lua ファイルや依存バイナリは作成しません。

```text
src/FujiPhotoRenamer.lrplugin/
├── Info.lua                         # SDK 確認後に登録情報を定義
├── core/
│   ├── TemplateParser.lua
│   ├── TokenResolver.lua
│   ├── ManufacturerNormalizer.lua
│   ├── MetadataResolver.lua
│   ├── FilenameSanitizer.lua
│   └── CollisionResolver.lua
├── infrastructure/
│   ├── ExifTool.lua
│   ├── MetadataSourceResolver.lua
│   ├── FileSystem.lua
│   └── Platform.lua
├── ui/ExportDialog.lua
└── lightroom/ExportServiceProvider.lua
```

配布時のみ追加する `vendor/` と第三者ライセンスは [配布設計](packaging.md) を参照してください。モジュールごとにクラス階層やインターフェースファイルを作る必要はありません。
