# Phase 4：項目単位のメタデータ統合

## 状態と範囲

2026-10-09、ユーザーの Phase 4 開始指示で実装しました。`core/MetadataResolver.lua` は普通の Lua テーブルだけを処理し、SDK、ExifTool、ファイル・プロセス I/O、時計に依存しません。Phase 5 のメーカー正規化、テンプレート、書き出しへの統合は追加しません。

## 入出力契約

```lua
local result, mergeError = MetadataResolver.resolve {
    xmp = { metadata = { rating = 5, filmSim = 'CLASSIC_NEGATIVE' } },
    raw = { metadata = { camera = 'X-H2S', lensMaker = 'FUJIFILM', filmSim = 'PROVIA' } },
    jpeg = { metadata = { iso = 800 } },
}
```

成功時は `metadata`、`fieldSources`、`missingFields`、`rejectedValues` を持つ新しいテーブルを返します。例では rating / filmSim が XMP、camera / lensMaker が RAW、iso が JPEG から採用されます。入力元なしは nil、入力元がある場合は metadata テーブルを要求します。Phase 2 の読取結果から metadata と fieldSources を取り出して渡せます。

内部名は Phase 2 の camelCase を使用します。追加の文字列キーもスカラー項目として保持するため、例示された Rating 等のキーは改名しません。ただし特殊な検証規則は正規の内部名に適用します。

fieldSources は項目ごとの sourceKind（xmp / raw / jpeg）と、与えられた sourcePath / tag をコピーします。種類は入力グループが決定します。タグ名を解釈しないので、core は ExifTool のタグ定義を知りません。TokenResolver へは将来 metadata のみを渡します。

構造不正は nil と InvalidInput / InvalidSourceKind / InvalidSource / InvalidMetadata / InvalidField / InvalidProvenance を返します。入力元に readError があれば ReadError で失敗し、下位データへ黙ってフォールバックしません。実際の I/O 失敗は診断 adapter が先に検出し、統合処理を開始しません。

## 項目別の有効性

XMP → RAW → JPEG の順に各項目を走査し、最初の有効な値を採用します。nil は値なし。空文字・空白のみ・非スカラー・不正な値は不採用理由を記録して次の入力へ進みます。

| 項目 | 規則 |
| --- | --- |
| cameraMaker / camera / lensMaker / lens / filmSim | 空白だけでない文字列。未知メーカー名や元の表記を変更しない。 |
| iso | 正の有限な整数。文字列数値は adapter が数値へ変換してから渡す。 |
| focalLength | 正の有限な数値。小数を許可。 |
| rating | 0〜5 の整数。0 は有効。 |
| captureDateTime | 下記の完全な撮影日時文字列。 |
| その他 | 空白だけでない文字列、有限な数値、boolean。数値 0 と false を保存する。 |

不採用理由は EmptyValue / UnsupportedType / NonFiniteNumber / InvalidText / InvalidDateTime / InvalidISO / InvalidFocalLength / InvalidRating。項目名・入力元・理由を記録し、未採用の個人メタデータ値は診断へコピーしません。採用済み項目は下位で上書きしません。

欠落リストは標準 8 項目と入力に現れた追加項目を対象にします。全入力が空なら、標準 8 項目が欠落となり、空の metadata を正常に返します。実際のトークン使用時の必須性は Phase 6 に残します。

## 撮影日時の検証

EXIF の `YYYY:MM:DD HH:mm:ss`、ISO 形式の `YYYY-MM-DDTHH:mm:ss`（T の代わりに空白も可）に対応します。任意の小数秒と Z または ±HH:mm のオフセットを許可します。年は 0001〜9999、月日・閏年をグレゴリオ暦で検証し、時は 00〜23、分秒は 00〜59。オフセットの時分も同じ範囲で字句検証します。閏秒 60、日付だけ、時刻だけ、末尾の不明文字は未対応として拒否します。

採用値は元の文字列を保持し、UTC への変換や現在日時・ファイル更新日時の代用は行いません。Date / Time / DateTime 用の書式整形は Phase 6 です。複数ファイルの日付と時刻を合成せず、captureDateTime 全体を一つの入力から採用します。

## 自動検証

- 純 core テスト **59 件成功**。SDK・ExifTool・I/O・時計を与えない環境で実行。
- macOS ネイティブ連携 **6 件成功**。実 ExifTool の合成 XMP / JPEG と正規化済み合成 RAW データを項目別に統合し、JPEG へのフォールバック、入力バイト列不変、共通入口からの起動・取消を確認。
- Phase 1 回帰 66 件、Phase 2 合成入力回帰 87 件、Phase 3 境界 43 件・ネイティブ 9 件成功。個人の任意 RAW / XMP ケースは今回未実行。

```sh
lua tests/core/metadata_resolver_test.lua
lua tests/integration/metadata_resolver_native_test.lua /absolute/path/to/exiftool
```

正常系と欠落、false / 0、不正な日時・閏年・型、非有限値、読取エラー、入力・provenance 不変を確認します。native テストの任意の第 2 引数に、許諾済み検証用 X-H2S RAW を指定できます。未指定なら個人写真を自動探索しません。

## Lightroom の手動確認

1. プラグインを再読み込みして `0.3.1.10` を確認する。
2. 「プラグインエクストラ → メタデータ取得 / 入力ファイル探索を検証…」を開く。
3. 「ExifTool でメタデータ取得」、続いて「XMP → RAW → JPG を統合」を選ぶ。
4. 検証用 ExifTool と元 JPG / JPEG / RAF / DNG のコピーを選ぶ。
5. same_then_parent の探索結果を読み取り、統合した各値と（xmp / raw / jpeg）の採用元が表示されることを確認する。
6. 複製素材で XMP の既知 Look / CameraProfile を変えたケース、RAW からの補完、JPG のみ、欠落・破損・曖昧候補を確認する。読取失敗を成功扱いしない。
7. 入力 RAW / JPG / XMP の書き出し前後ではなく、診断前後のチェックサム不変を確認する。

検証用 adapter にだけ探索・ExifTool 読取を組み合わせます。探索モードの本番 UI、プレビュー、書き出し処理との全体統合は行いません。既存の単一ファイル読取・探索も共通入口から利用できます。新規 SDK メニュースクリプトは登録せず、既存入口から絶対パスで処理を読み込みます。

## 残課題と次 Phase

Lightroom 内の DNG 現像変更ケースはユーザー報告で取得成功を確認しました。Windows 実機、その他の統合ケース・異常系、多様な実機データは未確認です。日時の閏秒等の拡張は必要な実データが出た時点で仕様を検討します。現時点の対応範囲と不採用診断を明示し、推測で採用しません。

Phase 4 の実装・自動検証は完了。手動確認を待ち、Phase 5 は新たな指示を受けるまで開始しません。

## DNG の変更前 FilmSim が残る報告への対処

修正版 `0.3.1.10` は、DNG / JPG 内の既知編集プロファイルを古い撮影時コードより優先します。合成 DNG の変更後 CameraProfile を読取境界で解決し、core が RAW 入力からその値を採用して、JPEG の旧設定で上書きしないテストを追加しました。純 core の 59 件と連携 6 件、Phase 2 の合成入力回帰 87 件が成功しています。

診断結果には FilmSim の採用ファイルとタグを表示します。XMP → RAW → JPG の順位は変更せず、古い sidecar が選ばれたか、DNG 内の MakerNotes が使われたかを切り分けます。ユーザーが実際の DNG 書き出しのケースを再確認し、変更後の FilmSim を取得できたと報告しました。エージェントによる実再現ファイルの直接検査は未実施で、パス・前後の値・採用タグは未記録です。

## DNG 現像変更ケースの手動確認（2026-10-09）

ユーザーより「DNG の書き出しの件を確認し、変えた FilmSim が取得できるのを確認」との報告を受けました。修正後の Lightroom 内で、以前の変更前設定を取得していたケースが変更後の FilmSim を返すことを、ユーザーの実機結果として記録します。

具体的な FilmSim 名、入力パス、採用元タグ、OS / Classic の詳細バージョンは今回の報告に含まれません。この成功を Windows、全プロファイル、日時や他項目の全異常系へ一般化しません。コードや素材の再検査を実施したとは記載せず、Phase 5 は新たな指示を待ちます。
