---
title: "Cloud Run with IAP / 任意の環境のURLを作る"
emoji: "🦁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["CloudRun","gcp"]
published: true
---

Cloud Run with IAPを利用しているアプリを開発中にPull Requesのレビューをする時、専用の環境で動作確認したいと言われたので、考えてみた。
Cloud Runには [Revision Tagを利用して、任意のRevisionにRequestを送る独自URLを発行する機能](https://cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration#tags) があるが、IAP([Identity Aware Proxy](https://cloud.google.com/iap))を利用している場合、Serverless NEGを利用して、HTTP LBからRequestを受けるため、この機能を使っただけでは解決しない。

# 最終的なCloud Runの構成

![](/images/cloudrun-pr-deploy/gcp.jpg)

# 作る時に考えたこと

## 前提

* Identity Aware Proxyがかかっている
* MarkdownをHTMLに変換しているStaticなWeb Site
* 開発チームは数人
* 更新頻度はそんなに高くはない

対象はIAPをかけているStaticなWeb SiteでPull Requestの時に実際に動いている画面が見たいというのが今回の要望。
環境を作って振り分けれそうなレイヤーとして [URL maps](https://cloud.google.com/load-balancing/docs/url-map) がある。
URL mapsではpathかhostでBackend Serviceが切り替えられる。
今回のケースではpathを変えてしまうとWeb Siteがうまく動かなくなる可能性があるので、hostを変えることにした。
hostを変えると新たな課題として、SSL証明書の管理が出てきた。
ワイルドカード証明書が使えればよいが [Google Managed SSL 証明書](https://cloud.google.com/kubernetes-engine/docs/how-to/managed-certs) はワイルドカード証明書に対応していない。
Google Managed SSL 証明書をPull Requestごとに作るとProvisioningに時間がかかってしまう。
そのため、Pull Requestごとに新たな環境を作るのではなく、事前にいくつかの環境を作っておき、指定した環境にDeployすることにした。
[1つのSSL証明書で100のドメインを設定できる](https://cloud.google.com/load-balancing/docs/quotas#ssl_certificates) のでそれなりの数の環境を作ることができる。
ただ、SSL証明書にドメインを追加, 削除した時はProvisioning Statusとなり、SSL証明書自体がしばらく使えなくなるので、注意が必要だ。
Target Proxyには15個までSSL証明書リソースを設定できるので、最大1500環境を作ることができる。

## 事前に環境ごとに用意しておくもの

* Serverless NEG ([Cloud Revision Tagを指定しておく](https://cloud.google.com/sdk/gcloud/reference/compute/network-endpoint-groups/create#--cloud-run-tag))
* Backend Service

alpha, beta...のように環境を用意して、上記の3つのリソースを作りURL Mapsのhostで切り替えるようにする。
`https://alpha-hoge.example.com` がRequestされたら、alpha用のBackend Serviceに割り振り、alpha tagが付いているCloud Run RevisionがResponseを返すようにする。
これを必要な環境の数だけ用意しておく。

# CI/CD

環境の数に限りがあるためBranch Pushごとに自動的にDeployするのではなく、Pull RequestのコメントをトリガーにDeployを行うことにした。
`/deploy alpha` とコメントするとalpha環境にDeployする。
コメントをトリガーして動かすのは [GitHub Actions](https://github.co.jp/features/actions) が簡単だろうと思い、GitHub Actionsで作った。
BuildやTestはBranch Pushで動いた方が便利だろうと思い、Cloud BuildでBuildとTest, GitHub ActionでDeployするという2つの段階に分けた。
Cloud Buildを使っている理由は、筆者が慣れているからと [Binary Authorization](https://cloud.google.com/binary-authorization) するなら、Cloud Buildを使うことになると思った程度なので、すべてGitHub Actionにしてもよい。

![](/images/cloudrun-pr-deploy/cicd.jpg)

### cloudubild.yaml

``` yaml
steps:
  - name: 'golang:1.16-buster'
    entrypoint: 'go'
    args: ['build', '.']
    env: ['GO111MODULE=on']
  - name: 'gcr.io/kaniko-project/executor:v1.6.0'
    args:
      - --destination=asia-northeast1-docker.pkg.dev/$PROJECT_ID/cloudrun-helloworld/$BRANCH_NAME:$COMMIT_SHA
      - --cache=true
      - --cache-ttl=6h

```

## GitHub Commentをトリガーに実際に動いている様子

![](/images/cloudrun-pr-deploy/github_pr_comment.jpg)

### github-action.yaml

permissionsには要らないものが入っている気がしている。

``` yaml
name: "deploy"
on:
  issue_comment:
    types: [created, edited]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write'
      issues: 'write'
      checks: 'write'
      pull-requests: 'write'
      statuses: 'write'
    steps:
      - name: "Check for Command"
        id: command
        uses: xt0rted/slash-command-action@065da288bcfe24ff96b3364c7aac1f6dca0fb027 #1.1.0
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}
          command: deploy
          reaction: "true"
          reaction-type: "eyes"
          allow-edits: "true"

      - name: "Get branch name"
        uses: xt0rted/pull-request-comment-branch@29fe0354c01b30fb3de76f193ab33abf8fe5ddb0 #1.2.0
        id: comment-branch
        with:
          repo_token: ${{ secrets.GITHUB_TOKEN }}

      - name: "Checkout"
        uses: actions/checkout@v2
        with:
          ref: ${{ steps.get_branch.outputs.head_ref }}

      - name: "Post Comment"
        uses: actions/github-script@v3
        env:
          MESSAGE: |
            Start Deploy to ${{ steps.command.outputs.command-arguments }}
            Branch: ${{ steps.comment-branch.outputs.head_ref }}
            Commit: ${{ steps.comment-branch.outputs.head_sha }}
        with:
          github-token: ${{secrets.GITHUB_TOKEN}}
          script: |
            github.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: process.env.MESSAGE
            })
      - name: "Google Auth"
        uses: "google-github-actions/auth@v0"
        with:
          workload_identity_provider: "projects/${{ secrets.PROJECT_NUMBER }}/locations/global/workloadIdentityPools/github-actions/providers/gha-provider"
          service_account: "github@${{ secrets.GCP_PROJECT }}.iam.gserviceaccount.com"
      - name: 'Set up Cloud SDK'
        uses: 'google-github-actions/setup-gcloud@v0'
        with:
          version: '369.0.0'
      - name: 'Use gcloud CLI'
        run: 'gcloud info'

      - name: "Deploy to Run"
        id: "deploy-to-run"
        uses: "google-github-actions/deploy-cloudrun@v0"
        with:
          service: "cloudrun-helloworld"
          image: "asia-northeast1-docker.pkg.dev/${{ secrets.GCP_PROJECT }}/cloudrun-helloworld/${{ steps.comment-branch.outputs.head_ref }}:${{ steps.comment-branch.outputs.head_sha }}"
          region: "asia-northeast1"
          tag: ${{ steps.command.outputs.command-arguments }}
          no_traffic: "true"
      - name: "Output Cloud Run URL"
        run: 'curl "${{ steps.deploy-to-run.outputs.url }}"'
      - name: "Post Comment"
        uses: actions/github-script@v3
        env:
          MESSAGE: |
            Finish Deploy to ${{ steps.command.outputs.command-arguments }}
            Branch: ${{ steps.comment-branch.outputs.head_ref }}
            Commit: ${{ steps.comment-branch.outputs.head_sha }}
        with:
          github-token: ${{secrets.GITHUB_TOKEN}}
          script: |
            github.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: process.env.MESSAGE
            })
```

# 余談

GitHub ActionでCloud RunをDeployするのに [google-github-actions/deploy-cloudrun](https://github.com/google-github-actions/deploy-cloudrun) を使った。
前提条件として、Google Cloud SDKの認証を行う必要があるため、[google-github-actions/auth](https://github.com/google-github-actions/auth)でWorkload Identity Federationを行ったのだが、ここでちょっとハマった。
Deployに失敗するが、 `The process '/opt/hostedtoolcache/gcloud/369.0.0/x64/bin/gcloud' failed with exit code 1` と出力されるだけで他に情報がなかったので、なぜ失敗するのか分からなかった。
GitHub Token Permissionや、GCPのService Accountの権限設定など見直したりしてみたが、よく分からなかった。
試しに [google-github-actions/setup-gcloud](https://github.com/google-github-actions/setup-gcloud) に変更してみたが、 `google-github-actions/setup-gcloud failed with: The process '/opt/hostedtoolcache/gcloud/369.0.0/x64/bin/gcloud' failed with exit code 1` と出るだけで特に情報は増えなかった。
ただ、gcloud commandが全く動かない状態なのはなんとなく分かったので、割と最初の方で何かが失敗しているだろうと思った。

結果としては間違っていたのはwithの中でのsecretの扱いだった。
google-github-actions/authの中で使うProjectIDやProjectNumberをsecretに入れていたのだが、その設定方法が間違っていた。
google-github-actions/authのstep自体は成功していたので、これでうまくいってるのだろうと思いこんでいたが、ProjectIDとProjectNumberが空っぽで作られていたのか、認証が失敗した？か何かでgcloud commandが動かなかったようだ。

## 誤り

```
- name: "Google Auth"
  uses: "google-github-actions/auth@v0"
  env:
    GCP_PROJECT: ${{ secrets.GCP_PROJECT }}
    PROJECT_NUMBER: ${{ secrets.PROJECT_NUMBER }}
  with:
    workload_identity_provider: "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/gha-provider"
    service_account: "github@$GCP_PROJECT.iam.gserviceaccount.com"
```

## 正しい

```
- name: "Google Auth"
  uses: "google-github-actions/auth@v0"
  with:
    workload_identity_provider: "projects/${{ secrets.PROJECT_NUMBER }}/locations/global/workloadIdentityPools/github-actions/providers/gha-provider"
    service_account: "github@${{ secrets.GCP_PROJECT }}.iam.gserviceaccount.com"
```