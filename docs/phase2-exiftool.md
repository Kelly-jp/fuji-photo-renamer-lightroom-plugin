# Phase 2：ExifTool 単体連携

## 状態と範囲

2026-10-08、ユーザーの「次のフェーズに移行」という指示により開始しました。Phase 1 の macOS 基本保存、同名時非上書き、元 RAW / XMP のチェックサム不変は確認報告済みです。Windows 等の残課題は継続し、全プラットフォーム検証完了とはみなしません。

`infrastructure/ExifTool.lua` に読み取り専用ラッパーを実装しました。書き出し処理、テンプレート、入力探索、項目単位マージ、メーカー正規化、C2PA 削除には統合しません。Phase 3 以降は未着手です。

## API と戻り値

SDK の task 内で、検証メニューから絶対パスの loadfile で ExifToolLoader を読み込み、プラグインパス・SDK namespace・OS を引数として渡します。ExifToolLoader が JSON と infrastructure 本体を同じ方法で読み込みます。SDK の require による名前検索には依存しません。

```lua
local result, readError = ExifTool.readMetadata(inputPath, {
    executablePath = absoluteExifToolPath, -- 検証時のみ明示指定
    timeoutSeconds = 30,                  -- 1〜120 秒の整数
})
```

実行ファイル指定を省略すると `_PLUGIN.path` の `vendor/windows/exiftool.exe` または `vendor/macos/exiftool` を参照します。存在しなければ `ExecutableMissing` を返し、PATH や Homebrew を黙って検索しません。ExifTool 本体の同梱はまだ未実施です。

成功時の `result`:

- `metadata`: captureDateTime、cameraMaker、camera、lensMaker、lens、filmSim、iso、focalLength。取得不能は nil。
- `fieldSources`: 項目ごとの sourceKind（raw / jpeg / xmp）、sourcePath、取得した tag。
- `rawTags`: 調査用の ExifTool グループ付き生タグ。core や将来の TokenResolver には渡さない。
- `missingFields` / `warnings`: 欠落項目と診断。警告を握りつぶさない。
- `toolVersion` / `exitCode`: 実際の取得ツールのバージョンと終了コード。

失敗時は `nil, { code, message, exitCode?, shellCode?, stderr?, cleanupWarnings? }` を返します。終了コード非ゼロ、時間超過、破損 JSON、取得元不一致、出力過大等を区別します。

## 実行・安全設計

1. 入力は読み取り可能な単一の RAF / DNG / JPG / JPEG / XMP。絶対パスを要求し、改行・NUL を拒否する。フォルダー・再帰探索・任意オプションは受け付けない。
2. SDK の一時領域に専用フォルダーを新規作成し、SDK の created フラグで所有を確認する。
3. UTF-8 引数ファイルに固定の読み取りオプションと `--` に続く写真パスを書く。写真パスをシェルコマンドへ連結しない。
4. `-config ''` を先頭に置いて利用者設定ファイルを無効にし、`-charset filename=UTF8` を `-@` より前に指定する。
5. `LrTasks.execute` で OS 別の小さな runner を起動し、stdout / stderr / 実終了コードを専用ファイルへ取得する。SDK の OS wait status とツールの終了コードを混同しない。
6. JSON / stderr の読み込み上限はそれぞれ 1 MiB。単一の JSON オブジェクト配列、SourceFile 一致、Error 不在を確認する。
7. 終了が確認できたときだけ、所有する固定名の一時ファイルを清掃する。未知のファイルがあるフォルダーは再帰削除しない。

macOS は POSIX の単一引用符で実行パスを引用し、内部の引用符もエスケープします。固定 shell runner が期限に達した ExifTool PID を TERM、必要なら KILL で停止します。macOS の実行エントリーは ExifTool 本体、または本体を exec するランチャーを前提とします。独自に子プロセスを増やすランチャーは検証対象外です。

Windows は引用済みパスで PowerShell runner を起動します。cmd.exe が引用符内でも展開する `%` / `!` / `^`、引用符、末尾区切りを実行用パスで拒否します。写真パスは別の UTF-8 引数ファイルなので、これらの文字を一律に禁止しません。PowerShell の Bypass は当該プロセスだけに指定し、システムの実行ポリシーは変更しません。標準出力と標準エラーを非同期に読み、期限後は taskkill の `/T /F` で対象プロセスツリーを停止します。

SDK 実行中の例外や runner の不完全終了でプロセス状態を確認できない場合は、作業ファイルを残して失敗・清掃診断を返します。元写真、XMP、既存の書き出しファイルへ書き込み・移動・削除する処理はありません。読み取り引数にはメタデータ書き込みオプションやバックアップ作成を含めません。

## 確認したタグ対応

固定引数は `-j -G1 -s -n` と必要項目のタグ指定です。`-n` で ISO・焦点距離・FilmMode 等を数値として取得します。タググループを保持し、同名のタグを混同しません。

| 内部項目 | RAW / JPEG | XMP |
| --- | --- | --- |
| captureDateTime | ExifIFD:DateTimeOriginal | XMP-exif:DateTimeOriginal |
| cameraMaker | IFD0:Make | XMP-tiff:Make |
| camera | IFD0:Model | XMP-tiff:Model |
| lensMaker | ExifIFD:LensMake | XMP-exifEX:LensMake |
| lens | ExifIFD:LensModel | XMP-exifEX:LensModel |
| iso | ExifIFD:ISO | XMP-exif:ISO |
| focalLength | ExifIFD:FocalLength | XMP-exif:FocalLength |
| filmSim | FujiFilm:FilmMode / FujiFilm:Saturation | XMP-crs:LookName → CameraProfile → CameraProfilesProfileName の既知名 |

日時は ExifTool が返した撮影日時文字列を保持し、暦やトークン用書式の処理は後続 Phase で行います。メーカーの文字列は変更せず、比較正規化は Phase 5 へ残します。数値項目には正の有限値を要求し、ISO は整数のみとします。単一要素の XMP 配列はスカラーとして扱い、複数要素は推定選択しません。

FilmSim は確認済みのコード対応だけを行います。白黒・ACROS は Saturation を優先し、それ以外は FilmMode を使います。FilmMode = 0 は有効な PROVIA です。未知コードは nil と診断にし、LensMake 欠落時もカメラメーカーから推定しません。レンズ ID の推測解決はしません。XMP の編集プロファイルは、今回確認した既知名の対応表に一致する場合だけ FilmSim として採用します。未知名の部分一致による推定はしません。

## 実データ・自動テスト結果

ExifTool **13.55**、Lua **5.1.5（POSIX 対応ビルド）**、macOS 上で実施しました。Lightroom SDK の代わりにテスト用 I/O adapter を使った結果であり、Lightroom 内での起動確認とは区別します。

ユーザーが許諾した X-H2S の RAF 1 ファイルで、以下を実際のラッパー経由で取得しました。

| 項目 | 取得結果 |
| --- | --- |
| CameraMaker | FUJIFILM |
| Camera | X-H2S |
| LensMaker | FUJIFILM |
| Lens | XF200mmF2 R LM OIS WR + 1.4x F2 |
| FilmSim | PROVIA（FilmMode = 0、Saturation = 384） |
| ISO / FocalLength | 160 / 280 mm |

DateTimeOriginal も取得できましたが、個人の撮影日時と絶対パスはリポジトリに記録しません。読み取り前後の RAF の SHA-256 一致を確認しました。画像本体はコピー・コミットしていません。

- Phase 2：**83 件成功**。実プロセスの非ゼロ終了、破損 JSON、時間超過、JSON 内 Error、stderr、特殊文字・日本語パスを含む。
- 合成 JPEG / XMP を実際の ExifTool で読み取り、入力バイト列不変を確認。
- Phase 1 の回帰テスト：**66 件成功**。
- Lua 5.1 構文、shell 構文、差分を確認。PowerShell runner は実行していない。

```sh
lua tests/integration/phase1_provider_test.lua
lua tests/integration/exiftool_read_test.lua /absolute/path/to/exiftool /absolute/path/to/test-copy.RAF /absolute/path/to/test-copy.xmp
```

実 ExifTool のパスを省略した場合は実ツール読み取りをスキップします。RAF 引数を省略した場合は個人素材を探さず、合成データだけを使います。テスト結果の件数は有効にした実データケースで変わります。

## Lightroom Classic での手動確認

1. プラグインマネージャーでプラグインを再読み込みする。表示名「Fuji Photo Renamer — 開発検証版」、バージョン `0.1.5.6`、読み込み元がリポジトリの `src/FujiPhotoRenamer.lrplugin/` であることを確認する。
2. 「ファイル → プラグインエクストラ」（または「ライブラリ → プラグインエクストラ」）内の「メタデータ取得 / 入力ファイル探索を検証…」を開き、「ExifTool でメタデータ取得」を選ぶ。
3. 検証用 ExifTool 実行ファイルを選ぶ。今回の環境なら `/opt/homebrew/bin/exiftool`。選択画面の ⌘⇧G で親フォルダーを指定できる。
4. 検証用 RAW / JPG / XMP を 1 ファイル選び、表示された 8 項目、欠落・警告を確認する。
5. 不正な実行ファイル、破損入力、取消時に誤って成功表示されないことを確認する。
6. 入力のチェックサム不変を確認する。既存の Phase 1 書き出しは引き続き固定名であり、ExifTool と未統合であることを確認する。

## 残課題と次 Phase の判定

- ユーザーから XMP の診断結果が表示され、FilmSim のみ未取得だったとの報告あり。診断の起動経路は確認報告済み。2026-10-09、同じ XMP で修正後の FilmSim 取得成功の報告あり。エージェント自身による Lightroom 操作は未実施。
- Windows runner の構文・実プロセス・UTF-8 パス・タイムアウト・プロセス停止は未検証。特に Lua の io.open と SDK の UTF-8 パスの互換性が要確認。失敗時は明示的な I/O エラーにし、対応済みとしない。
- ExifTool と必要ランタイムの自己完結した同梱、署名・隔離属性、固定版ダウンロードは Phase 12 / 技術検証 6 に残す。Homebrew 版での今回の成功は自己完結配布の証明ではない。
- 他機種 RAF、他レンズ、DNG の MakerNotes、未確認の XMP プロファイル名は未検証。1 ファイルの成功を全機種対応へ一般化しない。
- 処理中キャンセルの即時停止は未実装。単体呼び出しは期限まで待つ。書き出し統合前にキャンセル方針を決める。

**Phase 2 の実装・macOS ネイティブ単体検証は完了。Lightroom 内の診断表示はユーザー報告済みで、修正後の XMP FilmSim 取得もユーザー報告で確認済みです。Windows の成立性は確認待ちです。Phase 3 へは自動で進みません。**

## 依存と公式根拠

JSON ライブラリは純 Lua の **dkjson 2.11、25,009 bytes、MIT** を採用。Lua 5.1 対応、追加依存不要、現行版の不正入力に関する修正状況を確認してから追加しました。ソースは改変せず、公式 SHA-256 `197cb50834c642f84b4cf99fe724932c50e6d9c92faec7ad89aa25e91df4d481` と照合済みです。`third_party/dependencies.json` へ固定版・URL・ハッシュを、`THIRD_PARTY_NOTICES/dkjson-LICENSE.txt` へライセンスを保存します。

- [ExifTool CLI](https://exiftool.org/exiftool_pod2.html)：JSON、グループ、数値変換、引数ファイル、設定無効化、ファイル名文字コード、終了コード。
- [ExifTool FujiFilm タグ](https://exiftool.org/TagNames/FujiFilm.html) と実環境の 13.55 `FujiFilm.pm`：FilmMode / Saturation のコード。名前・タググループは実取得で照合。
- [dkjson 公式配布・更新履歴](https://dkolf.de/dkjson-lua/)、[公式ハッシュ](https://dkolf.de/downloads)、[ドキュメント・ライセンス](https://dkolf.de/dkjson-lua/documentation)。
- SDK 根拠は [Phase 1 の資料](phase1-lightroom.md#参照資料の出典)。Guide p.19–20 の require、p.34 の Library Menu、LrTasks / LrFileUtils / LrPathUtils の参照を使用。
- [Microsoft Process.StandardOutput](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardoutput)、[WaitForExit](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.waitforexit)、[taskkill](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/taskkill)：ストリーム排出とプロセス停止。

## メニュー未表示の切り分け

ユーザーからメニュー未表示の報告がありました。初期実装は `LrLibraryMenuItems` のみで、File メニューの同名サブメニューには登録していませんでした。SDK Guide p.34–35 の登録先の違いを確認し、同じ項目を `LrExportMenuItems` と `LrLibraryMenuItems` の両方へ登録しました。写真選択を要求する enabledWhen は指定しません。メニュー追加は書き出し処理を変更しません。

どちらのメニューでも出ない場合、原因を File / Library の違いと断定せず、読み込み元、無効状態、Info.lua の読み込みエラー、古い版の保持を確認します。まずプラグインマネージャーの「プラグイン作成者ツール」で再読み込みし、`0.1.5.6` が表示されるかを確認してください。変わらなければ Lightroom を再起動し、それでも変わらなければ該当プラグインをマネージャーから削除・同じソースフォルダーを追加して確認します（写真やカタログを削除する操作ではありません）。その後ユーザーから診断結果の表示と FilmSim 取得成功の報告があり、メニュー起動経路の解消を確認しています。

## require の命名エラーの修正

実機で `require: invalid characters in script name` が報告されました。初期実装の `require 'infrastructure/ExifTool.lua'` と `require 'third_party/dkjson.lua'` は Lightroom の制約に適合せず、サブフォルダー名を許したテスト adapter もこの誤りを検出できていませんでした。

ルートの `ExifToolLoader.lua` を `require 'ExifToolLoader'` で読み込み、SDK が使用可能と明記する `loadfile`（Guide p.18）で固定パスの infrastructure 本体を読み込みます。SDK で使用できない getfenv / setfenv は使わず、SDK namespace・プラグインパス・OS・JSON を初期化時の引数として明示的に渡します。汎用ローダーや任意ファイルの読み込み UI は追加しません。

dkjson はルートの `dkjson.lua` へ移し、`require 'dkjson'` で取得します。原版のバイト列・ハッシュ・ライセンスは変更せず、manifest の配置パスだけを更新しました。テスト adapter はサブディレクトリ名・通常 Lua のドット付きモジュール名を拒否し、ルート名の読込と拒否動作を回帰テストへ追加しました。

読み込み版は `0.1.5.6`。新規ルートファイルが追加されているため、プラグインを再読み込みし、ファイル一覧の保持による読込エラーが続く場合は Lightroom Classic を再起動してください。その後の絶対パス読み込み修正と XMP タグ対応により、ユーザーから Lightroom 内の取得成功が報告されています。

## ExifToolLoader の名前検索エラーの修正

続いて `Could not load toolkit script: ExifToolLoader` が実機で報告されました。ファイル自体の存在は確認できましたが、拡張子補完・スクリプト名の解釈・読み込み済みファイル一覧のどれが実機原因かは断定していません。検証メニューから loader、JSON、infrastructure 本体を、すべて明示した絶対パスで loadfile する方式へ変更しました。前節の require を使った入口はこの変更で置き換えています。

読み込みを task 内の保護呼び出しに移し、SDK の内部エラーのまま終了させず、失敗したファイルパスと読み込み理由を表示します。SDK 名前検索が新規スクリプトを一切見つけられない状況でも、検証メニューが実行ファイルの選択画面へ到達する回帰テストを追加しました。テスト adapter の暗黙の .lua 補完も除去しました。修正版は `0.1.5.6`。その後ユーザーから XMP 診断結果の表示と FilmSim 取得成功が報告されています。

## XMP FilmSim の修正（2026-10-09）

ユーザーの参考リポジトリ [fphoto-renamer の xmp_reader.rs](https://github.com/Kelly-jp/fphoto-renamer/blob/develop/crates/core/src/xmp_reader.rs) と [exif_reader.rs](https://github.com/Kelly-jp/fphoto-renamer/blob/develop/crates/core/src/exif_reader.rs) を確認しました。ローカル参照版は `06df2ac74eec2e3b33155234dab72cb78b8c43df`。Rust 側は CRS の Look 名や CameraProfile から FilmSim を採用します。元のプラグインではこれらを要求も解決もしていなかったことが差分でした。

許諾された実 XMP の `XMP-crs:CameraProfile = Camera PROVIA/Standard` を ExifTool 13.55 で確認し、ラッパー経由で PROVIA を取得しました。RAW / XMP の前後 SHA-256 が一致しています。個人素材のパス・撮影日時・編集内容はフィクスチャにコピーしていません。

XMP の優先順位は、既知の LookName → CameraProfile → CameraProfilesProfileName → 取得できる MakerNotes のコードです。Look の構造内 Name も ExifTool が出す LookName で取得できることを合成 sidecar で確認しました。RAW / JPEG は従来の MakerNotes を優先し、コードが取得できない場合だけ既知プロファイルを使います。採用元のタグを fieldSources に保持します。

Camera 接頭辞、空白、明示した末尾 v2 等の数値バージョンを整理した後、明示的な別名表で完全一致比較します。PROVIA/Standard、Velvia/Vivid、ASTIA/Soft、CLASSIC Neg、REALA ACE v2、ACROS のフィルター等を既存の内部名へ対応させます。Adobe Color、Adobe Standard、未知のカスタム名は nil と診断にします。複数プロファイル名から勝手に一つを選びません。

参考アプリの任意の未知名採用、撮影日時欠落時の CreateDate / 更新日時への代用、独自 XML パーサー、ExifTool 以外の EXIF ライブラリへのフォールバックは採用していません。既存の安全・欠落仕様を維持し、XML の解析は ExifTool に任せます。複数ファイルの XMP → RAW → JPG マージは Phase 4 のままです。

これは現像で選択された既知の編集プロファイルの解釈であり、元 RAW の撮影時設定を書き換えたり、両者が常に同じと保証するものではありません。修正版は `0.1.5.6`。2026-10-09、ユーザーが同じ XMP を選択し FilmSim の値を取得できたことを報告しました。

## macOS の手動確認報告（2026-10-09）

ユーザーが Lightroom Classic の診断メニューで、問題が起きたものと同じ XMP を再選択し、FilmSim の値を取得できたことを報告しました。これにより、診断メニュー起動、依存モジュールの読み込み、ExifTool による XMP 読み取り、修正後の FilmSim 表示をユーザー報告として確認しています。表示文字列や OS / Classic の詳細バージョンは今回の報告には添付されていません。

エージェントが確認済みの同ファイルの PROVIA 取得・SHA-256 不変と、ユーザーの Lightroom 内での取得成功は別の証拠として扱います。Windows、別機種、他の編集プロファイル、Lightroom 内の異常終了・時間超過等の未確認項目は継続します。Phase 3 は新たな指示を受けるまで開始しません。
