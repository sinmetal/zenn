---
title: "sinmetalはなぜGoogle Cloudが好きなのか？"
emoji: "♥"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: false
---

[Google Cloud Champion Innovators Advent Calendar 2023](https://adventar.org/calendars/9217) の1日目の記事です。

Advent Calendarの初日ということもあり、sinmetalがなぜGoogle Cloudが好きなのかについて書きます。

筆者が初めてGoogle Cloudに出会ったのは2011年で、Google App Engineに恋い焦がれてから、ずっとGoogle Cloudを使い続けています。
現在、仕事ではかなり大きなシステムをGoogle Cloudで扱っていますが、個人で小さなシステムを作るのも好きです。
そんな小さなシステムから大きなシステムまで作れるところも魅力に感じています。
この記事では個人でよく作っている小さなシステムに注力しています。

まず、筆者が魅力に感じているGoogle Cloudの思想としてDatacenter as a Computerがあります。
日本語だとGoogle Developer AdvocateのKazunoriさんが[Google Cloud Platformの謎テクノロジーを掘り下げる](https://qiita.com/kazunori279/items/3ce0ba40e83c8cc6e580#datacenter-as-a-computer) で概要を書いてくれています。
ものすごく強力な1台のマシンを用意するのではなく、普通のマシンをたくさん横に並べて必要な時にすぐに使えるようにすることで、Google規模のサービスが効率よく動いています。
小さなシステムはこの仕組みに乗っかって、巨大なデータセンターの端っこを少し使わせてもらうことで、のんびり暮らすことができます。

Datacenter as a Computerを体現していて、好きなサービスがCloud RunとBigQueryです。
この2つはまさに使う時だけ瞬間的にリソースを使えるサービスです。
個人で小さなシステムを作る時もこの2つはよく使います。
この2つに加えて、データベースとしてCloud Firestoreを加えた3つを個人開発ではよく使っています。

# Cloud Run

Cloud RunはHTTP Requestを受け取る任意のContainer ImageをDeployして動かせるプロダクトです。
`https://{ランダム文字列}.a.run.app` のURLが付与され、証明書の管理などもすべてやってくれるので、個人でちょっとしたシステムを作るのにとても便利です。
無料枠が存在するので、自分だけしかアクセスしないものなら、無料枠の中で生きていけます。
まさにGoogleのデータセンターの端っこで生きている感じです。

Cloud Runでシステムを構築する場合、Containerを起動してからHTTP Requestを受け取れる状態になるまでの時間を短くすることを考える必要があります。
これはCloud RunがHTTP Requestが来てから、Containerを起動するため、Requestを送った人はその間待つ必要があるため、その時間を短くしたいからです。
最小Instance台数を指定して常時1台Instanceを起動しておくこともできますが、お金がかかるし、スケールアウトして2台目のInstanceが起動する時に同じ問題に当たるため、軽減することしかできません。
筆者はGoogle App Engineを使っている頃から長い間、起動時間を短くすることを考えて生きています。
現在はGo言語を使ってアプリケーションを作成して、小さなContainer Imageを作ることで、なるべく早く起動するようにしています。
Webフレームワークも使っておらず、net/http packageを使って書いています。
Dockerfileも3行しか無い短いものです。

```Dockerfile
FROM gcr.io/distroless/static-debian11
COPY ./app /app
ENTRYPOINT ["/app"]
```

もう1つ最初に考えておくこととしてCPU allocationをどうするか？があります。
Cloud Runはdefaultでは、HTTP Requestを処理している時のみCPU割当を行います。
CPUが割り当てられている時間のみ料金を払えば良いので、Requestが少ないシステムでは非常に安い料金で動かせます。
自分だけが使うちょっとしたシステムでは非常に嬉しい料金設定です。
ただ、うまく動かすには色々と気を付けることがあります。

HTTP Requestに対して、単純にHTMLやJSONを返すだけなら、問題は少ないのですが、DBへのアクセスがあったり、分散traceやmetricsを送っているとCPU割当がなくなる時間があることを気にする必要が出てきます。
DBとはコネクションを張りっぱなしにしてKeep Aliveを送り続けたりしますがCPU割当がないとこれはできません。
HTTP Requestがたまにしか来ない場合、DBからはコネクションが切断されている可能性があるので、接続し直す必要があります。
少しLatencyは上がってしまいますが、自分しか使わないから、まぁ、良いかと割り切っています。

分散traceやmetricsは定期的に裏で送信することが多いので、これもHTTP Requestがたまにしか来ないと、送信する機会がありません。
HTTP Request処理する度に送るようにしてしまうか、まぁ、出てたらラッキーぐらいで、割り切ってしまっても良いかなと思っています。

これらの問題を解決する簡単な方法としてCPUを常時割当にすることです。
常時割当にするとInstanceが起動している間はCPUが常時割り当てられます。
HTTP Requestが来ない状態がしばらく続くとInstanceはshutdownされるため、24h365d料金がかかるようになるわけではありません。
常時割当にすると単位時間辺りの料金が安くなります。
そのため、高頻度でHTTP Requestが来る場合、常時割当の方が安くなります。
個人利用でRequestがたまにしか来ない場合、どちらでも無料枠に収まることが多いので、CPU常時割当の方が考えることが減って楽ではあるのですが、筆者は趣味で常時割当にはしていません。

|  | CPU | Memory |
| ---- | ---- | ---- |
| 常時割当 | $0.00001800 / vCPU 秒 毎月 240,000 vCPU 秒無料 | $0.00000200 / GiB 秒 毎月 450,000 GiB 秒まで無料 |
| Request処理時のみ割当 | $0.00002400 / vCPU 秒 毎月 180,000 vCPU 秒まで無料 | $0.00000250 / GiB 秒 毎月 360,000 GiB 秒まで無料 |

# Cloud Firestore



# BigQuery