# Phase 3：メタデータ入力ファイルの探索

## 状態と範囲

2026-10-09、ユーザーの Phase 3 開始指示により実装しました。Phase 2 の macOS 診断メニュー・XMP FilmSim 取得はユーザー報告で確認済みです。Windows 等の残課題は継続します。

`infrastructure/MetadataSourceResolver.lua` はファイル名と配置だけで入力を探します。ExifTool、メタデータ読取、項目マージ、テンプレート、C2PA、書き出しへの統合は追加していません。新しい診断メニューは探索結果だけを表示します。

## 呼び出しと戻り値

SDK の task 内で、絶対パスの loadfile を使って初期化します。過去に発生した require のサブディレクトリ・スクリプト名制約へ依存しません。

```lua
local resolver = assert(loadfile(modulePath)) {
    fileUtils = LrFileUtils,
    pathUtils = LrPathUtils,
    tasks = LrTasks,
}
local sources, scanError = resolver.resolve(originalPath, 'same_then_parent')
-- 成功: { xmp = pathOrNil, raw = pathOrNil, jpeg = pathOrNil }
-- 失敗: nil, { code = '...', message = '...', candidates = optionalPaths }
```

originalPath は読み取り可能な JPG / JPEG / RAF / DNG の絶対パスです。XMP は関連入力として探索しますが、探索の起点にはしません。改行・NUL、相対パス、未対応拡張子、不正な探索モードは拒否します。

## 探索規則

| RAW モード | JPG 起点で探す階層 |
| --- | --- |
| same_directory | JPG と同じフォルダーだけ |
| parent_directory | JPG の 1 つ上のフォルダーだけ |
| same_then_parent（既定） | 同じ階層に一意な RAW がなければ 1 つ上 |

- RAF / DNG、JPG / JPEG、XMP の拡張子は大小文字不問。stem は拡張子を除いた名前の完全一致。
- 同階層に RAF と DNG 等が複数ある場合は `AmbiguousSource`。親に一意な候補があっても曖昧な同階層を飛ばさない。
- ASCII の大小文字だけ異なる stem は `AmbiguousStem` とし、推測で選ばない。Unicode 正規化による別名は等価扱いせず、完全一致しなければ採用しない。
- サブフォルダーへの再帰、親より上への探索、撮影日時による推測、派生名の対応付けは行わない。
- 元画像が RAF / DNG ならそのファイルを RAW として使い、同階層で対応 JPG / JPEG を探す。RAW モードはこの場合の探索範囲を変更しない。
- XMP は選択 RAW の隣接フォルダーと元画像のフォルダーで探す。候補が両方にあるなら、先順位だけで黙って捨てない。異なる候補が複数ならエラー。
- 同じ正規化済みパスへ解決される別名は重複排除する。元の探索パスを返し、物理パスを使って探索範囲を拡大しない。
- 関連ファイルなしは nil。元画像不在、候補の読み取り不能、列挙・パス解決失敗は `SourceReadError` とし、欠落扱いでフォールバックしない。

XMP 同士の合成や複数入力のフィールド単位マージは Phase 4 に残します。返却したパスの有効性を未来まで保証するものではなく、後続の読取時にも検証が必要です。

## SDK と I/O の境界

使用する API は `LrFileUtils.directoryEntries` / `exists` / `isReadable` / `resolveAllAliases`、`LrPathUtils.isAbsolute` / `parent` / `leafName` / `removeExtension` / `extension` / `standardizePath`、`LrTasks.pcall` です。

directoryEntries は直下のみを列挙し、ハンドルを保持するため途中で break しないという SDK の仕様を確認しました。先に列挙を正常に完了し、その後候補を検証します。1 回の resolve 内で階層別の列挙結果をキャッシュし、RAW と XMP の検索で同じフォルダーを再走査しません。呼び出しをまたぐ永続キャッシュはありません。

作成・コピー・移動・削除・権限変更の API は探索モジュールへ実装していません。SDK の ReadError を握りつぶさず、ユーザーへ理由と曖昧な候補を表示します。

参照元は Adobe 作成 SDK リファレンスの [LrFileUtils](https://lrc.mcor.dev/modules/LrFileUtils.html) と [LrPathUtils](https://lrc.mcor.dev/modules/LrPathUtils.html) の公開ミラーです。公式 SDK 配布物との照合状況は [Phase 1 記録](phase1-lightroom.md#参照資料の出典) の制約を引き継ぎます。

## 自動検証結果

- SDK 境界テスト：**43 件成功**。3 モード、RAF / DNG、拡張子大小文字、XMP 単独、RAW 単独、JPEG 単独、曖昧候補、読み取り失敗、ルート、Windows パス文字列、Unicode・日本語等を確認。
- macOS の合成ファイル配置テスト：**9 件成功**。日本語フォルダー・stem、親フォルダーからの取得、DNG 優先階層、曖昧性、入力バイト列不変、両メニューの登録を確認。
- Phase 1 回帰：**66 件成功**。
- Phase 2 回帰：**81 件成功**。実 ExifTool と合成入力を使用し、以前の個人 RAF / XMP の任意ケース 2 件は今回実行していない。
- Lua 5.1 構文・差分を確認。Lua 5.1.5 は公式 SHA-256 を照合して一時領域に再構築し、製品の依存には追加していない。

```sh
lua tests/integration/metadata_source_resolver_test.lua
lua tests/integration/metadata_source_resolver_native_test.lua
```

境界テストはメモリ上の SDK ダブルで、ExifTool やプロセス実行機能を渡しません。ネイティブテストは macOS 用 adapter を通して独自の一時領域に合成ファイルを作り、検証後にテスト自身が清掃します。探索モジュールによる書き込み・削除ではありません。空のモデルファイルは配置検証用で、実 RAF / DNG の内容解析を証明するものではありません。

## Lightroom Classic での手動検証

1. プラグインを再読み込みし、バージョン `0.2.1.8` を確認する。新しいメニューが反映されなければ Lightroom Classic を再起動する。
2. 「ファイル（またはライブラリ）→ プラグインエクストラ → メタデータ取得 / 入力ファイル探索を検証…」を開き、「XMP / RAW / JPG の探索」を選ぶ。ExifTool の選択は不要。
3. JPG を選び、3 モードそれぞれの xmp / raw / jpeg のパスを確認する。
4. 合成・複製素材で、JPG と同階層に RAF、JPG の親に DNG を置く。同階層モードと same_then_parent は RAF、親階層モードは DNG を返すことを確認する。
5. 同階層の RAW を取り除いた別の検証配置で、same_then_parent が親へ進むことを確認する。
6. 同階層に同じ stem の RAF と DNG を置くと、同階層・順次探索が曖昧エラーになることを確認する。
7. 選択 RAW の隣と元 JPG の隣の両方に別の XMP があれば、曖昧エラーになることを確認する。
8. 元 RAW を直接選んだ場合、その RAW と同階層の対応 JPG / XMP を返し、3 モードで結果が変わらないことを確認する。
9. 読み取り不能・アクセス拒否を欠落として扱わないこと、元画像と XMP のチェックサム不変を確認する。

macOS の探索診断はユーザーから問題なく動作するとの報告があります。以下の個別ケースをすべて実施済みとはみなしません。個人素材を移動・削除して配置を変更せず、検証用コピーを使ってください。

## 残課題と Phase 4 のゲート

- macOS の診断起動・探索の基本動作はユーザー報告済み。Windows 実機、ACL・ネットワークフォルダーは未確認。
- Unicode 正規化、大小文字を区別しない実ファイルシステム、ショートカット・別名解決の実機差は要検証。
- SDK のパス解決だけで inode / ハードリンク同一性は判断しない。異なる正規パスを同一と推定せず、曖昧エラーへ倒す。
- SDK がアクセス拒否を例外ではなく空の列挙として返す条件があるか、手動検証で確認する。
- 処理途中で消えた候補は判定時にエラーにするが、探索・読取全体の原子的なスナップショットは保証しない。

Phase 3 の実装・単体検証は完了。macOS の Lightroom 内での探索診断の基本動作もユーザー報告で確認しました。個別の異常系・Windows 等は未確認です。Phase 4 は新たな指示を受けるまで開始しません。

## メニュースクリプト未認識への対処

ユーザーから `No script by the name Phase3Diagnostic.lua` が報告されました。新規ファイルを SDK のメニュー入口に直接登録する方式をやめ、起動実績のある `Phase2Diagnostic.lua` を共通入口として再利用します。この入口で検証内容を選び、Phase 2 / 3 の処理は絶対パスの loadfile と明示コンテキストで実行します。

共通入口は LrDialogs.confirm の ok / cancel / other を使います。API は [Adobe 作成 SDK の LrDialogs 参照](https://lrc.mcor.dev/modules/LrDialogs.html#LrDialogs.confirm) で確認しました。メタデータ読取・探索処理は各ファイルに分離したままです。SDK の名前検索を全面的に失敗させても探索結果表示まで到達するケースと、取消時にファイル選択・処理を開始しないケースを回帰テストへ追加しました。

修正版 `0.2.1.8` へ再読み込み後、共通検証メニューを開いて探索を選んでください。SDK の新規ファイル認識が失敗した正確な内部原因は未確定で、今回の変更はその名前検索への依存を除去する対処です。その後、ユーザーから修正後の動作に問題がなさそうとの報告を受けました。

## macOS の手動確認報告（2026-10-09）

メニュースクリプト未認識への修正後、ユーザーより「動作問題なさそうです」との報告を受けました。共通診断入口から探索を実行する基本経路の確認として記録します。エージェントによる Lightroom 実機操作ではありません。

使用した起点ファイル、各モードの実際のパス、曖昧・アクセス拒否ケース、確認環境の詳細は今回の報告に含まれません。基本動作の成功を全モード・全プラットフォーム・全異常系の合格へ一般化せず、残課題は維持します。Phase 4 はまだ開始しません。
