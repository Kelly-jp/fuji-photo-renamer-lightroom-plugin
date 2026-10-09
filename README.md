# fuji-photo-renamer-lightroom-plugin

Adobe Lightroom Classic の写真書き出し時に、ExifTool で XMP / RAW / JPG のメタデータを取得し、ユーザー指定のテンプレートに従って出力ファイルを命名するプラグインです。

**Phase 1 の最小 SDK 検証プラグインを実装しました。macOS では、元フォルダーのサブフォルダーへの保存、同名時の非上書き、元 RAW / XMP のチェックサム不変についてユーザーから確認報告があります。その他の実機検証は未完了です。Phase 2 の ExifTool 読み取り専用ラッパーと診断メニューも追加しました。ExifTool の書き出し統合、テンプレート、C2PA 処理、製品向け配布は未実装です。**

## 対象と機能

- Lightroom Classic / Lua / Lightroom Classic SDK、Windows / macOS。
- 書き出し画面の独自設定 UI、テンプレート入力、ファイル名プレビュー。
- XMP → RAW → JPG の順に、項目単位でメタデータを採用。
- RAW 探索は JPG と同じ階層、1 つ上の階層、同じ階層 → 1 つ上の階層。最低限 RAF / DNG に対応。
- カメラとレンズのメーカーが正規化後に同一なら、メーカーを一つだけ出力するオプション。
- 書き出し JPEG の C2PA / Content Credentials（JUMBF）削除オプション。
- ExifTool と必要な実行依存を配布物に同梱。自己完結した配布方式は技術検証対象。

クラウド版 Lightroom、動画、公開サービスへのアップロードは対象外です。初期検証は JPEG 出力を基準とし、他形式の対応範囲は検証後に決定します。

## 命名例（設計仕様）

```text
{DateTime}_{CameraMaker}_{Camera}_{LensMaker}_{Lens}_{Sequence}.{Extension}

メーカー重複省略 ON:
20261008_123456_FUJIFILM_X-H2S_XF100-400mm_0001.jpg

メーカー重複省略 OFF:
20261008_123456_FUJIFILM_X-H2S_FUJIFILM_XF100-400mm_0001.jpg
```

利用できるトークンと欠落時の扱いは [トークン仕様](docs/tokens.md) を参照してください。元画像を変更せず、既存出力も暗黙に上書きしません。

## Phase 1 の読み込みと検証

1. Lightroom Classic の「ファイル → プラグインマネージャー → 追加」で `src/FujiPhotoRenamer.lrplugin/` を選択する。
2. 複製した元画像を専用カタログへ登録し、書き出し先として「Fuji Photo Renamer — Phase 1」を選ぶ。
3. 標準の「書き出し場所」で「特定のフォルダー」または「元の写真と同じフォルダー」を選び、必要なら「サブフォルダーに保存」を指定して JPEG を書き出す。
4. 指定先の `test_DSCF1234.jpg` のような出力と元画像のハッシュ不変を確認する。同名ファイルがある場合は失敗する。

「後でフォルダーを選択」やデスクトップ等の保存先も利用できます。同名ファイルは標準の「既存のファイル」の設定にかかわらず拒否します。この検証版ではカタログへの追加とスタック追加は適用しません。旧版からはプラグインを再読み込みし、書き出し画面を開き直してください。

SDK 宣言の最低バージョンは 11.0 です。これは確認済みの Classic 動作バージョンを意味しません。完全な確認手順、API の出典、未解決事項は [Phase 1 検証記録](docs/phase1-lightroom.md) を参照してください。

## Phase 2 の単体確認

プラグインを再読み込みし、「ファイル（またはライブラリ）→ プラグインエクストラ → Phase 2：ExifTool のメタデータ取得を検証…」から、検証用 ExifTool 実行ファイルと写真を選びます。今回は `/opt/homebrew/bin/exiftool` で macOS ネイティブ読み取りを検証しました。macOS の Lightroom 内でも、ユーザーが同じ XMP の FilmSim 取得成功を確認しています。

メニューが出ない場合は、プラグインマネージャーでパスがこのリポジトリの `src/FujiPhotoRenamer.lrplugin/`、表示名が「Fuji Photo Renamer — 開発検証版」、バージョンが `0.1.5.6` であることを確認します。「プラグイン作成者ツール」から再読み込みし、改善しなければ Lightroom Classic を再起動してください。

XMP の FilmSim は、既知の Lightroom Look / CameraProfile に対応します（例：Camera PROVIA/Standard → PROVIA）。未知のプロファイルは未取得として扱います。

診断メニューは元画像を読み取るだけです。書き出し名は Phase 1 の固定ルールのままで、テンプレート・探索・項目別マージにはまだ統合しません。同梱用 ExifTool ペイロードは未準備です。API、タグ、実データ結果、残課題は [Phase 2 記録](docs/phase2-exiftool.md) を参照してください。

## 開発の開始点

1. [要件](docs/requirements.md) と [アーキテクチャ](docs/architecture.md) を読む。
2. [技術検証項目](docs/testing.md#技術検証項目) の未確認事項を確認する。
3. Phase 2 の Lightroom 内での起動結果と残課題を記録し、次フェーズの指示を待つ。

プラグインは Lightroom 内で実行します。ビルドや Lint の自動化はありません。Lua 5.1 の実行環境を用意した場合、リポジトリのルートで以下を実行できます（Lua 本体は配布物に同梱しません）。

```sh
lua -v
luac -p src/FujiPhotoRenamer.lrplugin/Info.lua src/FujiPhotoRenamer.lrplugin/ExportServiceProvider.lua
lua tests/integration/phase1_provider_test.lua
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
│   └── phase2-exiftool.md
├── src/
│   └── FujiPhotoRenamer.lrplugin/
│       ├── Info.lua
│       ├── ExportServiceProvider.lua
│       ├── Phase2Diagnostic.lua
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
│   └── integration/
├── fixtures/
│   └── metadata/
└── scripts/
```

空ディレクトリは `.gitkeep` で保持します。製品版の推奨ファイル配置は [設計](docs/architecture.md#推奨ファイル配置) に記載しています。Phase 1 のみ最小構成のため provider をルートへ置きます。

## 設計文書

| 文書 | 内容 |
| --- | --- |
| [要件](docs/requirements.md) | 対象、主要機能、安全要件、受け入れ条件 |
| [アーキテクチャ](docs/architecture.md) | 責務、依存方向、書き出しフロー |
| [メタデータ解決](docs/metadata-resolution.md) | 入力探索、項目単位の優先順位、採用元 |
| [トークン](docs/tokens.md) | 構文、表示形式、メーカー比較、衝突 |
| [C2PA](docs/c2pa.md) | 削除対象の制限と検証 |
| [配布](docs/packaging.md) | ExifTool 同梱、依存、ライセンス |
| [テスト](docs/testing.md) | テスト方針と技術検証 6 項目 |
| [Phase 1](docs/phase1-lightroom.md) | 最小 SDK 実装、API 出典、手動検証と判定 |
| [Phase 2](docs/phase2-exiftool.md) | ExifTool 単体読み取り、内部モデル、実データ検証 |

## ライセンス・公式資料

本プロジェクトは [MIT License](LICENSE) です。同梱する ExifTool、実行ランタイム、SDK にはそれぞれの条件が適用されます。

Adobe は Lua によるプラグイン開発、書き出し UI 拡張、レンダリング済みファイルの別保存先への転送を案内しています。ただし、この設計の実現を実機確認したものではありません。[Adobe Lightroom Classic 開発者ページ](https://developer.adobe.com/lightroom-classic)
