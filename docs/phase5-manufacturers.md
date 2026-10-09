# Phase 5：メーカー名の正規化

## 状態と範囲

2026-10-09、ユーザーの Phase 5 開始指示で `core/ManufacturerNormalizer.lua` を追加しました。SDK、ExifTool、I/O に依存せず、メーカー文字列から比較キーと表示名を作ります。元の Metadata は変更しません。テンプレート、メーカー出力の省略、本番 UI、書き出し統合は後続 Phase に残します。

## API

```lua
local camera, cameraError = ManufacturerNormalizer.normalize(' Fujifilm Corporation ')
-- { key = 'FUJIFILM', displayName = 'FUJIFILM', known = true }
local same, compareError = ManufacturerNormalizer.sameManufacturer('FUJIFILM', 'Fuji Film')
-- true
```

normalize は新しいテーブルを返します。nil・空文字・空白のみなら nil（欠落）、非文字列や不正な制御文字なら nil と InvalidManufacturer を返します。sameManufacturer は有効な両メーカーのキーが一致すれば true、それ以外は false。不正入力は nil とエラーです。nil 同士を同一メーカーとみなしません。

## 正規化の規則

1. 前後の空白を除去し、連続する空白を半角スペース一つに整理する。
2. ASCII の a–z だけを A–Z に変換し、比較キーを作る。Unicode の大小文字・正規化・全角変換はしない。
3. 明示した別名だけを正規のブランドへ対応させる。
4. 未知メーカーのキーは整理済み文字列の ASCII 大文字版、表示名は整理済みの元の大小文字を保持する。

| 比較に使う別名 | 既知キー・表示名 |
| --- | --- |
| FUJIFILM / FUJI FILM / FUJIFILM CORPORATION | FUJIFILM |
| TAMRON / TAMRON CO., LTD. | TAMRON |
| SIGMA / SIGMA CORPORATION | SIGMA |

任意の Corporation 等の接尾辞、句読点、ハイフンを削除しません。未知名の Acme と Acme Corporation は別のキーです。SIGMA Corporation of America 等、明示していない派生名も推定で統一しません。部分一致でブランドを推定しません。追加の会社名表記は実データを確認して明示的な別名とテストを追加します。

旧 tokens 文書には未知メーカーを同一とみなさないという記述がありましたが、Phase 5 のユーザー指示では未知メーカーも trim・大小文字正規化後に比較可能と指定されています。この指示に合わせ、非空の同じ未知キーは同一として比較する仕様へ更新しました。出力省略条件への適用は Phase 6 です。

## 自動検証

- 純 core テスト **32 件成功**。SDK / ExifTool / I/O を与えない環境で実行。
- 既知表記揺れ、未知名比較、異メーカー、欠落、型・制御文字、Unicode の非推定、元 Metadata 不変を確認。
- 統合診断の合成入力テスト **6 件成功**。実 ExifTool からのメーカーを表示し、キー・同一判定が確認できることを追加検証。
- 回帰は MetadataResolver 59 件、Phase 1 66 件、Phase 2 の合成入力 87 件、Phase 3 の 43 + 9 件が成功。

```sh
lua tests/core/manufacturer_normalizer_test.lua
lua tests/integration/metadata_resolver_native_test.lua /absolute/path/to/exiftool
```

## Lightroom 内での確認

1. プラグインを再読み込みし、`0.4.0.11` を確認する。
2. 共通検証メニューで「ExifTool でメタデータ取得」→「XMP → RAW → JPG を統合」を選ぶ。
3. 検証用 ExifTool と元画像のコピーを選択する。
4. 元の cameraMaker / lensMaker に加えて、末尾に比較キーと「同一メーカー：はい」等が表示されることを確認する。
5. 異メーカー・欠落の場合に同一と判定されないことを確認する。不正な名前では警告を表示する。

探索・読取・統合は既存の検証用 adapter のままです。core は通常の文字列だけを受け取り、元の metadata の値・採用元を上書きしません。ファイル名のメーカー省略や ON/OFF 設定はまだありません。

## 残課題

Lightroom 内の比較表示は未確認、Windows 等の既存残課題は継続します。未確認の会社名・Unicode 表記は推定で統一しません。Phase 5 の実装と自動検証は完了し、Phase 6 は新たな指示を待ちます。

## 既知会社名の根拠

ブランド名に加え、公式の [TAMRON 会社概要](https://www.tamron.com/global/company/company_profile.html) にある Tamron Co., Ltd. と、[Sigma 会社概要](https://www.sigma-global.com/en/corporate-overview/) にある Sigma Corporation を明示した別名として扱います。任意の接尾辞を削除するルールではありません。

## 手動確認報告（2026-10-09）

ユーザーはこれまで使用した画像でメーカー名を取得できたことを確認しました。表記揺れや異メーカーの検証に適した画像は手元になかったとの報告です。

既存画像のメーカー取得経路が維持されている確認として記録します。比較キーの具体的な表示値、同一・異メーカーの判定、欠落時動作の手動結果は未報告であり、正規化の全ケースが実機で合格したとはみなしません。これらは合成入力・純 core テストの結果と区別します。追加の個人画像を要求・自動探索せず、残課題を維持します。
