# Phase 8：Lightroom 書き出し設定 UI

## 実装と限定範囲

`ui/ExportDialog.lua` に設定・プレビュー・検証表示を分離し、ルートの ExportServiceProvider から呼びます。バージョンは `0.7.2.16`、書き出し先の表示名は「Fuji Photo Renamer — 開発検証版」です。

保存先は既存の標準「書き出し場所」を利用します。特定フォルダー、元写真と同じフォルダー、サブフォルダー等を維持し、二重の保存先設定は作りません。実書き出しは Phase 1 の `test_<元ファイル名>.jpg` のままです。元画像へ書き込みません。

## 設定とプリセット

| キー | 初期値 | 用途 |
| --- | --- | --- |
| fprTemplate | `{DateTime}_{Original}_{Sequence}` | 命名テンプレート |
| fprRawSearchMode | same_then_parent | JPG と同階層 / 親階層 / 同階層→親階層 |
| fprOmitDuplicateManufacturer | true | 同一メーカーの場合に LensMaker を省略 |
| fprRemoveC2pa | false | 新規書き出し JPEG の C2PA 削除設定 |

4 キーを `exportPresetFields` に宣言し、nil のときだけ初期化します。false や保存済み設定をリセットしません。標準保存先は Lightroom の組み込み設定で記憶します。候補名・エラー・監視用オブジェクトはプリセット対象に含めません。実際のプリセット保存・再起動後の復元は手動ゲートです。

## プレビューとエラー

TemplateParser → TokenResolver → FilenameSanitizer を UI でも使います。テンプレート入力は `immediate = true` とし、設定の observable table を監視して入力中に候補を更新します。メーカー省略の切り替えでも更新します。処理は小さな純 Lua 計算だけで、非同期タスク・ExifTool・写真探索は起動しません。

Phase 8 は取得できる写真情報がない場合にも表示できるサンプルプレビューに限定します。実写真と誤認しないよう日時・メーカー・カメラ・レンズ・FilmSim・ISO・焦点距離・元名・仮の Sequence を UI に明示します。RAW 探索方法は保存のみで、サンプル内容を変えません。実写真の読取・取得結果の固定・古い非同期結果の破棄は Phase 9 の統合時に検証します。衝突名・OS の長さ制限も未確定です。

不明トークン、不正構文、空名、予約名、不正な設定値は画面内へ理由を表示し、`LR_cantExportBecause` で書き出しを止めます。入力文字列は勝手に書き換えず、修正後は状態を解除します。C2PA 削除 ON も設定値は保持しますが、削除処理未実装のため書き出しを止めます。黙って OFF 相当で成功扱いしません。`updateExportSettings` でも検証し、UI を経由しない実行の拒否を確認しています。

endDialog で監視を解除し、再表示で重複登録しません。自身が設定した書き出し禁止理由だけを解除し、別の理由を消しません。

## SDK 確認資料と API

[Adobe 公式 Guide（2022）](https://ioconsolerykerprodcdn.azureedge.net/static/installers/lr/sdk/2022/cross_platform/v13/doc/Lightroom%20Classic%20SDK%20Guide_1655133965.pdf) の exportPresetFields 宣言を確認。今回の web ツールによる PDF 再取得は content-type エラーだったため、詳細は既存 Phase 1 と同じ固定コミットの Adobe 作成リファレンス・SDK サンプルで照合しました。[SDK 14.3 の固定スナップショット](https://github.com/mingchuno/lightroom-classic-sdk/tree/b3cbd46b716523eb2eb9cf230d440fbecc52e0e5)

| API / 定義 | 確認した Adobe 作成資料 |
| --- | --- |
| exportPresetFields / startDialog / endDialog / sectionsForTopOfDialog | API Reference/modules/SDK - Export service provider.html |
| LrView.bind / edit_field / checkbox / popup_menu / static_text / push_button / row | API Reference/modules/LrView.html |
| immediate | LrView.html / LrView edit view properties.html |
| addObserver(key, owner, callback) / removeObserver(key, owner) | LrObservableTable.html（owner を渡すと callback の第1引数になる） |
| LR_cantExportBecause | Sample Plugins/ftp_upload.lrdevplugin/FtpUploadExportDialogSections.lua の updateExportStatus、FlickrExportServiceProvider.lua |
| loadfile と明示依存の受け渡し | 既存 Phase 2 / 3 の SDK 名前検索回避方式 |

ミラーは Adobe 配信サイトではなく、公式 ZIP との同一性は未確認です。サンプルの転載・SDK 配布物のコミットは行いません。今回の codeload ZIP の SHA-256 は `c18c5fe9b8dfd65e140b81cbc8c7af7c424c5057d931d8c8568f2546cafd0e04`。これは固定コミットの今回の取得物識別用で、以前の取得 ZIP のハッシュとは区別します。

## macOS 手動検証

1. プラグインマネージャーでリポジトリの `.lrplugin` を再読み込みし、バージョン `0.7.2.16` を確認する。書き出し画面を開き直す。
2. 書き出し先「Fuji Photo Renamer — 開発検証版」を選ぶ。独自設定と標準「書き出し場所」が表示されることを確認する。
3. テンプレートを `{CameraMaker}_{Camera}_{LensMaker}_{Original}` に変更し、サンプル候補が即時更新されることを確認する。メーカー省略 ON は `FUJIFILM_X-H2S_DSCF1234.jpg`、OFF は `FUJIFILM_X-H2S_FUJIFILM_DSCF1234.jpg`。
4. `{Unknown}` や閉じない括弧を入力し、理由と書き出し不可の状態を確認する。正常なテンプレートに戻して解除を確認する。
5. RAW 探索の3選択肢とメーカー省略を変更して書き出しプリセットを作る。他の設定へ変更後、プリセットを再適用して復元を確認する。画面を閉じて再度開く操作も確認する。
6. C2PA 削除を ON にして理由と書き出し不可を確認する。ON のプリセットも保存・復元でき、勝手に OFF にならないことを確認する。実書き出し検証は OFF に戻す。
7. 標準保存先で「元の写真と同じフォルダー」＋サブフォルダーを指定し、複製した素材を使って従来の `test_<元名>.jpg` が保存されることを確認する。候補名では保存されない。同名時は従来どおりエラー。
8. 別の書き出し先へ切り替えた際に、このプラグインの禁止理由が残らないことを確認する。元 RAW / JPG / XMP の SHA-256 を前後比較する。

## 検証結果と残課題

SDK 境界テスト `tests/integration/export_dialog_test.lua` 31 件が成功。既定値・復元用宣言、入力時更新、ON/OFF、不正設定、C2PA ON の拒否、監視の終了・再表示、UI 制約、プログラム経由の検証を確認しました。SDK ダブルの結果であり、実際の画面描画・プリセット保存の証明ではありません。

Lightroom 内の macOS / Windows 表示、長文の折り返し・スクロール、macOS 入力中の通知、プリセット保存・復元・再起動は未検証です。実写真のプレビュー、書き出し名への適用と実連番・衝突確定、C2PA 削除は後続 Phase の範囲です。Phase 9 には進まず、手動確認報告と次の指示を待ちます。

## 手動確認と追加改善（2026-10-09）

ユーザーが初回 UI の基本動作を良好と報告しました。その後の指示により Extension トークンを廃止し、12 個のトークンボタンを追加しました。クリックすると末尾へ追加します。区切りの _ / - は入力欄で編集します。カーソル位置への挿入 API は推測して使用しません。旧プリセット末尾の `.{Extension}` は読み込み・再適用時に移行します。それ以外の位置はエラー、エスケープされた文字列は保持します。

ボタン追加・移行は SDK 境界テストで確認済み、実機では未確認です。0.7.2.16 を再読み込みし、12 個のボタンのクリック、拡張子未指定でも .jpg が付くこと、旧プリセットの再適用を確認してください。実保存への統合は引き続き未実装です。

## キャレット挿入の調査とトークン整理

SDK 14.3 の Adobe 作成リファレンス LrView.html、LrView edit view properties.html、LrView control view properties.html を調査しました。標準 edit_field にキャレット位置・選択範囲を取得または指定する公開 API は確認できませんでした。標準 SDK の範囲では位置挿入を実装せず、末尾追加を維持します。OS のキー入力自動化や未公開 API に依存しません。

ユーザー指示により ISO / FocalLength をトークンとボタンから削除し、現在は 10 個です。既存テンプレートに残る場合は修正を促すエラーとします。内部の既存メタデータ読取項目は維持します。0.7.2.16 で 10 個のボタン、廃止トークンのエラー、正常テンプレートでの復帰を手動確認してください。
