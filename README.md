# fuji-photo-renamer-lightroom-plugin

Adobe Lightroom Classic の写真書き出し時に、ExifTool で XMP / RAW / JPG のメタデータを取得し、ユーザー指定のテンプレートに従って出力ファイルを命名するプラグインです。

**現在は開発基盤・設計文書のみです。Lua 本体は未実装で、インストールできるプラグインや配布バイナリはありません。**

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

## 開発の開始点

1. [要件](docs/requirements.md) と [アーキテクチャ](docs/architecture.md) を読む。
2. [技術検証項目](docs/testing.md#技術検証項目) の未確認事項を確認する。
3. 実装開始の指示後に Adobe 公式 SDK と同梱サンプルを確認し、対象 SDK / Lightroom / Lua のバージョンを決める。

現時点ではビルド、実行、テスト、Lint コマンドはありません。文書変更の確認には次を使います。

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
│   └── testing.md
├── src/
│   └── FujiPhotoRenamer.lrplugin/
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

空ディレクトリは `.gitkeep` で保持します。各モジュールの推奨ファイル配置は [設計](docs/architecture.md#推奨ファイル配置) に記載し、まだ `.lua` ファイルは作りません。

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

## ライセンス・公式資料

本プロジェクトは [MIT License](LICENSE) です。同梱する ExifTool、実行ランタイム、SDK にはそれぞれの条件が適用されます。

Adobe は Lua によるプラグイン開発、書き出し UI 拡張、レンダリング済みファイルの別保存先への転送を案内しています。ただし、この設計の実現を実機確認したものではありません。[Adobe Lightroom Classic 開発者ページ](https://developer.adobe.com/lightroom-classic)
