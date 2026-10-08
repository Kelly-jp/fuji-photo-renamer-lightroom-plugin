# Phase 1：Lightroom Classic 最小技術検証

## 判定と実装範囲

2026-10-08：**実装・Lua 自動検証は完了。macOS の基本書き出しと安全性についてユーザーから確認報告あり。全体の成立判定は継続中で、Phase 2 には進まない。**

`Info.lua` と `ExportServiceProvider.lua` の 2 ファイルで、標準の保存先設定、JPEG 一時レンダリング、固定命名、保存失敗の通知を実装しました。ExifTool、テンプレート、C2PA、RAW 探索、メーカー処理はありません。SDK 宣言は 11.0 以上です。これは実測した最低対応 Classic バージョンではありません。

Phase 1 は `test_<カタログ元画像の stem>.jpg` を保存します。元 JPG / RAW は読み取り専用で、XMP を開く処理、メタデータ書き込み、元画像の移動・削除はありません。同名時は失敗し、Phase 7 の別名化を先行実装しません。

## 参照資料の出典

- [Adobe 配信元の SDK Programmers Guide（2022 年版）](https://ioconsolerykerprodcdn.azureedge.net/static/installers/lr/sdk/2022/cross_platform/v13/doc/Lightroom%20Classic%20SDK%20Guide_1655133965.pdf) を取得。宣言は p.36–38、コールバックと通知は p.53、非表示セクションと一時フォルダは p.58、設定キーは p.61–65、Lua 5.1 互換は開発環境の節を確認。
- 詳細 API とサンプルは Adobe 作成の **SDK 14.3 / build 202504141032-10373aad** の公開ミラーを参照。[参照スナップショット](https://github.com/mingchuno/lightroom-classic-sdk/tree/b3cbd46b716523eb2eb9cf230d440fbecc52e0e5)。Adobe の配信サイトではないため、公式配布 ZIP との同一性は未確認。Adobe CDN の候補 ZIP URL は 404 で取得できなかった。
- ミラー内の `API Reference/modules/` と `Sample Plugins/ftp_upload.lrdevplugin/`、`flickr.lrdevplugin/FlickrExportServiceProvider.lua` を照合。第三者による API 解説を根拠に API 名を補完していない。
- SDK 資料・サンプル・コンパイラは配布物や Git に追加していない。サンプルファイルを転載せず、本プロジェクトのコードを記述した。

取得物の SHA-256（版の識別用であり Adobe による署名検証ではない）:

```text
Adobe Guide PDF:
bfa23a9d5898ec71d16c3bad4a7eeb6d05484ce679e2942e7fd40866c210b8ce
SDK 14.3 mirror ZIP, commit b3cbd46b716523eb2eb9cf230d440fbecc52e0e5:
6cfe05c262ea18543206fb4147352ff3b6637a33fad81f24050d7025e0b849cc
```

正式な対応判定前に、[Adobe Developer Console](https://developer.adobe.com/console/servicesandapis) から取得した SDK の同じ節と API を再照合してください。

## 使用した SDK 定義と API

以下の参照名は SDK 内の HTML ファイル / 節です。ミラーの該当ページは上記固定スナップショットから参照できます。

| 定義 / API | 用途 | 確認した資料 |
| --- | --- | --- |
| `LrSdkVersion` / `LrSdkMinimumVersion` / `LrToolkitIdentifier` / `LrPluginName` / `VERSION` | プラグイン登録・バージョン | Guide「Plug-in Structure」、SDK サンプル `Info.lua` |
| `LrExportServiceProvider` の `title` / `file` | 書き出し先の表示名と provider | Guide p.36–37、FTP サンプル |
| `showSections` / `allowFileFormats` / `canExportVideo` / `canExportToTemporaryLocation` | 標準保存先を表示、一時保存先を選択肢から除外、JPEG のみ、動画不可 | `SDK - Export service provider.html`、Guide p.38 / p.58 |
| `startDialog` / 組み込み `LR_export_*` 設定 | 旧保存先の移行、標準設定としてのプリセット記憶 | 同 provider 参照、Guide p.39 / p.59 |
| `sectionsForTopOfDialog` / view factory の `static_text` | 固定命名・同名時の動作説明 | 同 provider 参照、`LrView.html`、Guide UI の節 |
| `LrDialogs.runOpenPanel` / `message` | フォルダ選択と処理結果表示 | `LrDialogs.html` |
| `LrTasks.pcall` | SDK タスク内の yield 可能な例外処理 | `LrTasks.html` |
| `updateExportSettings` | JPEG・一時保存・再取り込みなしの設定固定 | provider 参照、Guide の組み込み設定キー |
| `processRenderedPhotos` | SDK が用意する cooperative task で後処理 | Guide p.53、FTP / Flickr サンプル |
| `exportContext.propertyTable` / `configureProgress` / `renditions` | 設定取得、進捗、写真の列挙 | `LrExportContext.html`、Guide p.53 |
| `rendition.photo:getRawMetadata('path')` | カタログ元画像の現在または最後に判明したパス | `LrPhoto.html` の `getRawMetadata` / `path` |
| `rendition:waitForRender()` / `wasSkipped` | 完了を待ち、成功時にレンダリング済みパスを取得 | `LrExportRendition.html` |
| `rendition:uploadFailed(message)` | 保存・取得・レンダリング失敗を Classic へ通知 | 同 rendition 参照、Guide p.53 |
| `progressScope:isCanceled()` / `cancel()` / `stopIfCanceled` | キャンセル時に新規保存を停止 | `LrProgressScope.html` / `LrExportContext.html` |
| `LrPathUtils.isAbsolute` / `leafName` / `removeExtension` / `extension` / `child` / `parent` / `getStandardFilePath` / `standardizePath` | パス検証、固定命名、パス比較 | `LrPathUtils.html` |
| `LrFileUtils.exists` / `isReadable` / `resolveAllAliases` / `createAllDirectories` / `copy` | 存在・読取チェック、別名解決、指定サブフォルダー作成、出力コピー | `LrFileUtils.html` |

`renditionIsDone()` は Export Filter Provider 向けであり、この Export Service Provider には使用しません。成功時の独自完了 API は追加せず、処理ループを完了します。失敗は `uploadFailed`、全体の保存件数・失敗件数はメッセージで表示します。

## Export 処理の流れ

1. 標準の `exportLocation` を表示する。最終保存先はこの UI の組み込み設定を使用し、`fileNaming` は固定名のため表示しない。
2. `updateExportSettings` でユーザーの保存先種別・パス・サブフォルダー設定をセッション用 `phase1Destination` に退避し、JPEG、`tempFolder`、Lightroom 側の一時結果の衝突処理 `rename` を設定。最終保存先へ直接レンダリングしない。
3. `configureProgress` を呼ぶ。「後で選択」の場合は SDK のフォルダー選択で保存先を一度だけ確認し、取り消し・例外では進捗をキャンセルして保存を行わない。その後 `renditions { stopIfCanceled = true }` を列挙する。
4. 保存先を写真ごとに解決する。元フォルダー指定は元パスの親、特定フォルダーは選択パス、標準フォルダーは SDK の標準パスを使う。写真ごとに `getRawMetadata('path')` で元パスを読み、存在と読み取り可否を確認。元画像不在時は拒否する。
5. 元ファイル名から拡張子を除き `test_` と `.jpg` を付ける。禁止文字・制御文字・末尾ドット等の扱いに困る名前は、Phase 1 では置換せず拒否する。
6. `waitForRender()` の成功戻り値から一時 JPEG のパスを取得。動画、スキップ、非 JPEG、元画像と解決後のパスが同じ場合は保存しない。
7. レンダリング成功後、ユーザーが指定した単一のサブフォルダーがなければ作成する。パス区切り、親移動、予約名等は拒否する。`LrFileUtils.copy(renderedPath, destinationPath)` で最終名へコピー。存在確認だけに依存せず、SDK の既存保存先に対するコピー失敗契約を使用する。衝突・権限不足・例外は失敗通知し、他の写真へ進む。
8. 一時ファイルは移動・削除せず、コールバック終了後の Lightroom の清掃に任せる。キャンセル前に保存済みの JPEG は残す。

カタログへの再登録、元画像へのメタデータ保存、ExifTool 呼び出しはありません。Lightroom 自身の通常の書き出し履歴・Previous Export コレクション更新と、元画像内容への書き込みを混同しないでください。

## 手動検証手順

以下は完全な検証手順です。一部のユーザー報告結果は「macOS の実機確認報告」に記録しています。既存の個人カタログを検証用に使わず、合成画像または許諾済み写真のコピーと専用カタログを用意します。

1. OS / CPU、Lightroom Classic の正確なバージョン、使用 SDK の版、元写真の形式を記録する。
2. 元 JPG / RAF / DNG と隣接 XMP の SHA-256 を記録する。macOS は `shasum -a 256 <path>`、Windows PowerShell は `Get-FileHash -Algorithm SHA256 <path>` を使用する。
3. プラグインマネージャーで `src/FujiPhotoRenamer.lrplugin/` を追加し、有効・エラーなしとなることを確認する。ソース変更後は再読み込みする。
4. 書き出しダイアログで「Fuji Photo Renamer — Phase 1」を選ぶ。標準の「書き出し場所」があり、JPEG だけ選択可能であることを確認する。
5. 「特定のフォルダー」で空の専用フォルダーを選ぶ。未選択・無効パスは書き出せないか、保存エラーになることを確認する。
6. `DSCF1234.RAF` を書き出し、指定先に `test_DSCF1234.jpg` があること、JPEG として開けること、寸法・現像結果が設定と一致することを確認する。元 JPG / DNG でも繰り返す。
7. 元画像・XMP のハッシュが全て不変で、元フォルダに新規・バックアップファイルがないことを確認する。
8. 同じ写真を再書き出しし、同名エラーとなり、既存出力のハッシュが不変であることを確認する。別フォルダに同じ stem の元画像を置いた複数書き出しも確認する。
9. 保存先の削除・権限不足、元画像オフライン、スキップ、レンダリング失敗で成功扱いされないことを確認する。途中キャンセルで以後の保存が止まり、保存済み件数が正しいことを確認する。
10. 日本語・空白・ドットを含む元名と保存先、外付けの保存先、大小文字だけ異なる既存名を確認する。並行セッションで同じ保存先名を競合させ、既存ファイル不変と失敗通知を確認する。
11. 別名・シンボリックリンク・ハードリンクを含む環境でも元ファイルが変わらないことを確認する。`resolveAllAliases` や `standardizePath` だけで inode 同一性が保証されるとはみなさない。
12. 「特定のフォルダー」「元の写真と同じフォルダー」とサブフォルダー ON/OFF を各々確認する。異なる元フォルダーから選んだ写真が各親フォルダー（または各サブフォルダー）へ保存されることを確認する。「後で選択」の選択・取り消しも確認する。標準設定をプリセットとして保存・再読み込みし、保存先・サブフォルダーが保持されることを確認する。最終保存先に元名の中間 JPEG が残らず、`test_` の出力だけになることを確認する。
13. コールバック終了後に SDK 一時ファイルが清掃されることを確認する。コピー失敗時に出力先へ不完全な JPEG が残るかも記録する。

全ケースを Windows / macOS で記録し、技術検証 1・2 の判定を更新します。成功系だけで Phase 1 を成立済みとしません。

## 自動検証結果

- Lua 5.1.5 の `luac -p`：2 本体ファイルとテストファイルの構文チェックを実施。
- `lua tests/integration/phase1_provider_test.lua`：**66 / 66 成功**。
- `git diff --check` と新規ファイルの空白・競合マーカー確認を実施。

テストは最小の SDK 境界ダブルを用い、既存保存先、競合、読み取り不能、例外、レンダリング失敗、キャンセル、同名写真、保存先の標準設定、サブフォルダー、旧設定移行等の分岐を確認します。実画像を生成せず、SDK のスケジューリング、ネイティブコピー、JPEG の妥当性や Windows / macOS 差は検証できません。

テスト用 Lua は [公式配布](https://www.lua.org/ftp/) の 5.1.5 を一時フォルダでビルドしました。公式掲載 SHA-256 `2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333` と一致。配布依存にはしません。原版 C ソースの空ループ・古い `tmpnam`・インデントにコンパイラ警告が出ましたが、プラグインは `tmpnam` を使いません。第三者ソースを変更・警告抑制していません。

## 制約・未解決事項・次フェーズのゲート

- `getRawMetadata('path')` はオフライン時に最後の既知パスを返し得る。存在・可読性を別途確認し、スマートプレビューだけの元画像不在は拒否する。
- `processRenderedPhotos` は SDK の cooperative task。通常の Lua `pcall` は yield に対応しないため、本体は `LrTasks.pcall` を使用する。
- `tempFolder` に退避した一時結果はコールバック後に消えるため、後のタスクへパスだけ渡して保存を遅延しない。
- Export Filter 専用の完了通知を使わない。保存先選択・失敗一覧・キャンセル表示は実機で要確認。
- `copy` の非上書き契約は資料で確認したが、競合時の実装・別名・リンク・OS 差は未確認。SDK が安全条件を満たさなければ保存方式を再検討する。
- コピー失敗後の部分ファイル残留、長いファイル名・パス、無効プリセットの UI 表示も未確認。所有が曖昧な出力を自動削除するコードは入れない。
- SDK の詳細参照は Adobe 作成資料のミラー。公式配布 SDK との照合と実機結果が必要。
- Phase 9・10 の最新指示は C2PA 削除を最終保存後とする一方、既存設計は作業コピーへの削除・検証後に確定保存する。Phase 1 では変更せず、対象 Phase の前に失敗時の公開・所有・清掃方針を明記して設計を更新する必要がある。

**macOS の基本経路はユーザー報告で確認済みですが、未確認項目を含めた Phase 1 の判定は継続中です。** Phase 2 は自動で開始せず、残項目の扱いを決めて次の指示を受けてから進めます。後続の本番用抽象化やツール連携は追加していません。

## 保存先設定の変更理由と追加確認

ユーザーの指示により、独自の保存先選択 UI を標準の「書き出し場所」へ置き換えました。SDK ガイド p.61 の `LR_export_destinationType`、`LR_export_destinationPathPrefix`、`LR_export_useSubfolder`、`LR_export_destinationPathSuffix` を採用します。標準の使い方の根拠は [Adobe の書き出し場所の説明](https://helpx.adobe.com/lightroom-classic/desktop/export-photos/export-files-disk-or-cd.html) です。

セッションで退避する `phase1Destination` は内部の処理用で、独自プリセット項目にはしません。標準保存先設定は標準 UI に記憶させます。`updateExportSettings` に渡る設定が UI の設定とどう分離されるか、再書き出し・プリセット再読込で一時保存先が選択状態として残らないかは実機確認対象です。

既存ファイルの上書き・衝突時別名化、カタログへの追加、スタック追加はこの変更に含めず、画面にも適用しない旨を表示します。フォルダー作成失敗・取消ではコピーをしません。明示的なサブフォルダーの空ディレクトリが失敗・取消後に残る場合がありますが、所有が不明なディレクトリの自動削除はしません。以前の「元フォルダーに追加ファイルがない」確認は、同フォルダーへの保存を選んだ場合、意図した `test_` 出力・サブフォルダー以外に中間生成物がないことの確認へ読み替えます。

## macOS の実機確認報告

2026-10-08、ユーザーが実施した確認の報告を記録します。エージェントが実機操作やチェックサム比較を独立に実施した結果ではありません。macOS / CPU / Lightroom Classic の詳細バージョン、比較アルゴリズム、チェックサム値は未記録です。

| 項目 | 報告された結果 |
| --- | --- |
| 元画像と同じフォルダーのサブフォルダーへの保存 | 成功。`test_DSCF9649.jpg` の出力を確認。 |
| 同名時の上書き防止 | 上書きされないことを確認。 |
| 元 RAW の内容不変 | 書き出し前後のチェックサムが一致。 |
| XMP の内容不変 | 書き出し前後のチェックサムが一致。 |
| 更新日時 | 変化なしとの報告。内容不変の判定には上記チェックサム比較を使用。 |

元 JPG のハッシュ不変、Windows、特定フォルダー単独、キャンセル、権限不足、並行書き出し、リンク、プリセット再読込、一時出力の清掃等については未確認のままです。これらを今回の報告から推定で合格にしません。

改善事項：書き出し時に表示されるダイアログを後で削減する。対象ダイアログと代替通知方式は変更時に決め、失敗を成功扱いしないことを維持する。現時点では UI の挙動を変更しません。
