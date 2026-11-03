# リリース手順（ハンドオーバー）

Keysy は **ローカルで Developer ID 署名 + Apple 公証** してから GitHub Releases に出す。
公証していないと、ダウンロードしたユーザーの Mac で「ゴミ箱に入れる」しか出ず起動できない
（Gatekeeper 判定 `source=Unnotarized Developer ID`）。署名だけでは不十分。

## 通常のリリース（毎回これだけ）

```sh
git checkout main && git pull        # main をクリーンかつ origin と一致させる
./release.sh 0.2.0                   # 自動生成のリリースノート
./release.sh 0.2.0 notes.md          # リリースノートを自分で書く場合
```

`release.sh` がやること:

1. 事前チェック — main / クリーン / origin と一致 / タグ未使用 / 最新リリースより新しい番号 / 公証プロファイルあり
2. `build.sh` でビルド → Developer ID 署名（hardened runtime）→ .app と .dmg を公証・staple
3. 検証 — Info.plist のバージョン一致、`spctl` が `accepted`、.dmg と zip 内 .app の staple
4. `vX.Y.Z` タグを push → `gh release create` で `Keysy.dmg` と `Keysy.zip` を添付

公証は Apple 側の処理待ちで数分かかる（.app と .dmg の 2 回）。

## バージョン番号のルール

- タグは `vX.Y.Z`、アプリの `CFBundleShortVersionString` は `X.Y.Z`。**必ず一致させる**（release.sh が保証）。
- アプリ内アップデーター（`Sources/Keysy/Updater.swift`）は GitHub の latest release の
  タグとアプリのバージョンを比べ、新しければ **`.zip` アセット** を入れて再起動する。
  - zip を付け忘れると更新できない。
  - `VERSION` を付けずに `build.sh` を実行すると既定の `0.1.0` になり、
    それを配ると毎回「更新があります」と出続ける。リリースは必ず `release.sh` 経由で。
- 番号を飛ばす・戻すのは不可（release.sh が最新より新しいことをチェックする）。

## 一度だけのセットアップ（新しい Mac の場合）

1. **Developer ID Application 証明書** がキーチェーンにあること
   `security find-identity -v -p codesigning` に
   `Developer ID Application: Junki Omura (W2Z92AW32J)` が出れば OK。
   無ければ Xcode → Settings → Accounts → Manage Certificates で作成 / 書き出し・取り込み。
2. **公証用プロファイル `keysy-notary`** を作る（アプリ用パスワードは https://account.apple.com で作成。
   他アプリ用に作ったものを流用しても可）:
   ```sh
   xcrun notarytool store-credentials keysy-notary --apple-id junki.ohmura@gmail.com --team-id W2Z92AW32J
   ```
   別名のプロファイルを使うときは `NOTARY_PROFILE=<名前> ./release.sh X.Y.Z`。
3. `gh auth status` で GitHub にログイン済みであること。

## 手動で確認したいとき

```sh
spctl -a -vvv -t exec build/Keysy.app       # → accepted / source=Notarized Developer ID
xcrun stapler validate build/Keysy.dmg
xcrun notarytool log <submission-id> --keychain-profile keysy-notary   # 公証が Invalid のとき理由を見る
```

## 失敗したとき

- **公証が Invalid** — `notarytool log` で理由を見る。多くは署名漏れ・hardened runtime 無し。
- **リリース後に問題発覚** — 既存タグを付け替えず、修正して次の番号（例 0.2.1）を出す。
  アップデーターは番号比較なので、同じ番号の差し替えは既存ユーザーに届かない。
- **途中で止まった（タグ push 前）** — そのまま直して再実行して良い。
  **タグ push 後に gh release で失敗** — `gh release create vX.Y.Z build/Keysy.dmg build/Keysy.zip --generate-notes` を手で実行。

## 補足

- `.github/workflows/release.yml` は ad-hoc 署名の手動フォールバックのみ（公証されないので通常は使わない）。
- 履歴: v0.1.0（2026-11-03）が初リリース。
