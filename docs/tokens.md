# ファイル名トークン

## 構文と共通ルール

トークンは大文字・小文字を区別する `{Name}` です。初期は固定トークンのみで、条件式、任意書式指定、スクリプト評価は提供しません。`{{` / `}}` はリテラルの波括弧とします。未知トークン、不対応の構文、閉じない括弧は実行前エラーです。

テンプレートはファイル名だけを扱います。`/`、`\`、制御文字によるパス指定は拒否します。拡張子は実際の出力形式から必ず自動付加します。Extension トークンは廃止しました。実際のファイル形式と不一致の拡張子をユーザー文字列で指定できません。

## 対応トークン

| トークン | 元になる値 | 表示規則 / 例 | 欠落時 |
| --- | --- | --- | --- |
| `{Date}` | 撮影日時 | `YYYYMMDD` / `20261008` | 使用時はエラー |
| `{Time}` | 撮影日時 | `HHmmss` / `123456` | 使用時はエラー |
| `{DateTime}` | 撮影日時 | `YYYYMMDD_HHmmss` / `20261008_123456` | 使用時はエラー |
| `{Original}` | カタログ元画像の stem | `DSCF0123`（拡張子なし） | エラー |
| `{CameraMaker}` | cameraMaker | 正規化表示名 / `FUJIFILM` | 空欄 |
| `{Camera}` | camera | `X-H2S` | 空欄 |
| `{LensMaker}` | lensMaker | 正規化表示名 / `FUJIFILM` | 空欄 |
| `{Lens}` | lens | `XF100-400mm` | 空欄 |
| `{FilmSim}` | filmSim | 検証済み表示対応 / `PROVIA` | 空欄 |

撮影日時は記録された現地の壁時計時刻を使い、タイムゾーン変換や現在時刻への置換はしません。ファイル更新日時は代用しません。必要な時刻成分がない場合はエラーにします。FilmSim の未確認コードは空欄と診断にし、誤ったフィルム名へ変換しません。


## メーカーの正規化と重複省略

比較キーは前後空白の除去、ASCII の大小文字統一、空白の連続整理、明示的な既知別名表で生成します。初期の例として `FUJIFILM`、`FUJI FILM`、`FUJIFILM CORPORATION` を `FUJIFILM` として扱います。別名表はテストを伴って追加し、任意の会社名接尾辞削除や部分一致は行いません。Unicode 表記差の追加対応は実データで必要性を確認します。

カメラ・レンズ両メーカーが存在し、比較キーが一致し、テンプレートに両方のトークンがある場合だけ、重複省略 ON で LensMaker の展開を空にします。CameraMaker の位置だけを残します。LensMaker しか指定されていない場合は省略しません。未知メーカーも非空の正規化キーが一致すれば同一として比較できます（Phase 5 のユーザー指示に合わせた更新）。空文字・欠落同士は同一メーカーとみなしません。

```text
テンプレート: {CameraMaker}_{Camera}_{LensMaker}_{Lens}
入力: CameraMaker = FUJIFILM、Camera = X-H2S
      LensMaker = FUJIFILM CORPORATION、Lens = XF100-400mm
ON:  FUJIFILM_X-H2S_XF100-400mm
OFF: FUJIFILM_X-H2S_FUJIFILM_XF100-400mm
```

## 空欄、整形、衝突

空欄トークンを含む箇所だけ、隣接する `_`、`-`、空白の区切り列を一つにし、stem の端の残余区切りを除きます。利用者が明示したリテラル全体を一括置換しません。プレビューは空欄項目と省略理由も表示します。stem が空になる場合は拒否します。

FilenameSanitizer はメタデータ由来の禁止文字 `< > : " / \ | ? *` を `_` に置換し、制御文字を除去し、末尾の空白・ドットを除去します。`.`、`..`、Windows 予約名（拡張子付きの CON / PRN / AUX / NUL / COM1〜9 / LPT1〜9 を含む）は拒否します。先頭ドット名と上付き ¹ / ² / ³ の COM / LPT 予約名も拒否します。OS の成分長・フルパス長は Platform で確認し、超過時は切り詰めずエラーにします。Unicode の単位と SDK の長さ制限は実機検証が必要です。

衝突時は `name.jpg` → `name_001.jpg` → `name_002.jpg` と候補を作ります。処理内で確定済みの名前も衝突として扱い、OS の大小文字・Unicode 等価性も考慮します。FileSystem は保存時に再確認し、既存ファイルを置換しない確定方法を使います。安全な方法の検証完了までは非上書きを保証済みとしません。

## Phase 5 / 6 の実装状態

メーカーの比較キー・表示名を作る ManufacturerNormalizer は実装済みです。既知の FUJIFILM 別名と TAMRON / SIGMA、未知の非空文字列の比較に対応します。元 Metadata は不変です。[正規化の仕様](phase5-manufacturers.md)

TemplateParser / TokenResolver とメーカー省略は Phase 6 で実装しました。設定 UI は Phase 8、書き出しへの統合は Phase 9 に残します。[Phase 6 の詳細](phase6-templates.md)


Phase 6 の結果は未サニタイズの候補名です。メタデータ内の禁止文字や予約名、衝突は Phase 7 以降で処理します。FilmSim のコード解釈は ExifTool 境界の責務で、TokenResolver は正規化済み文字列のみを受け取ります。

## Phase 7 の実装状態

FilenameSanitizer / CollisionResolver を実装しました。制御文字はユーザーの Phase 7 指示に合わせて除去へ統一しました。core では明示したバイト長制約を検証し、OS の比較キーを必須入力として既存名・セッション予約名から衝突候補を生成します。ファイル I/O・実保存は行いません。[具体的な契約と残課題](phase7-filename-safety.md)

## Phase 8 の UI

書き出し画面のテンプレート入力とメーカー省略により、同じ core と FilenameSanitizer を使うサンプルプレビューを更新します。サンプル情報を明記し、実写真からの取得・衝突名・長さ制約は未確定と表示します。設定はプリセット保存対象に宣言しました。[UI の範囲](phase8-export-dialog.md)

## Phase 8 の入力改善

ユーザー指示により対応トークンを 12 個に変更しました。内部の extension は必須入力として維持します。ボタンはテンプレート末尾へ追加し、区切りは入力欄で編集します。旧プリセットの末尾 `.{Extension}` だけを読み込み・適用時に除去して移行します。他の位置のトークンはエラー、`{{Extension}}` は文字として保持します。

## ISO / FocalLength の廃止

ユーザー指示により ISO と FocalLength もトークンとボタンから削除しました。現在の対応数は 10 個です。旧テンプレートに残るこれらのトークンは未知トークンとしてエラーを表示し、黙って削除しません。ExifTool / MetadataResolver の既存の読取項目はこの UI 変更では変更しません。

## Phase 9 の実保存

9 トークンを実書き出しへ適用します。出力拡張子は実際の JPEG レンダリング結果から取得します。番号は衝突回避時だけ付加します。プレビューは衝突回避前の候補です。

CollisionResolver の比較キーは統合境界で試行名・予約名の完全一致に使い、全候補を実保存先の exists で確認して OS の同一性を判定します。SDK copy の非上書き契約と併用します。コピー開始後の失敗は安全に競合だけを区別できないため再試行せず、失敗として通知します。実機の保証は未確認です。[保存境界](phase9-export-integration.md)

## Sequence の廃止（2026-10-10）

現在の対応トークンは Date / Time / DateTime / Original / CameraMaker / Camera / LensMaker / Lens / FilmSim の9個です。Sequence はユーザー指示により廃止しました。通常は name.jpg、衝突したときだけ name_001.jpg / name_002.jpg とします。旧 UI 設定の末尾 `{Sequence}` とその直前の _ / - / スペース1文字だけは取り除きます。その他の位置はエラーとし、`{{Sequence}}` は文字として保持します。

## トークン値のハイフン表記（2026-10-10）

ユーザー指示により、各トークン値の前後空白を除き、連続する ASCII 空白類（スペース、タブ、改行等）を1つの区切りへ整理して `-` に変換します。大文字・小文字は保持します。Original、カメラ・レンズ・メーカー名にも適用します。テンプレートに直接書いた `_`、スペース、ハイフンや、値にもともと含まれる数字・記号・アンダースコアは一括変更しません。Date / Time / DateTime の既存書式も維持します。元 Metadata と元画像は変更しません。

例：`XF200mm  F2 R LM   OIS WR` → `XF200mm-F2-R-LM-OIS-WR`。`{CameraMaker}_{Lens}` の `_` はトークン間の区切りとして残ります。

FilmSim は ExifTool 境界の正規化済み ID を、[Rust 版の表示名規則](https://github.com/Kelly-jp/fphoto-renamer/blob/fd706e4ebf29a5f0a2c8afba471190d115d3765d/crates/core/src/exif_reader.rs) に対応付けてからハイフン化します。内部 ID・採用元・優先順位は変更せず、タグ名や未確認コードの推測を TokenResolver へ持ち込みません。

| 内部 ID | ファイル名での表記 |
| --- | --- |
| PROVIA / VELVIA / ASTIA | PROVIA / Velvia / ASTIA |
| PRO_NEG_STD / PRO_NEG_HI | PRO-Neg-Std / PRO-Neg-Hi |
| CLASSIC_CHROME / CLASSIC_NEGATIVE | CLASSIC-CHROME / CLASSIC-Neg |
| ETERNA / ETERNA_BLEACH_BYPASS | ETERNA / ETERNA-BLEACH-BYPASS |
| NOSTALGIC_NEG / REALA_ACE | NOSTALGIC-Neg / REALA-ACE |
| MONOCHROME / ACROS / SEPIA | MONOCHROME / ACROS / SEPIA |
| MONOCHROME_R / MONOCHROME_Y / MONOCHROME_G | MONOCHROME+-R-FILTER / MONOCHROME+-Ye-FILTER / MONOCHROME+-G-FILTER |
| ACROS_R / ACROS_Y / ACROS_G | ACROS+-R-FILTER / ACROS+-Ye-FILTER / ACROS+-G-FILTER |

比較用に既知メーカーを正規化する従来の規則と、FilmSim の表示名変換は、この空白整形に先立って適用します。未知の内部文字列を既知 FilmSim と推測せず、既存の読取境界での未知コード欠落・警告を維持します。

参照日は2026-10-10。指定された develop の取得コードと上記固定コミットのバイト列を照合済みです。exif_reader.rs の SHA-256 は `e7b46acd65bf41ee557e01ec90e5338295a611758cdd76530a8d0ab678da8091`。文字列表示規則を本プロジェクトの Lua で実装し、RAW 読取・部分一致・任意プロファイルの推測ロジックは移植していません。
