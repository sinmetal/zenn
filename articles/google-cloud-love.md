---
title: "sinmetalはなぜGoogle Cloudが好きなのか？"
emoji: "♥"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: true
---

[Google Cloud Champion Innovators Advent Calendar 2023](https://adventar.org/calendars/9217) の1日目の記事です。

Advent Calendarの初日ということもあり、筆者がなぜGoogle Cloudが好きなのかについて。

筆者が初めてGoogle Cloudに出会ったのは2011年で、 [Google App Engine](https://cloud.google.com/appengine) に恋い焦がれてから、ずっとGoogle Cloudを使い続けています。
現在、仕事ではかなり大きなシステムをGoogle Cloudで扱っていますが、個人で小さなシステムを作るのも好きです。
そんな小さなシステムから大きなシステムまで作れるところも魅力に感じています。
この記事では個人でよく作っている小さなシステムに注力しています。

筆者が魅力に感じているGoogle Cloudの思想としてDatacenter as a Computerがあります。
日本語だとGoogle Developer AdvocateのKazunoriさんが [Google Cloud Platformの謎テクノロジーを掘り下げる](https://qiita.com/kazunori279/items/3ce0ba40e83c8cc6e580#datacenter-as-a-computer) で概要を書いてくれています。
ものすごく強力な1台のマシンを用意するのではなく、普通のマシンをたくさん横に並べて必要な時にすぐに使えるようにすることで、Google規模のサービスが効率よく動いています。
小さなシステムはこの仕組みに乗っかって、巨大なデータセンターの端っこを少し使わせてもらうことで、のんびり暮らすことができます。

Datacenter as a Computerを体現していて、好きなサービスがCloud RunとBigQueryです。
この2つはまさに使う時だけ瞬間的にリソースを使えるサービスです。
個人で小さなシステムを作る時もこの2つはよく使います。
この2つに加えて、データベースとしてCloud Firestoreを加えた3つを個人開発ではよく使っています。

## [Cloud Run](https://cloud.google.com/run)

Cloud RunはHTTP Requestを受け取る任意のContainer ImageをDeployして動かせるプロダクトです。
`https://{ランダム文字列}.a.run.app` のURLが付与され、ロードバランサや証明書の管理などもすべてやってくれるので、個人でちょっとしたシステムを作るのにとても便利です。
無料枠が存在するので、自分だけしかアクセスしないものなら、無料枠の中で生きていけます。
まさにGoogleのデータセンターの端っこで生きている感じです。

Cloud Runでシステムを構築する場合、Containerを起動してからHTTP Requestを受け取れる状態になるまでの時間を短くすることを考える必要があります。
これはCloud RunがHTTP Requestが来てから、Containerを起動するため、Requestを送った人はその間待つことになるからです。
最小Instance台数を指定して常時1台Instanceを起動しておくこともできますが、アクセスが無い時も常時起動することになるので、お金がかかるし、スケールアウトして2台目のInstanceが起動する時に同じ問題に当たるため、軽減することしかできません。
筆者はGoogle App Engineを使っている頃から長い間、起動時間を短くすることを考えて生きています。
現在はGo言語を使ってアプリケーションを作成して、小さなContainer Imageを作ることで、なるべく早く起動するようにしています。
Webフレームワークを使う場合も軽量で起動が早いかどうかを気にしています。
Dockerfileも3行しか無い短いものです。

``` Dockerfile
FROM gcr.io/distroless/static-debian11
COPY ./app /app
ENTRYPOINT ["/app"]
```

もう1つ最初に考えておくこととして [CPU allocation](https://cloud.google.com/run/docs/configuring/cpu-allocation) をどうするか？があります。
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

## [Cloud Firestore](https://cloud.google.com/firestore)

Cloud FirestoreはKeyValueStore型のDBです。
Instanceという概念がなく、Read Write1回辺りいくらという料金体系です。
大規模システムで凄まじい数のRWを行うと料金も大規模になりますが、個人で使う分には無料枠内で生きていけます。

Cloud FirestoreにはNative ModeとDatastore Modeの2つがあります。
Native Modeは元々Mobile Backend as a ServiceとしてのFirebaseに備わっていたFirebase Realtime DBの流れを汲みGoogle Cloudで作られたプロダクトです。
ブラウザやAndroid, iOSなどのクライアントアプリと直接やり取りする機能があったり、リアルタイムに更新されたデータを取得する機能があります。

Datastore Modeは元々存在していたCloud Datastoreの後継になります。
元々のDatastoreはBigtableの上に乗っかっていましたが、Firestore Datastore ModeはSpanner的なものの上に乗っかっています。
機能としてはKeyによるRead WriteとシンプルなQueryが使えます。

個人でちょっとしたものを作るなら、どちらを使っても良いのですが、筆者はNative Modeを使うことが多いです。
ブラウザから直接Read Writeできるのも便利だし、リアルタイムの更新取得やオフライン機能があるのも良いです。
サーバサイドで使う場合もリアルタイムの更新取得が結構便利でポーリングする必要がなくなります。

## [BigQuery](https://cloud.google.com/bigquery/)

BigQueryはデータウェアハウスのサービスです。
TB単位のデータでも数秒でフルスキャンすることができる性能が売りですが、KB単位のデータでも数秒でフルスキャンできます。
BigQueryもInstanceという概念がなく、ストレージの料金とQuery実行時のオンデマンド料金です。
無料枠があるのでやっぱり個人で使う分には無料枠の中で生きていけます。

BigQueryにはログなど分析したいデータはなんでも入れておくことができて便利です。
Google CloudのAudit Log、Cloud RunのリクエストログやアプリケーションログはCloud LoggingのSink機能を使えば簡単にBigQueryに入れることができます。
入れたデータをSQLで検索、集計できるのも便利だし、Looker Studioでグラフにして見ても便利です。
CloudのBilling Dataやゲームのキャラクター情報など、何でも入れておけば、好きに見ることができます。

### Dremel

BigQueryの元になっているGoogleのシステムがDremelです。
DremelはData Center as a Computerの思想を体現していて、とてもGoogleらしいシステムだと思います。

Dremelはインタラクティブなクエリを実行するために生まれたシステムです。
インタラクティブなクエリの難しいところは、どのようなクエリが実行されるかは分からないため、事前にインデックスを用意するのが難しいことです。
解決策として、膨大なマシンリソースで超高速にフルスキャンするというパワープレイを行っているのがDremelです。
巨大なデータをフルスキャンする時、最初にボトルネックになるのはDiskから読み出す処理です。
HDDだと200MB/s程度読み込めますが、TBやPB読み込もうとすると長い時間がかかってしまいます。
そこでデータを分割してたくさんのHDDに保存して並列に読むことで、TB単位のデータを数秒で処理できるようにしています。

![](/images/google-cloud-love/dremel1.png)

HDDから読みだした後に処理するのにもマシンパワーが必要なので、たくさんのContainerを起動して処理しています。
この圧倒的パワーにより、非常に大量のデータに対してLIKE句や正規表現を実行しても現実的な時間で結果を取得できます。

![](/images/google-cloud-love/dremel2.png)

これをデータセンターの中でクエリ実行時に行っているのが、とっても面白いですね。

[DremelについてはCloud Solutions Architectの中井悦司さんの記事](https://www.school.ctc-g.co.jp/columns/nakai2/nakai294.html) があるので、これを読むと周辺技術も含めてもっと知ることができます。

## まとめとおまけ

無料枠の話ばかりしたので、筆者が金の亡者っぽい感じがしますが、まぁ、割と金の亡者で、コスト最適化は大好きです。
なんなら、仕様をインフラに合わせて考えます。

筆者はDatacenter as a Computerが好きなので、Google Cloudが好きなのですが、プロダクトの中には色々あります。
BigQueryのように、まさしくDatacenter as a Computerというものもあれば、別段そうでもないものもあります。
全プロダクト触ってるわけではないですが、好んで使うプロダクトは以下です。

### 好きなプロダクト

* Cloud Run
* Cloud Firestore
* Cloud Spanner
* BigQuery

### そうでもないプロダクト

* Cloud SQL
* Cloud Composer

[Alloy DB](https://cloud.google.com/alloydb) のように最近出てきて様子を伺っているものもありますし、Cloud StorageやCloud Monitoringのように空気のように使うプロダクトもあります。

既存のプロダクトも機能がどんどん増えています。
様々な人が色んなユースケースで使うようになっているので、それに対応するように機能がリリースされています。
例えば、 [BigQueryに文字列やJSONを検索するためののINDEX](https://cloud.google.com/bigquery/docs/search-intro) を作れるようになったのは面白いですね。
全力マシンパワーでフルスキャンするのがBigQueryですが、OLAP以外にも日々のバッチジョブなどでも使われるようになり、事前に決まっているクエリを実行することも多くなりました。
[月額定額料金のプラン](https://cloud.google.com/bigquery/pricing?hl=en#capacity_compute_analysis_pricing) を使っている人も増えたので、効率よく少ない [スロット](https://cloud.google.com/bigquery/docs/slots) でクエリを処理できるようになっていってます。

今後もたくさんのアップデートがあり、様々な機能がリリースされ、使うプロダクトも変わっていくと思いますが、Datacenter as a Computerの思想がある限り、なんだかんだGoogle Cloudが好きで、使い続けているのではないかと思います。

Google Cloudのプロダクトが増えるに連れ、利用者も様々な人が増えました。
筆者が普段使わないプロダクトを使う人たちもたくさんいます。
[Google Compute Engine](https://cloud.google.com/compute) でVMをごりごり動かしている人、 [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine) でContainerを動かしている人、 [Dataflow](https://cloud.google.com/dataflow) でビッグデータを処理している人、 [Vertex AI](https://cloud.google.com/vertex-ai) で機械学習をしている人・・・。
昔々、Google App Engineしか無かった頃と比べて、本当に色んな人たちがいます。
そんな個性豊かなGoogle Cloud Champion Innovatorsが送るAdvent Calendarをお楽しみください。 