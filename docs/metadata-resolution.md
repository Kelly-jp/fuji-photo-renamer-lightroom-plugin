# メタデータの解決

## 入力と探索

元画像パスは Lightroom カタログから読み取り、取得 API とオフライン写真の扱いを SDK で確認します。書き出し後の名前から元画像を逆算しません。

初期の対応付けは拡張子を除いた元ファイル名（stem）の完全一致です。拡張子の大文字・小文字は許容しますが、stem の大小文字差や Unicode 正規化差は曖昧性として検証します。再帰探索、任意フォルダ検索、撮影時刻だけの推測マッチは行いません。

| 元画像 | 初期探索規則 |
| --- | --- |
| JPG / JPEG | 元 JPG を JPG 入力とし、選択した場所で同じ stem の RAF / DNG を探索する。 |
| RAF / DNG | 元 RAW 自体を RAW 入力とし、同階層の同じ stem の JPG / JPEG を探索する。JPG 起点の RAW 探索設定は適用しない。 |
| その他 | 初期検証対象外として明示的に拒否する。 |

JPG 起点の RAW 探索は、同階層のみ、1 つ上のみ、同階層 → 1 つ上の 3 モードです。最後のモードは同階層に一意な RAW があるなら採用し、なければ親を調べます。RAF と DNG の両方など、同じ探索階層に複数候補がある場合は黙って選ばず、その写真をエラーにします。ルートの親探索は打ち切ります。

XMP は、選択した RAW に隣接する `<stem>.xmp` を第一候補、元画像に隣接する `<stem>.xmp` を第二候補とする初期設計です。同じ実体は重複排除します。異なる XMP が複数存在すれば優先順で黙って捨てず、曖昧エラーにします。複数 XMP 同士の合成は初期範囲外です。この対応付けは実際の Lightroom / カメラの配置例で検証します。

存在しない XMP / 関連 RAW / 関連 JPG は Missing とし、残る入力を使います。元画像自体の不在、アクセス拒否、破損、ツール失敗は ReadError として報告します。未検証の読取エラーを欠落としてフォールバックしません。

## 項目単位の採用

1. 各入力を ExifTool で読み取り、グループ付きタグ名を保存する。
2. タグ対応表に従い共通項目へ変換する。型、値、採用タグを保持する。
3. 項目ごとに XMP → RAW → JPG を走査し、最初の有効値を採用する。
4. 採用値と sourceKind・sourcePath・tag、欠落理由を記録する。

「有効」は型と項目別の妥当性を満たす値です。未定義、null、空文字、空白のみ、日付不正、対象外の構造は採用しません。数値 0 や false を一般的な真偽判定で欠落にしないでください。ISO / 焦点距離は正の値を要求します。未知のメーカー文字列は有効で、既知別名に無理に置換しません。

| 項目 | XMP | RAW | JPG | 採用結果 |
| --- | --- | --- | --- | --- |
| cameraMaker | FUJIFILM | FUJIFILM | FUJIFILM | XMP |
| lens | 欠落 | XF100-400mm | XF100-400mm | RAW |
| filmSim | 欠落 | PROVIA | 欠落 | RAW |
| iso | 欠落 | 欠落 | 800 | JPG |

一部の値を持つ XMP があっても RAW / JPG の読み取りを省略しません。必要項目が全て揃う場合のみ、不要な入力読み取りの省略を検討できます。初期段階では最適化より再現性を優先します。

## 共通項目とタグ候補

以下はタグ対応を検証するための候補であり、全機種・全形式で存在する保証はありません。候補内の優先順位は実データで確認して固定します。

| 共通項目 | ExifTool の候補 | 注意点 |
| --- | --- | --- |
| captureDateTime | EXIF DateTimeOriginal、XMP の対応する撮影日時 | CreateDate / ファイル更新時刻を無条件で代用しない。 |
| cameraMaker | Make | 表示・比較の正規化は core で行う。 |
| camera | Model | レンズ名と混同しない。 |
| lensMaker | LensMake | 欠落時にカメラメーカーから推定しない。 |
| lens | LensModel、検証済みの LensID / Composite Lens | 複数候補や推測名の扱いを固定する。 |
| filmSim | FujiFilm FilmMode などの MakerNotes | 白黒モード、DNG 変換時の欠落、XMP の対応項目を別途検証する。 |
| iso | ISO | スカラーへの変換規則を確認する。 |
| focalLength | FocalLength | 実焦点距離。35mm 換算と混同しない。 |

日時は一つの撮影日時項目として採用し、Date / Time / DateTime を全て同じ値から派生させます。XMP の日付と RAW の時刻を合成しません。JPG は元画像または対応 JPG であり、レンダリング済み JPEG を追加のフォールバック元にはしません。

## 読取境界と検証用コマンド

次は ExifTool が用意された環境での読み取り調査例です。開発用コマンドであり、同梱済みツールはまだありません。

```sh
exiftool -j -G1 -s sample.RAF
exiftool -j -G1 -s sample.xmp
exiftool -j -G1 -s sample.jpg
```

実装時は絶対パス、ユーザー設定ファイルの無効化、オプションと入力パスの分離、ファイル名文字コードを公式 CLI 資料で確認します。JSON のグループを捨てて同名タグを上書きしないでください。プラグイン自身が元画像へタグを書き戻すことはありません。

公式の [FujiFilm タグ一覧](https://exiftool.org/TagNames/FujiFilm.html) には FilmMode が記載されていますが、RAF の各機種で必要な 5 項目が揃うかは未検証です。[タグ名の調べ方](https://exiftool.org/TagNames/) を参照し、取得結果と対応表をフィクスチャ化します。

## Phase 2 で確認した単体取得

ExifTool 13.55 で許諾済み X-H2S RAF の Make / Model / LensMake / LensModel / FilmMode / Saturation を実取得し、グループ付きタグを確認しました。LensMake は FUJIFILM として取得でき、推定は不要でした。FilmMode = 0 は PROVIA として扱い、0 を欠落にしません。白黒・ACROS は確認済み Saturation コードを先に判定します。全機種・全レンズへ一般化しません。

合成 JPEG / XMP でもタググループを確認しています。ラッパーの詳細な対応表は [Phase 2 記録](phase2-exiftool.md#確認したタグ対応) を参照してください。日時の暦検証・トークン書式、Composite LensID による推測、Phase 2 時点では入力探索・項目別マージは未実装でした。入力探索は Phase 3 に追加し、項目別マージは未実装です。XMP FilmSim は、実ファイルで確認した CRS の既知の LookName / CameraProfile に限って対応しています。採用する日付の有効性は後続の項目解決・トークン処理で検証するため、Phase 2 の文字列取得だけを妥当性確認済みとはみなしません。

### XMP の編集プロファイル

2026-10-09 の修正で、Rust 版 fphoto-renamer の取得ロジックを参考に `XMP-crs:LookName`、`XMP-crs:CameraProfile`、`XMP-crs:CameraProfilesProfileName` を固定取得対象に追加しました。許諾された XMP の Camera PROVIA/Standard を PROVIA と解決しています。これはユーザーが現像で選択した編集プロファイルの解釈です。撮影時 MakerNotes とは採用元を区別します。

既知名だけを対応させ、未知のカスタム名・Adobe Color 等は FilmSim として採用しません。XMP 内は Look 名を先に採用し、RAW / JPG は撮影時コードを優先します。異なるファイルの項目別マージは引き続き後続 Phase の責務です。[詳細な修正根拠](phase2-exiftool.md#xmp-filmsim-の修正2026-10-09)

## Phase 3 の探索実装

[Phase 3 記録](phase3-metadata-sources.md) のとおり、3 モードの RAW 探索、同階層の JPEG 探索、RAW / 元画像に隣接する XMP 探索を実装しました。元 RAW 入力は直接採用し、JPG 起点の階層設定を適用しません。ExifTool からは独立し、入力メタデータの読み取り・マージには進みません。

stem の大小文字差は ASCII の大小文字だけ違う候補を明示的な曖昧エラーとして扱います。Unicode 正規化差は SDK での安全な同一性判定が未確認のため採用しません。同一性の重複排除は SDK で解決した正規パスの一致に限定し、ハードリンクを推定で同一としません。これらは初期の「stem 完全一致・推測しない」方針を具体化した制約です。
