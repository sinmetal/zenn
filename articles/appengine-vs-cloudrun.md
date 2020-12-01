---
title: "Google App Engine VS Cloud Run"
emoji: "🦁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["GoogleAppEngine","CloudRun","GoogleCloudPlatform"]
published: false
---

ちょいちょい、これから Web Application を作るなら、[Google App Engine](https://cloud.google.com/appengine/) と [Cloud Run](https://cloud.google.com/run) どちらを使うべきか？と聞かれるので、思いの丈を綴っておこうと思う。

# 結論

正直、僕もよく分からない。
現状、僕はどちらにも好きなところと嫌いなところがあって、使い分けている。

この先は2つを比べて、僕がどちらを使うのかを判断する時の材料を書いていく。
Google App Engine(以下App Engine) には Standard と Flex があるが、この記事では Standard を主に扱っている。
Cloud Run には fully managed と for Anthos があるが、この記事では fully managed を主に扱っている。

# App Engine と Cloud Run を比べてみる

### 課金体系

App Engine は Instance 課金、Cloud Run は 使用したリソースでの課金になる。
App Engine(automatic scaling, basic scaling) は Instance が起動してから、最後のリクエストの15分後に終了するまでを単位にしている。
Cloud Run は 100ms 単位で切り上げで計算される。
そのため、1min毎に5sec処理するみたいなことをした時に、App Engine は Instance が終了しないので、ずっと課金対象だが、Cloud Run は都度 5000ms 課金されるだけで済む。
cron で定期的に起動するような時やリクエスト頻度が少なくぽつぽつ来るケースだと Cloud Run が有利で、心がCloud Runに傾く。

### マシンスペック

### Deploy

### スピンアップタイム

### Runtime

### 認証

### Static Contents

### Cloud Tasks, Cloud Scheduler での Deadline

### Observability

# Cloud Run で悩ましいところ

CPU割り当てなくなってから、復活するのどうしようかなー

# App Engine と Cloud Run を Mix するために

Serverless NEG

Custom Domain

Cloud Run が IAP 対応してないからなー

Tasks とかだと Serverless NEG 経由しないから、まぁいいか