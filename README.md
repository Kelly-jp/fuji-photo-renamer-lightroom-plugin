# fuji-photo-renamer-lightroom-plugin

Adobe Lightroom ClassicからJPEGを書き出す際に、撮影日時・カメラ・レンズ・フィルムシミュレーションなどを使ってファイル名を付けるプラグインです。ExifToolでXMP / RAW / JPGのメタデータを読み取り、指定したテンプレートから出力名を生成します。

## できること

- 撮影情報のトークンを組み合わせたファイル名の設定とプレビュー。
- XMP → RAW → JPGの順で、欠けたメタデータを項目ごとに補完。RAF / DNGを同じフォルダーや1つ上のフォルダーから探索。
- カメラとレンズのメーカーが同じ場合に、レンズメーカーを省略。
- `-DxO_DeepPRIME XD2s_XD`など、複数の指定文字列を元ファイル名から削除してからテンプレートを適用。
- Lightroom標準の書き出し場所・サブフォルダー・透かし設定を利用。
- 保存後にFinder / Explorerで表示、または指定アプリで開く。
- 新しく書き出すJPEGだけを対象に、C2PA / Content Credentials（JUMBF）を削除するオプション（既定OFF）。

元RAW・元JPG・XMPは変更しません。同名ファイルがある場合は`_001`、`_002`を付け、既存ファイルを上書きしません。

## ファイル名の例

```text
テンプレート:
{DateTime}_{CameraMaker}_{Camera}_{LensMaker}_{Lens}_{FilmSim}_{Original}

出力例（同じメーカーの省略ON）:
20261008_123456_FUJIFILM_X-H2S_XF200mm-F2-R-LM-OIS-WR_PROVIA_DSCF1234.jpg
```

拡張子は自動で付きます。トークン値の連続空白はハイフンへ変換し、英字の大文字・小文字は保持します。

対応トークンは`{Date}`、`{Time}`、`{DateTime}`、`{Original}`、`{CameraMaker}`、`{Camera}`、`{LensMaker}`、`{Lens}`、`{FilmSim}`です。表示形式や欠落時の扱いは[トークン仕様](docs/tokens.md)を参照してください。

## 動作対象

- Adobe Lightroom Classic（クラウド版Lightroomは対象外）
- macOS Apple Silicon / Windows x64（Intel Macは対象外）
- JPEG書き出し

現在は開発検証版です。Windows実機での動作確認は未実施です。macOSの同梱ランタイムはad-hoc署名付きですが、Developer ID署名・Appleの公証はなく、Gatekeeperの個別許可が必要になる場合があります。[配布・環境ごとの検証状況](docs/phase12-packaging.md)

## インストールと使い方

1. 対象OS向けのZIPを解凍し、`FujiPhotoRenamer.lrplugin/`を任意の場所に置きます。ZIPは下記の手順でビルドできます。
2. Lightroom Classicの「ファイル → プラグインマネージャー → 追加」で、そのフォルダーを登録します。
3. 写真の書き出し画面で「Fuji Photo Renamer」を選びます。
4. テンプレートと「書き出し場所」を設定し、必要に応じてプレビュー・メーカー省略・透かし・後処理を設定して書き出します。

配布ZIPにはExifToolと実行に必要なランタイムを同梱します。利用者によるExifTool / Perlの追加インストールは不要です。書き出し設定のExifToolパスは空欄にしてください。

除外文字列は「除外文字列を編集…」から1行に1件ずつ入力し、「編集を完了」を押します。改行はMacでは **Option＋Return**、Windowsでは **Ctrl＋J** です（Windowsは実機未確認）。設定は書き出しプリセットへ保存できます。

処理終了ダイアログは表示しません。書き出し失敗はLightroom標準のエラー報告で確認でき、メタデータや後処理の警告は[ログ](docs/development.md#書き出しログ)に記録します。

## ビルド方法

リポジトリのルートで実行します。Luaソースのコンパイルは不要で、ExifToolとランタイムを準備して配布ZIPを作成します。

必要な開発ツールはNode.js 20以上とPython 3.9以上です。macOS版のビルドにはApple Silicon MacとApple Command Line Toolsも必要です。追加のnpm / Pythonパッケージは使いません。

```sh
# macOS版
node scripts/prepare-exiftool.mjs --platform macos --jobs 4
node scripts/package.mjs --platform macos

# Windows版（macOS上でも生成可能）
node scripts/prepare-exiftool.mjs --platform windows
node scripts/package.mjs --platform windows
```

両OSをまとめる場合は`--platform all`を指定します。macOS版の生成を含むため、Apple Silicon Macで実行してください。

`dist/`に次の形式のZIPと`.sha256`ファイルを生成します。バージョンは`Info.lua`から読み取ります。同名のZIPは上書きしません。

```text
fuji-photo-renamer-lightroom-plugin-<version>-macos.zip
fuji-photo-renamer-lightroom-plugin-<version>-windows.zip
```

依存のバージョン・取得元・SHA-256は`scripts/exiftool-lock.json`で固定しています。準備済みキャッシュだけを使う場合は準備コマンドに`--offline`を追加します。[同梱とパッケージの詳細](docs/packaging.md)

## GitHub Release

`Info.lua`と`CHANGELOG.md`の版をそろえてmainへマージし、`v0.10.2`のようなタグをpushすると、GitHub Actionsがテスト・OS別ZIP生成・Windows同梱ExifToolの確認を行い、4つの配布ファイルを添付したRelease下書きを作成します。自動公開はしません。[準備・公開・失敗時の手順](docs/releases.md)

## テスト

Lua / luac 5.1を用意し、リポジトリルートで実行します。

```sh
python3 scripts/run-tests.py --suite core
python3 scripts/run-tests.py --suite sdk
node --test tests/packaging_test.mjs
python3 tests/archive_test.py
python3 tests/run_tests_test.py
```

macOSで実ExifTool連携を含む全Luaテストを実行する場合:

```sh
python3 scripts/run-tests.py --exiftool /absolute/path/to/exiftool
```

LuaがPATH上にない場合は`--lua /absolute/path/to/lua --luac /absolute/path/to/luac`を指定します。SDK境界テストはLightroom実機での動作確認とは異なります。[開発・テストの詳しい手順](docs/development.md)

## リポジトリ構成とドキュメント

- `src/FujiPhotoRenamer.lrplugin/`: Lua / Lightroom Classic SDKによるプラグイン本体
- `scripts/`: 依存の準備、ZIP生成、テスト実行
- `tests/`・`fixtures/`: 単体・結合テストと検証用素材
- `docs/`: 要件、設計、開発手順、技術検証の記録

設計書と段階別の開発・検証記録は[ドキュメント一覧](docs/README.md)にまとめています。変更内容は[CHANGELOG](CHANGELOG.md)、貢献時の指針は[AGENTS.md](AGENTS.md)を参照してください。

## ライセンス

本プロジェクトは[MIT License](LICENSE)です。同梱するExifTool・Perlなどの第三者ソフトウェアには、それぞれのライセンスが適用されます。配布ZIPにライセンスと`THIRD_PARTY_NOTICES.md`を含めます。
