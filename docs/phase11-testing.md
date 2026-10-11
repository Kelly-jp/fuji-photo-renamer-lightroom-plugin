# Phase 11：自動テストと手動Integration Test

## 範囲と結果

2026-10-11、Phase 10までの機能を現行仕様へ照合しました。製品Luaコード・SDK API・プラグインバージョンは変更せず、`0.9.0.21`を維持します。外部テストフレームワーク、配布バイナリ、ダウンロード・ZIP生成は追加していません。

- 純core：264件、SDK境界：235件、実ExifToolを使うmacOS結合：123件。合計622件、17ファイルが成功。
- 43 Luaファイルの構文チェックと、実行補助のPython標準unittest14件が成功。
- テストファイルの順序をseed=11で入れ替え、別プロセスで実行。ネットワーク・現在日時・個人写真を使用しない。
- 実ExifTool全体経路の衝突ケースは、そのケース内で既存出力を作成し、前のケースの出力への依存を除去。
- 許諾済み実JPEG削除の任意ケースは今回の件数に含めない。以前の成功結果は[Phase 10](phase10-c2pa.md)に記録。

数値カバレッジの閾値は設けません。以下の振る舞いと、元画像保護・失敗を成功扱いしないことを確認基準にします。自動テスト成功は実LightroomのSDK・OS・競合動作の証明ではありません。

自動実行環境：macOS 27.0.1 / arm64、Lua / luac 5.1.5、ExifTool 13.55、Python 3.9.6。SDK境界は既存ダブルで、新しいSDK APIは使用していません。SDK出典は[Phase 1](phase1-lightroom.md#参照資料の出典)を参照してください。

## 必須ケースの対応表

表のファイルは`tests/`からの相対パスです。TemplateParser / TokenResolver、FilenameSanitizer / CollisionResolverはそれぞれ共通のテストファイルで連携も確認します。

| ケース | 自動テストと確認内容 |
| --- | --- |
| XMPのみ・RAWのみ・JPGのみ | `core/metadata_resolver_test.lua`、`integration/metadata_reader_test.lua`：値・採用元・呼出し対象 |
| XMP + RAW + JPG | 同上：ファイル単位にせず項目別に統合、入力不変 |
| XMP欠落→RAW、RAW欠落→JPG | 同上：nil・空文字・空白、不正型を区別。読取失敗ではフォールバックしない |
| RAW同階層・親階層・same_then_parent | `integration/metadata_source_resolver_test.lua`と`metadata_source_resolver_native_test.lua`：探索・同階層優先・nil・曖昧性 |
| RAF・DNG・拡張子大小文字 | 同上：RAF/raf/RaF、DNG/dng/dNg、元RAW直接採用。RAW実デコードは別の任意検証 |
| 同一メーカー・異メーカー | `core/manufacturer_normalizer_test.lua`：FUJIFILM別名、TAMRON/SIGMA、未知メーカー、入力不変 |
| メーカー省略ON/OFF | `core/template_engine_test.lua`、`integration/export_pipeline_test.lua`：LensMakerの意味で省略、LensMakerのみは保持 |
| 現行9トークン・不明トークン | `core/template_engine_test.lua`：全トークン、構文、エスケープ、不明・廃止トークン拒否 |
| 空メタデータ | 同上とMetadataResolver：任意値は空欄、必須日時はエラー、空名拒否 |
| 禁止文字・制御文字・予約名 | `core/filename_safety_test.lua`：置換・除去、UTF-8、長さ、Windows予約名 |
| 同名ファイル・連番 | 同上と`integration/export_pipeline_test.lua`：通常名→_001→_002、セッション予約・既存出力保持 |
| Sequence廃止 | `core/template_engine_test.lua`、`integration/export_dialog_test.lua`：トークン拒否と旧末尾設定移行。番号は衝突回避のみ |
| 自動拡張子・ISO/FocalLength廃止 | 同上：実JPEG拡張子の付加、旧Extension末尾移行、不対応トークン拒否 |
| トークン値の空白・FilmSim表示 | `core/template_engine_test.lua`：大小文字・リテラル保持、既知FilmSim表示 |
| C2PA削除ON/OFF・不在・失敗 | `integration/c2pa_native_test.lua`、`export_pipeline_test.lua`と`export_pipeline_native_test.lua`：限定削除・警告・終了コード・タイムアウト・取消 |
| 画像・EXIF/XMP/ICC保持 | `core/jpeg_integrity_test.lua`：全非JUMBFバイト保持、変更拒否。合成APP内容のテストで、タグ意味や色の実表示は手動で確認 |
| 元RAW/JPG/XMP・所有外の保護 | `integration/export_artifact_test.lua`：由来、別名参照、処理中変更、清掃拒否、削除失敗。パス解決はSDKダブル |
| UI・プリセット・プレビュー | `integration/export_dialog_test.lua`と`export_preview_test.lua`：設定復元、空選択、非同期の古い結果破棄 |
| 前回設定・保存失敗 | `integration/phase1_provider_test.lua`と`export_pipeline_test.lua`：保存先復元、衝突、部分出力、C2PA後の転送失敗を報告 |

## 実行方法

開発用にPython 3とLua / luac 5.1を用意します。実ExifTool結合はmacOSのみです。リポジトリルートで実行します。

```sh
python3 scripts/run-tests.py --exiftool /absolute/path/to/exiftool --shuffle-seed 11
python3 tests/run_tests_test.py
```

`--lua`と`--luac`で実行ファイルを指定できます。`--suite core` / `--suite sdk`はExifTool不要、`--suite native` / 既定`all`は明示した絶対パスが必須です。nativeを実行できない環境では黙ってスキップせず終了します。SDKスイートをWindowsで実行してもLightroom実機確認とは呼びません。

新規Luaテストは`scripts/run-tests.py`のSUITESへ登録します。Pythonテストが一覧の漏れを検出します。各Luaファイルの非ゼロ終了、成功要約の欠落、時間超過を失敗として集計し、残りも実行します。依存不足・構文エラーは事前に停止します。タイムアウトしたプロセスの未知の作業ディレクトリを一括削除しません。製品runnerの停止確認・清掃制限はネイティブテストと別に維持します。

## Lightroom手動Integration Test（macOS）

専用カタログへ複製素材を登録し、プラグインを再読み込みします。実行補助はLightroomを操作せず、元画像の編集・移動・メタデータ保存も行いません。OS / CPU、Classic・プラグイン・ExifToolのバージョン、設定、期待値と結果を個人情報を除いて記録します。

1. **元画像・既存出力の不変**：複製したRAW/JPG/XMPと、書き出し前から存在する出力を対象に前後を比較する。別々に生成したJPEG同士を比較しない。写真の現像変更やメタデータ保存は比較の途中で行わない。

   ```sh
   shasum -a 256 "/absolute/path/source.RAF" "/absolute/path/source.jpg" "/absolute/path/source.xmp" "/absolute/path/existing-output.jpg" > /tmp/fuji-phase11-before.sha256
   # OFF / ONの書き出しを実行後、同じファイルを照合
   shasum -a 256 -c /tmp/fuji-phase11-before.sha256
   ```

   存在する複製ファイルだけを列挙する。すべて`OK`が期待結果。新規出力・日時・文書IDの差は元画像変更と区別する。
2. **保存先と衝突**：特定フォルダー、元写真と同じフォルダー、サブフォルダーで確認。同じ写真を3回出力すると`name.jpg`、`name_001.jpg`、`name_002.jpg`だけが増え、以前の出力は不変。「前回の設定で書き出し」で余分な元名JPEGが増えない。
3. **禁止文字**：素材名を変更せず、テンプレートに`test:{Original}`を指定する。プレビュー・保存名は`test_<元名>.jpg`。元RAW/JPG/XMPは変更されない。不明トークン`{Unknown}`はエラーで書き出しを止める。
4. **メタデータ・メーカー**：探索モードと関連XMP/RAW/JPGの配置を変え、診断で採用元を確認する。メーカー省略ON/OFFと、実画像で確認できない欠落・異メーカーは自動テストの結果と区別する。
5. **C2PA**：JUMBF入りのSDK出力でOFFは保持、ONは削除。`exiftool -JUMBF:all -Error -Warning output.jpg`と表示・色・画像内容を確認。署名が有効だったかは別の検証であり、JUMBF検出だけから推定しない。
6. **失敗と取消**：複製素材で無効なExifToolパス、オフライン元画像、複数枚処理のキャンセルを確認。失敗を成功扱いせず、完了済み出力と既存ファイルが残る。権限・別ボリューム・競合・リンクは環境を確保して個別に確認する。

## 判定と残課題

Phase 11の自動テスト整備は完了です。既存のmacOS手動結果は[Phase 9](phase9-export-integration.md)・[Phase 10](phase10-c2pa.md)に記録済みで、上記追加手順を実施済みとは扱いません。

今回の全経路の元画像・既存出力の前後ハッシュ、禁止文字の実保存、取消・異常系、別ボリューム・競合・リンク、複数機種のRAF/DNG、Windows実機には未確認項目があります。Windowsはユーザーの実機がないため環境確保まで保留です。自己完結配布はPhase 12の検証事項で、現段階を製品リリース合格とは呼びません。Phase 12へ進む前に次の指示を待ちます。

## ユーザーによる実行確認（2026-10-11）

Lua / luac 5.1とExifToolの絶対パスを明示した一括実行後、ユーザーから`622 cases passed; 17/17 test files passed.`の報告を受けました。自動テストの実行成功として記録し、Lightroom手動Integration Testの実施とは区別します。Python実行補助の14件については、開発時の成功結果のみで、ユーザーからの追加結果報告はありません。
