# Phase 12：ExifTool同梱とOS別パッケージ

## 対象と設計

開発検証版`0.9.1.22`向けに、Windows x64とmacOS Apple SiliconのZIP生成を実装します。ユーザーの2026-10-11の指示によりIntel Macは対象外です。新しいSDK API、core機能、公開リリースは追加しません。バイナリはソース管理へ含めず、固定した公式配布物とビルド手順から組み立てます。

| 依存 | 固定版と取得元 | 同梱方式 |
| --- | --- | --- |
| ExifTool | 13.59、[公式ダウンロード案内](https://exiftool.org/)が指定するSourceForge、[公式チェックサム](https://exiftool.org/checksums-13.59.txt) | Windows公式64-bit ZIP、macOSはPerl配布のスクリプトとlib |
| macOS Perl | 5.44.0、[CPANソース](https://www.cpan.org/src/5.0/perl-5.44.0.tar.gz)、[公式SHA-256](https://www.cpan.org/src/5.0/perl-5.44.0.tar.gz.sha256.txt) | CPU別にビルドした実行ファイル・標準ライブラリ・ライセンス |
| Windows実行依存 | 公式ExifTool ZIPに含まれるStrawberry Perl 5.32.1等 | `exiftool_files/`一式を原版のまま保持。個別DLLを推測で間引かない |

全URL・版・SHA-256は`scripts/exiftool-lock.json`へ固定しています。更新時はmanifestを明示的に変更し、タグ・削除・配布の回帰を行います。最新版を自動取得しません。Windows実行依存のPerlは[CPANの保守状況](https://www.cpan.org/src/)上の保守終了版で、公式ペイロードの採用だけから安全性・製品対応を保証しません。

## macOSランタイムの判断

Perl公式INSTALLのRelocatable @INCに従い`-Duserelocatableinc -Uuseshrplib`を指定します。標準ライブラリ探索先を移動先の同梱Perlへ限定し、Mach-Oの動的依存をAppleのOSライブラリだけに限定します。システムPerl、Homebrew、外部libperlは不要です。[公式ビルド手順](https://github.com/Perl/perl5/blob/v5.44.0/INSTALL)

最初の5.42.0候補は標準テストでmacOSのロケール関連のpanicが出たため採用しませんでした。現行安定版5.44.0でもOSの`nl_langinfo(CODESET)`が一部ロケールで空文字を返す問題が残ったため、[公式locale.cのConfigure指定](https://github.com/Perl/perl5/blob/v5.44.0/locale.c)にある`-DHAS_BROKEN_LANGINFO_CODESET`をコンパイルフラグへ追加します。Perlが用意したUTF-8判定の対処を使い、ロケール機能全体の無効化やテスト除外は行いません。ソースは改変しません。

Apple Silicon上でネイティブにビルドし、SDKROOTと出力CPUを明示します。検討途中のIntel / Rosettaビルドと、そのためのtoolchain補助はユーザーの指示により取り除きました。

macOSランチャーはApple Siliconを確認し、同梱Perlを絶対パスで起動します。外部PERL5LIB / PERL5OPT等を解除し、ライブラリへの外部注入・環境依存を避けます。Intel Macではエラーにし、システムPerlへ切り替えません。最低OSのビルド設定は11.0ですが、実測した最低対応OS版を意味しません。[判断記録](adr/0002-bundled-exiftool.md)

## 準備とZIP生成

開発者側にはNode.js 20以上、Python 3.9以上が必要です。macOSのPerlビルドにはApple Silicon MacとApple Command Line Toolsが必要です。ユーザー側にはこれらの開発ツールは不要です。

```sh
node scripts/prepare-exiftool.mjs --platform all --jobs 4
node scripts/package.mjs --platform all
```

Windows同梱物の取得・ZIP生成はmacOS上で実行できます。対象OSだけなら`--platform windows`または`--platform macos`を指定します。macOS ZIPはApple Silicon専用です。Intel用・universal用の生成オプションは提供しません。

キャッシュ取得後は準備に`--offline`を追加できます。ハッシュ不一致のキャッシュを暗黙に置換しません。準備済みファイルが欠落・変更された場合も再取得・梱包せず停止します。原因を調べ、不要と判断した該当キャッシュを手動で除去してから再準備します。Perlの標準テストは`make test_harness`を使い、失敗すると同梱物を公開しません。制限環境でのローカルIPC/ソケット失敗は通常環境で再検証します。

生成名はInfo.luaのmajor.minor.revisionから取ります。

```text
dist/fuji-photo-renamer-lightroom-plugin-0.9.1-windows.zip
dist/fuji-photo-renamer-lightroom-plugin-0.9.1-macos.zip
```

同名生成物は上書き拒否です。ZIPと`.sha256`を生成し、内部は`FujiPhotoRenamer.lrplugin/`だけです。プラグイン本体、対象OSの依存、原版ライセンス、INSTALL、全ファイルのSHA-256/実行権限を記録したPACKAGE_MANIFESTを含みます。tests・fixtures・開発キャッシュ・Adobe SDKは含みません。同じ準備済みファイルを同じPython/zlib版でZIP化すると、ソート順・日時・権限を固定した同じバイト列になります。Perl自体の再ビルドで同一バイトになる保証はしません。

## インストールとLightroom手動確認

1. ZIPを解凍し、生成された`.lrplugin`を任意の場所へ置く。ソース側の`src/`には同梱物がないため、配布検証は解凍した側を使う。
2. Lightroom Classicの「ファイル → プラグインマネージャー → 追加」でそのフォルダーを選び、`0.9.1.22`を確認する。
3. 書き出し設定のExifToolパスを空欄にする。古いプリセットの開発用パスも消す。
4. 複製素材でプレビュー、書き出し、衝突、前回設定、C2PA ON/OFFを確認する。元画像と既存出力は同じパスで前後ハッシュ比較する。
5. 日本語・空白を含む設置先、書き込み不可の設置先、外部ExifTool/Perlがない環境で確認する。

署名・公証を済ませた一般公開版ではありません。隔離属性・Gatekeeperの挙動は別の検証項目です。OSの保護設定を一律に解除する手順は案内しません。

## 自動確認と残課題

```sh
node --test tests/packaging_test.mjs
python3 tests/archive_test.py
python3 tests/run_tests_test.py
python3 tests/package_native_test.py dist/fuji-photo-renamer-lightroom-plugin-0.9.1-macos.zip dist/fuji-photo-renamer-lightroom-plugin-0.9.1-windows.zip
```

Nodeテストは固定ハッシュ、破損/欠落キャッシュ、HTTP失敗、OS選択、必要ファイル、実行失敗、同梱ランチャーの環境分離を確認します。Pythonテストは展開先逸脱、リンク・重複の拒否、原版バイト・権限、ZIPの再現性と上書き拒否を確認します。ランチャー等のネイティブ部分はmacOSで実行します。配布物を解凍した同梱ツールでも既存Lua回帰を実施します。

Windows実機、クリーン環境、Lightroomからの同梱起動、署名/公証、実測した最低OS、Windows依存の保守状況には確認事項が残ります。Intel Macは対象外です。技術検証6全体の合格・製品リリース完了とは区別し、検証結果を追記してPhase 12の結果報告後は停止します。

## 実行結果（2026-10-11）

macOS 27.0.1 / arm64、CLT clang 21.0.0、Node.js 24.4.1、Python 3.9.6、Lua 5.1.5で確認しました。

- Perl標準テスト：2939ファイル・1,379,419テスト、PASS。ソースは原版、CODESET用の公式コンパイルフラグを追加。最初の失敗後、ライセンス収集時にビルド生成リンクを対象外とする修正を行い、同じ合格済みビルドから同梱物を組み立てました。
- 同梱Perlの版・arm64形式・再配置後の@INC・全Mach-OのOSライブラリだけの動的依存を確認。
- Node配布テスト17件、Pythonアーカイブ8件、既存実行補助14件、実ZIPネイティブ6件が成功。
- 同梱ExifTool 13.59で既存Lua回帰622件（seed=12）が成功。解凍したプラグインをロードし、外部ExifToolパスを空欄にしたSDK境界の全体処理8件も成功。
- 固定URLの3アーカイブをNodeの実オンライン経路でも取得し、公開SHA-256との一致を確認。ZIPの全ファイル・実行権限・manifest・SHA-256も確認。Windows実行ファイルは公式ZIPの原版バイト列と一致し、同梱依存のライセンスZIPも保持。
- 日本語・空白・引用符を含む移動先、PATHにツールがない状態、外部Perl設定、書き込み不可のプラグイン全体でmacOSの起動・読取を確認。合成JUMBFの削除は画像の残り全バイト・入力不変を確認。

macOS ZIPは約22 MiB、Windows ZIPは約11 MiBです。準備済みキャッシュを再検証し、既存ZIPの再生成は拒否しました。Lightroom実機・OSの隔離属性・Windows実行はこの結果に含みません。

## Gatekeeperによる起動拒否（2026-10-11）

ユーザーのLightroom書き出しで、同梱`perl`について「Appleはマルウェアが含まれていないことを検証できませんでした」と表示され、起動を拒否されたと報告がありました。配布元バイナリの署名はリンカー生成のad-hoc署名で、Developer ID・TeamIdentifier・公証はありません。開発環境の有効な署名用IDも0件でした。CLIテスト成功をGatekeeper通過とは扱いません。

この開発検証版を信頼して実行する場合は、[Appleの個別許可手順](https://support.apple.com/ja-jp/102445)に従い、警告後に「システム設定 → プライバシーとセキュリティ」の`perl`の項目から「このまま開く」を選び、確認・認証後に書き出しを再試行します。Mac全体のGatekeeper無効化や自動的な隔離属性削除は行いません。

一般配布でこの個別許可を不要にするには、[Developer ID署名とAppleの公証](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)が必要です。有効な証明書・公証用認証情報がない現段階では完了していません。個別許可後のLightroom動作も結果待ちです。

## 明示的なad-hoc署名（2026-10-23）

ユーザー指示により`0.9.2.23`から、macOSのPerlとネイティブモジュールをパッケージ組立時にad-hoc署名します。[Appleの署名要件資料](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)にある疑似ID`-`を使い、タイムスタンプは付けません。既存のリンカー署名を置き換えて明示的な識別子を付け、全対象を`codesign --verify --strict`で検証します。[Appleの指針](https://developer.apple.com/library/archive/technotes/tn2206/)に従い`--deep`の一括署名を避けます。

`scripts/sign-macos.mjs`がMach-Oヘッダーから署名対象を検出します。署名・検証失敗時はZIPを公開しません。manifestは署名後のハッシュと、`macosSigning: {type: "ad-hoc", identity: "-", notarized: false, files: [...]}`を記録します。元の準備キャッシュの検証ハッシュは変えず、Windowsバイナリにも手を加えません。

Gatekeeperの個別許可は引き続き必要になる場合があります。信頼設定・隔離属性の自動変更、証明書作成、公証は行いません。Node配布テスト20件、署名検証を含む実ZIPテスト7件が成功。解凍後の全ネイティブコードでad-hoc署名と厳密検証、JPEG/XMP取得・JUMBF削除・移動先/読取専用設置先の起動を確認しました。準備済みキャッシュも再検証済みです。

今回のSDK境界8件の再実行は、以前の`/tmp`のLua 5.1実行環境が消失しているため未実施です。2026-10-11の成功記録とは区別し、プラグインのロジックはバージョン以外変更していません。新しいZIPは`dist/fuji-photo-renamer-lightroom-plugin-0.9.2-macos.zip`と`-windows.zip`です。旧ZIPは保持します。
