# パッケージングと ExifTool 同梱

## 配布要件

Windows / macOSとも、ユーザーによるExifTool、Perl、Homebrewの追加インストールやPATH設定を不要にします。Phase 12では、公式ExifTool 13.59のWindows x64一式と、ExifToolソース＋ソースからビルドしたPerl 5.44.0のmacOS同梱方式を実装・検証します。バイナリはGitへ追加しません。生成できたことと、クリーン環境・Lightroom内で対応を確認できたことは区別します。[現在の検証・手順](phase12-packaging.md)

## OS 別の検証方針

| 対象 | 公式資料で確認できたこと | 本プロジェクトでの未確認事項 |
| --- | --- | --- |
| Windows x64 | 公式ZIPの実行ファイルを`exiftool.exe`へ改名し、`exiftool_files/`をライセンスZIPも含めて保持する。 | 実機の起動・日本語パス・Classic・セキュリティ製品。公式ペイロードのPerlは5.32.1で、保守終了版の扱いと依存更新をリリース前に判断する。 |
| macOS Apple Silicon | 同梱ランチャーがPerlとExifToolソースを絶対パスで起動する。Perlは再配置可能なライブラリ探索と静的libperlでビルドする。Intelはユーザー指示により対象外。 | クリーン環境・Classicからの同梱起動・署名/公証/隔離属性・実測した最低OS版。 |

macOS の pkg を同梱するだけでは自己完結要件を満たしません。システム Perl が利用できるという前提を製品保証にしないでください。[ExifTool 公式インストール資料](https://exiftool.org/install.html)

## 配布物の配置

```text
FujiPhotoRenamer.lrplugin/
├── Info.lua / ExportServiceProvider.lua / core/ / infrastructure/ / ui/ / lightroom/
├── vendor/
│   └── windows/ または macos/  # 対象OSの同梱物だけ
├── THIRD_PARTY_NOTICES/  # 原版のライセンス・通知
├── THIRD_PARTY_NOTICES.md
├── third_party/dependencies.json
├── PACKAGE_MANIFEST.json
├── INSTALL.md
└── LICENSE
```

ZIPのトップレベルは`FujiPhotoRenamer.lrplugin/`だけです。macOSの`vendor/macos/exiftool`はランチャー、`tool/`はExifTool本体とlib、`runtime/arm64/`はPerlです。Intelランタイムは含めません。システムPerl・PATHにはフォールバックしません。作業ファイルは別の専用領域に置きます。

macOS ZIPは、組立領域へコピーしたPerlと全Mach-Oモジュールを`codesign --force --sign - --timestamp=none`で個別にad-hoc署名し、厳密検証後に作成します。準備キャッシュは変更しません。manifestのハッシュは署名後のバイト列から生成し、署名対象一覧と未公証であることも記録します。Developer ID署名やGatekeeper通過を意味するものではありません。

## 取得と再現性

実装段階では公式配布元を選び、バージョン、取得 URL、取得日、SHA-256、対象 OS / CPU、依存一覧、適用ライセンスを manifest と第三者通知へ記録します。常に最新版を自動取得せず、検証済みの固定版を使います。更新時にタグ解釈と削除の回帰テストを実施します。

プロジェクトの MIT ライセンスが第三者ツールにも適用されるとみなしません。ExifTool と各ランタイムの公式配布物に含まれるライセンス、再配布・通知・ソース提供条件を確認します。Adobe SDK 本体やサンプルを無条件に再配布しません。

取得物は`.cache/downloads/`、検証済み同梱物は`.cache/prepared-exiftool/`、ログ・組立領域は`build/`、ZIPとSHA-256は`dist/`へ置きます。`src/`へバイナリをコピーしません。Node.jsの準備・パッケージスクリプトとPython標準ライブラリのアーカイブ補助を使います。ダウンロード・展開の前に固定ハッシュを検証し、パッケージ前に全準備済みファイルのハッシュ・実行権限を再確認します。

## リリース判定

[技術検証 6](testing.md#技術検証項目) が通るまで自己完結した配布を対応済みとしません。クリーン環境で起動・読取・削除、非 ASCII / 空白を含む設置パス、実行権限、依存不足時のエラーを確認します。管理者権限や OS の保護設定を一律に無効化する手順は採用しません。対応 OS / Classic / SDK / ExifTool の実測バージョンを README とリリース情報へ記載します。

## Phase 2 の開発用例外

Phase 2 は明示指定した開発用 ExifTool で読取を検証します。今回の検証版は Homebrew の 13.55 です。これは同梱や自己完結配布の完成ではなく、配布要件は維持します。既定の同梱パスにツールがなければエラーにし、PATH へフォールバックしません。

純 Lua JSON ライブラリ dkjson 2.11 のみをソース管理へ追加しました。25,009 bytes、MIT、Lua 5.1 対応を確認し、公式ハッシュ・取得 URL を `third_party/dependencies.json`、ライセンスを `THIRD_PARTY_NOTICES/dkjson-LICENSE.txt` に固定します。OS runner とこれらの通知は将来の配布に必要な構成要素です。ExifTool / Perl のペイロード、取得・ZIP スクリプトは Phase 12 まで追加しません。

## Phase 9 の検証用パス

fprExifToolPath を UI とプリセット対象に追加しました。空欄なら同梱パスを解決し、指定があればその絶対パスを使います。PATH や Homebrew の自動探索は行いません。未同梱時は書き出し開始を止めます。これは統合検証用の設定で、自己完結配布・取得スクリプト・バイナリ同梱は引き続き Phase 12 に残します。

## Phase 10 の追加ファイル

JPEG保持の純Lua検証と所有管理を追加しました。ExifTool実行は既存のOS別runnerを共用します。Pillowは開発時の画素比較だけに使い、配布・実行時の依存には追加しません。ExifTool同梱物と固定ダウンロード・ZIP生成はPhase 12に残します。
