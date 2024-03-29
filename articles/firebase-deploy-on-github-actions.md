---
title: "GitHub ActionsでFirebase Deployを行う"
emoji: "🦁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["firebase","gcp","githubactions"]
published: true
---

GitHub ActionsでFirebase Deployを行う時のサンプルです。

Firebase CLIで大昔はService Accountが使えなかったので、 `firebase login:ci` を実行して `FIREBASE_TOKEN` を生成していましたが、現在はこの方法は非推奨となっています。
この方法はお手軽ではありますが、いくつか使いづらい点がありました。

* `FIREBASE_TOKEN` を発行した人の権限でDeployされる
* 発行している `FIREBASE_TOKEN` が分からないので、Rotateが難しい

ということで、今は [Service Accountを使ってfirebaseコマンドを実行](https://github.com/firebase/firebase-tools#using-with-ci-systems) するようになりました。
Cloud Buildsでは公式ドキュメントに [Exampleがあります](https://cloud.google.com/build/docs/deploying-builds/deploy-firebase) 
Cloud BuildsだとService Accountが元々あるので、Firebaseの権限さえService Accountに持たせれば、やることはありませんね。

GitHub Actionsの場合は、Service Accountを使うための設定が必要になります。
設定は [GitHub Actions + google-github-actions/auth で GCP keyless CI/CD](https://zenn.dev/vvakame/articles/gha-and-gcp-workload-identity) の通りにすればできます。
Service Accountでの認証ができれば、Firebase CLIを実行するだけなので、npmでinstallして実行しています。

``` deploy.yaml
name: Deploy

on:
  push:

jobs:
  build:
    runs-on: ubuntu-latest
    environment: 
      name: production
    permissions:
      contents: read
      id-token: write
    env:
      GCLOUD_VERSION: "412.0.0"
      NODE_VERSION: 18
    steps:
      - uses: actions/checkout@v3
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1.0.0
        with:
          workload_identity_provider: projects/${{ vars.GOOGLE_CLOUD_PROJECT_NUMBER }}/locations/global/workloadIdentityPools/github-actions/providers/gha-provider
          service_account: github-actions@${{ vars.GOOGLE_CLOUD_PROJECT_ID }}.iam.gserviceaccount.com
          access_token_lifetime: 1200s
          create_credentials_file: true
      - uses: google-github-actions/setup-gcloud@v1
        with:
          version: ${{ env.GCLOUD_VERSION }}
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: ${{ env.NODE_VERSION }}
      - run: npm install -g firebase-tools
      - run: firebase deploy --project=${{ vars.GOOGLE_CLOUD_PROJECT_ID }} --only=hosting
```

[Example Repository](https://github.com/sinmetal/firebase-deploy)
