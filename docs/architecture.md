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

以下は製品版に向けた配置です。Phase 1 では `Info.lua` とルートの `ExportServiceProvider.lua` のみを実装し、Phase 2 で `infrastructure/ExifTool.lua` と診断メニュー・OS runner・JSON ライブラリを追加しました。Phase 3 の探索モジュールと Phase 4 の MetadataResolver も追加しました。それ以外の core モジュールや配布用バイナリは未実装です。

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

## Phase 1 の実装上の限定

最小 SDK 検証のため、設定 UI と書き出し処理をルートの `ExportServiceProvider.lua` に置きます。これはユーザー指定の最小構成に合わせた一時的な例外です。ExifTool / core の処理を追加せず、製品版の UI 分離は Phase 8、adapter への統合は Phase 9 で行います。

`showSections` で標準の `exportLocation` を表示します。`updateExportSettings` で最終保存先設定をセッション用 `phase1Destination` に退避してから、一時レンダリングへ切り替えます。これはユーザーの保存先拡張指示に基づく変更で、元画像フォルダーへ直接レンダリングさせないためです。`updateExportSettings` でも `LR_format = JPEG` と `LR_export_destinationType = tempFolder` を固定し、他サービスの設定混入を防ぎます。`processRenderedPhotos` は SDK が用意するタスクで動き、元パスは読み取りだけ、保存は `LrFileUtils.copy` のみです。元画像・レンダリング結果の移動・削除はせず、一時出力の清掃は Lightroom に任せます。「元の写真と同じフォルダー」は写真ごとの元パスの親を使い、明示的に指定されたサブフォルダーだけ必要時に作成します。

SDK 契約の確認と実機での成立性は分けます。特に `copy` の競合時動作、コピー失敗時の部分ファイル、リンクの扱いは実機ゲートに残します。[Phase 1 記録](phase1-lightroom.md)

## Phase 2 の境界

単体診断メニュー `Phase2Diagnostic.lua` から `infrastructure/ExifTool.lua` を呼び出します。ExifTool の生タグはラッパー内で camelCase の内部項目へ変換し、採用元と診断は別テーブルに保持します。core は依存しません。OS 別の `ExifToolRead.sh` / `ExifToolRead.ps1` は、SDK にない実行時間制限と出力取得を補う小さなプロセス境界です。汎用 Platform や FileSystem の抽象化は後続の必要性が出るまで作りません。

Phase 1 の書き出しフローは変更せず、探索と読取、テンプレートとタグ名を混在させません。ライセンス・固定版を伴う純 Lua JSON ライブラリの manifest を `third_party/` に置き、SDK の require 制約によりソースはルートの `dkjson.lua` に置きます。検証メニューが絶対パスの loadfile でルートの `ExifToolLoader.lua` を読み込み、この入口が同じ方法で JSON と infrastructure 本体を読み込み、プラグイン専用コンテキストを引数として渡します。ExifTool の配布ペイロードは別扱いとします。[Phase 2 記録](phase2-exiftool.md)

## Phase 3 の境界

`infrastructure/MetadataSourceResolver.lua` は SDK の読取 API だけを使い、元画像と探索方法から `{xmp, raw, jpeg}` を返します。ExifTool、メタデータ、書き出し処理へ依存しません。SDK namespace を初期化引数で渡し、絶対パスの loadfile で読み込みます。根拠は [Phase 3 記録](phase3-metadata-sources.md) に記載しています。

`Phase3Diagnostic.lua` は元画像を選択し 3 モードの探索結果を表示する単体処理です。SDK から起動する共通入口は既存の `Phase2Diagnostic.lua` に限定し、Phase 2 の読取処理は `Phase2MetadataDiagnostic.lua` へ分離します。各処理は絶対パスの loadfile と明示コンテキストで読み込みます。本番の設定 UI・MetadataResolver・全体統合は後続 Phase に残します。フォルダー列挙は呼び出し内で一度ずつ行い、永続キャッシュや汎用 FileSystem 抽象化は追加しません。

## Phase 4 の境界

core の MetadataResolver は SDK・ExifTool・I/O・時計を持たない純粋なテーブル処理です。Phase4Diagnostic のみに探索・読取・統合の検証用手順を組み合わせます。core へは metadata / opaque な採用元だけを渡し、生タグや読取警告の扱いは adapter に残します。

既存共通入口でメタデータ検証方法を選択し、絶対パスで Phase4Diagnostic を読み込みます。これは単体成立性の確認用であり、ExportServiceProvider への全体統合は Phase 9 に残します。[Phase 4 記録](phase4-metadata-merge.md)
