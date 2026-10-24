# GitHub Releaseの作成

## 仕組み

`.github/workflows/release.yml`は`vMAJOR.MINOR.PATCH`タグのpushで起動します。タグのコミットが`main`に含まれ、`Info.lua`とタグの版が一致し、`CHANGELOG.md`にその版の説明がある場合だけ進みます。自動公開はせず、添付物をそろえたRelease下書きを作成します。

1. `macos-15`のApple Siliconランナーでテスト用Lua 5.1.5をSHA-256検証済みの公式ソースからビルドする。
2. 既存スクリプトで固定版ExifTool・Perlを準備する。Perlの標準テストも省略しない。
3. 全Luaテスト・配布テストを実行し、macOS / WindowsのZIPを生成する。
4. ZIPの内容・ハッシュ・ライセンス、macOSのad-hoc署名、同梱ExifToolと解凍済みプラグインの処理を確認する。
5. `windows-2022`で同じZIPを受け取り、Windows同梱ExifToolの版・合成JPEGのMake/Model読取・入力ハッシュ不変を確認する。外部PerlやPATH上のExifToolは使わない。
6. 両ジョブ成功後、Ubuntu上で添付物のSHA-256とリリースノートを再確認し、GitHub CLIでRelease下書きを作る。

ビルドの成果物をWindows検証・Release作成へそのまま渡し、公開前に再ビルドしません。ZIP・チェックサム・ノート以外の予期しないファイルがある場合も停止します。

## 最初の設定

- このワークフローを含む変更を`main`へマージし、リポジトリのGitHub Actionsを有効にする。
- 組織・リポジトリでActionsを制限している場合は、使用するGitHub公式のcheckout / setup-node / setup-python / upload-artifact / download-artifactを許可する。
- Release作成ジョブは自動の`GITHUB_TOKEN`に`contents: write`を指定する。組織ポリシーで許可されているか確認する。PATやDeveloper ID証明書の登録は不要。

Actionは確認済みの完全コミットSHAで固定しています。更新時は公式リポジトリの対応タグと変更内容を確認して差し替えます。ランナーは`latest`を使わず、macOSでは`arm64`も明示確認します。初回はPerlのコンパイルと標準テストのため時間がかかります。現在はビルド済みバイナリのキャッシュ共有を行いません。

## リリースの準備

1. `src/FujiPhotoRenamer.lrplugin/Info.lua`の`major` / `minor` / `revision`を決める。タグとZIP名にはこの3値を使い、`build`は含めない。同じ3値で別の公開物を出さない。
2. `CHANGELOG.md`の`Unreleased`から対象の変更を移し、版別の見出しを作る。例えばInfo.luaが`0.10.2`なら以下の形式にする。

   ```markdown
   ## Unreleased

   ## [0.10.2] - YYYY-MM-DD

   ### Fixed

   - リリースに含まれる変更内容。
   ```

   `## 0.10.2`形式も利用可能。対象の見出しは1個、本文は必須。`Unreleased`を代わりに使うことはできない。Releaseノートへは対象見出しの本文だけを採用する。

3. 変更をPRで`main`へマージする。ローカル確認が必要なら、空の出力先を指定して次を実行する（ZIPをビルドする前の検査）。

   ```sh
   node scripts/release.mjs prepare v0.10.2 build/release-preview
   ```

4. 最新の`main`でタグを作成し、そのタグだけをpushする。

   ```sh
   git switch main
   git pull --ff-only origin main
   git tag -a v0.10.2 -m 'Fuji Photo Renamer v0.10.2'
   git push origin v0.10.2
   ```

タグは正式な`v数字.数字.数字`だけに対応します。先頭ゼロ、`-beta`等の接尾辞、Info.luaと異なる版は拒否します。現在のCHANGELOGが`Unreleased`だけなら、先に版別見出しを用意してください。タグやReleaseはこの機能の導入だけでは作成しません。

## 下書きの確認と公開

Actionsの`Release draft`が成功すると、Releasesに下書きができます。以下の4ファイルが添付されます。

```text
fuji-photo-renamer-lightroom-plugin-<version>-macos.zip
fuji-photo-renamer-lightroom-plugin-<version>-macos.zip.sha256
fuji-photo-renamer-lightroom-plugin-<version>-windows.zip
fuji-photo-renamer-lightroom-plugin-<version>-windows.zip.sha256
```

対象コミット・版・Releaseノート・添付物を確認し、ZIPを解凍してLightroomで確認後、GitHub画面から公開します。初期の配布を検証扱いにする場合は、公開時にPre-releaseを選択します。ワークフローは公開状態・Latest扱い・リポジトリ設定を自動変更しません。

macOSの署名はad-hocのままで、Developer ID署名・公証を追加するものではありません。Windowsジョブの成功も、Lightroom ClassicのUI・書き出し・Explorer操作の実機確認を意味しません。[残る環境検証](phase12-packaging.md)

## 失敗・再実行

- タグ、版、CHANGELOGが不一致ならビルド前に停止する。公開前に必要な修正をmainへマージし、原則として新しい版・タグで実行する。
- ビルドやWindows検証が失敗するとReleaseを作らない。Actionsで原因を修正・確認する。
- 通信等の一時的な失敗は同じタグの実行を再実行できる。`Re-run all jobs`では新規ランナーで再ビルドする。同じタグの実行を並行に進めないためconcurrencyを設定している。
- 既存Releaseがあると`gh release create`は失敗する。下書き・公開済みのどちらも上書きしない。アップロード途中に失敗した場合は下書きが残ることがあるため、添付物を確認し、不要な未公開下書きだけを管理者が明示的に削除してから再実行する。公開済みReleaseやタグは自動削除しない。
- Actionsの中間成果物は14日間保持する。期限後に失敗ジョブだけを再実行しても取得できない場合は全ジョブを再実行する。

## ローカルテスト

```sh
node --test tests/release_test.mjs tests/packaging_test.mjs
python3 tests/windows_release_test.py
```

Windows機では、検証済みWindows ZIPに対して次も実行できます。

```sh
python scripts/verify-windows-release.py dist/fuji-photo-renamer-lightroom-plugin-0.10.2-windows.zip
```

## 出典

- [GitHubランナーのOSとCPU](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub CLIのRelease作成・draft・verify-tag](https://cli.github.com/manual/gh_release_create)
- [Release管理と公開前の添付](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
