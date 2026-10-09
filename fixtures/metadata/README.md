# メタデータ検証フィクスチャ

- `phase2-fujifilm.json`: X-H2S の許諾済み実取得で確認したタグ構成をもとに作った合成 JSON。SourceFile と撮影日時は架空値。メーカー・機種・レンズ等は型と対応確認用。
- `phase2-sample.xmp`: テスト用に記述した合成 sidecar。実写真から抽出した内容ではない。
- `phase2-sample.jpg`: 自作の 2×2 ピクセル JPEG に ExifTool 13.55 で合成テスト用 EXIF を設定したもの。写真、位置情報、シリアル番号を含まない。

- `phase2-lightroom-profile.xmp` / `phase2-lightroom-look.xmp`: 自作の CRS プロファイル検証用 sidecar。CameraProfile と構造内 Look Name の取得・優先順位を確認します。

本プロジェクトの MIT License を適用します。ExifTool の出力形式確認には 13.55 を使用しました。読取テストは JPEG / XMP の前後バイト列不変を確認します。個人の画像やメタデータをこのディレクトリへ追加しないでください。
