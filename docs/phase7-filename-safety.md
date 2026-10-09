# Phase 7：ファイル名安全処理と衝突候補

## 範囲

純 Lua 5.1 の FilenameSanitizer / CollisionResolver を追加しました。SDK・ExifTool・ファイル I/O・時計には依存しません。既存統合診断に整形結果と仮想衝突例を表示します。実フォルダーの衝突調査、保存処理、Phase 1 の固定書き出しルールは変更しません。設定 UI は Phase 8、書き出しへの統合は Phase 9 に残します。

## FilenameSanitizer

`sanitize(filename, limits?)` は拡張子付きの候補名を受け取り、`{filename, changed}` または `nil, {code, message}` を返します。

- UTF-8 を検証し、不正なバイト列を拒否する。Unicode の正規化・大小文字変換は行わない。
- `< > : " / \ | ? *` をそれぞれ `_` に置換する。パスとして解釈しない。
- ASCII C0、DEL、UTF-8 の C1 制御文字を除去する。
- ファイル名全体と拡張子直前の stem の末尾スペース・ドットを除去する。拡張子は英数字で必須、小文字にする。
- 空名・空 stem、`.` / `..`、先頭ドットの名前を拒否する。
- 最初のドットより前の部分で Windows 予約名を判定する。CON / PRN / AUX / NUL、COM1〜9 / LPT1〜9、上付き ¹ / ² / ³ のポート名は拡張子付きでも拒否する。

既存文書の「制御文字を置換」は、ユーザーの Phase 7 指示「制御文字除去」に合わせて除去へ統一しました。先頭ドットは Finder で出力が見えにくくなることを避けるため拒否します。上付き番号の予約名は Microsoft の公式規則に基づく補足です。[Windows の命名規則](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file)、[Apple のファイル名変更ガイド](https://support.apple.com/guide/mac-help/rename-files-folders-and-disks-mchlp1144/mac)

`limits.maxBytes` を明示した場合だけ、整形後の UTF-8 バイト長（拡張子込み）を検証し、超過時は FilenameTooLong を返します。切り詰めません。この値を Windows の UTF-16 単位や全 OS の上限と同一視しません。実測した成分長・フルパス制約は後続の Platform / 保存境界で検証します。制約未指定の候補を保存可能と保証しません。

## CollisionResolver

読み込み時に `{sanitizer = FilenameSanitizer}` を渡し、`resolve(filename, options)` を呼びます。整形済み名前だけを受け取り、`{filename, collisionNumber}` を新しいテーブルで返します。

```lua
local candidate, err = collisions.resolve('photo.jpg', {
    existingNames = { 'photo.jpg', 'photo_001.jpg' },
    reservedNames = { 'photo_002.jpg' },
    nameKey = verifiedPlatformNameKey,
    maxAttempts = 10000,
    limits = { maxBytes = verifiedFilenameByteLimit },
})
-- candidate.filename == 'photo_003.jpg'
```

existingNames / reservedNames は保存先内のファイル・ディレクトリ名の配列です。関数自身は探索・予約・保存をしません。呼び出し元は確定した名前を reservedNames に追加します。`nameKey` は必須の純粋な比較キー関数で、OS / ボリュームの大小文字・Unicode 等価性を反映する責任を境界へ残します。Lua の lower で Unicode の同一性を推定しません。関数失敗・空キーは InvalidNameKey で停止します。

元候補を 0 とし、末尾拡張子の前へ `_001`、`_002` を付け、空いた最小番号を採用します。999 の次は 1000。元の `_0001` や `_001` は削除せず、Sequence とは別の番号です。入力配列は変更しません。候補ごとの長さ制約を再検証し、超過で停止します。候補数の既定は元候補を含め 10000、設定は 1〜1000000。上限到達は CollisionLimitReached として失敗します。

存在確認だけでは競合時の上書きを防げません。後続の FileSystem は保存時に再確認し、非上書きの確定保存に失敗した場合は候補を再解決します。この Phase は安全な保存の保証を実装したものではありません。

## macOS 手動確認

1. プラグインを再読み込みし、バージョン `0.6.0.13` を確認する。
2. プラグインエクストラの「メタデータ取得 / 入力ファイル探索を検証…」→「ExifTool でメタデータ取得」→「XMP → RAW → JPG を統合」を選ぶ。
3. 検証用 ExifTool と元写真を選び、「Phase 7 整形後」を確認する。レンズ等に禁止文字があれば `_` に変わる。整形に失敗した場合は理由が表示される。
4. 「同名ありを仮定した例」で `_001.jpg`、その候補も使用済みの例で `_002.jpg` を確認する。両方のメーカー省略設定について表示する。

衝突例は仮想の名前配列と完全一致比較を使い、実保存先の調査・OS の等価性検証・ファイル生成は行いません。元 RAW / JPG / XMP へ書き込みません。

## 検証と残課題

純 core 76 件が成功。禁止文字・制御文字、UTF-8、日本語、空名・予約名、バイト長超過、同名・連番・予約名配列、大小文字・Unicode 比較キー、不正入力・失敗・入力不変、テンプレートからの連携を確認しました。SDK ダブルと実 ExifTool を使う既存連携 6 件では、整形と仮想衝突表示、入力ファイルのバイト列不変を確認しています。

通常名の基本経路はユーザー報告があります。禁止文字を含む実機ケース、Windows / macOS の実保存時の名前・パス長、Unicode / 大小文字の OS 比較、競合時の非上書き確定保存は未確認です。次フェーズの指示を待ちます。

## 手動確認報告（2026-10-09）

ユーザーが、禁止文字を含む素材がなく、そのケースを十分に確認できなかった一方、通常のファイル名変更には問題がなさそうだったと報告しました。macOS の通常名の基本経路に関する確認として記録します。禁止文字の処理は合成入力による自動テスト済み、実機では未確認です。Phase 7 は診断候補の表示に限定しているため、この報告を Phase 7 の実保存・リネーム統合や競合時の非上書き保証の確認とは扱いません。衝突例の個別手動結果も未記録です。
