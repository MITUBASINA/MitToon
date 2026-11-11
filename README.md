# MitToon

VRChat アバター向けのトゥーンシェーダーです (Unity 2022.3 / Built-in Render Pipeline)。

## 導入 (VCC)

1. VCC の Settings > Packages > Add Repository に、次の URL を追加します。
   `https://mitubasina.github.io/MitToon/index.json`
2. プロジェクトの Manage Project から MitToon を追加します。

## ライセンス

MIT License です。詳しくは `Packages/com.mittoon.shader/LICENSE.md` と `ThirdPartyNotices.txt` をご覧ください。

## 連絡先

X: [@MITUBASINA](https://x.com/MITUBASINA)

## リリース手順 (開発者向け)

1. `Packages/com.mittoon.shader/package.json` の `version` を上げてプッシュします。
2. Actions の **Build Release** を実行します。
3. リリースが作られると **Build Repo Listing** が動き、GitHub Pages のリスティングが更新されます。

初回だけ、次の設定が必要です。
- Settings > Secrets and variables > Actions > Variables に `PACKAGE_NAME` = `com.mittoon.shader`
- Settings > Pages の Source を「GitHub Actions」

このリポジトリは [vrchat-community/template-package](https://github.com/vrchat-community/template-package) から作成しています。
