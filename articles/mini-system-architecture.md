---
title: "小さなWebアプリケーションをGoogle Cloudで作る場合の構成例"
emoji: "🐁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: true
---

[Google Cloud Champion Innovators Advent Calendar 2023](https://adventar.org/calendars/9217) の12日目の記事です。

筆者が小さなWebアプリケーションをGoogle Cloudで構築する場合の構成をいくつか紹介します。
今やGoogle Cloudには多くのプロダクトがあり、同じ要件を満たすにも様々な構成があります。
筆者の場合は少人数で開発運用することが多く、予算も少な目なことが多いので、フルマネージドサービスやサーバーレスと呼ばれるものを使い、基本運用はプラットフォーム任せで何もしてないみたいな感じのことが多いです。

## [Firebase Hosting](https://firebase.google.com/docs/hosting) with [Cloud Run](https://cloud.google.com/run/docs/overview/what-is-cloud-run)

Firebase Hostingは静的コンテンツをDeployして配信するのを簡単に行えるプロダクトです。
[VersioningやPreviewの機能](https://firebase.google.com/docs/hosting/test-preview-deploy) もあり、 [カスタムドメインの設定](https://firebase.google.com/docs/hosting/custom-domain) もあるので、便利です。
自身でドメインを持っていない場合でも PROJECT_ID.web.app or PROJECT_ID.firebaseapp.com のドメインが付与されているので、それをそのまま使うこともできます。
動的コンテンツを配信したい場合は [指定したPathをCloud Runに送ることができます。](https://firebase.google.com/docs/hosting/cloud-run?hl=ja#direct_requests_to_container) 

Firebase HostingのRequestのTimeoutは60secなので、それ以上かかるような処理は何か考える必要があります。

## App Engine Standard Environment

App EngineはWebアプリケーションのためのPaaSなので、なんだかんだ便利です。
[Static Contents Server](https://cloud.google.com/appengine/docs/standard/serving-static-files?hl=en&tab=go#configuring_your_static_file_handlers) があるため、htmlやcssなどの配信もお任せです。
[動的に処理したResponseも手軽にキャッシュすることができるため](https://cloud.google.com/appengine/docs/standard/how-requests-are-handled?hl=en&tab=go#response_caching) OGPなどほとんど静的だけど、一部動的に差し込むような場合、作り終えたResponseは全部キャッシュに乗せてしまえば良いので便利です。
ただ、明示的にキャッシュを消すことはできないので、URLの運用には注意が必要です。
エッジキャッシュについては [昔少し書いた](https://qiita.com/sinmetal/items/37c105a098174fb6bf77) ので、気になる方は確認してください。

ドメインも PROJECT_ID.REGION_ID.r.appspot.com が付与されているので、自分で用意する必要はありません。
カスタムドメインも設定できるのですが、 [東京リージョン(asia-northeast1)でカスタムドメインを設定すると、むしろus-central1にDeployするより遅くなってしまう](https://cloud.google.com/appengine/docs/standard/mapping-custom-domains?hl=en) ことに注意です。
この挙動はなかなかびっくりするもので、Zennでも [昔ハマった](https://zenn.dev/catnose99/articles/56f523d39cca43) ことがあるようです。

特定のGoogle WorkspaceのDomainや、Google Groupに所属している人だけにWebアプリケーションを見せたい時に [Identity-Aware Proxy](https://cloud.google.com/iap) で簡単に覆えるのも便利です。

App Engineを使う上でのハードルとしては独自要素が多く、App Engine固有の知識が必要になります。
知識を持っている人間も徐々に減っており、App Engineの状況を完全に把握するには歴史を紐解く必要があります。

Scaling Configも独自仕様なので、ノリを理解するのが大変かもしれません。
どんな設定があるか [大昔に書いた](https://qiita.com/sinmetal/items/017e7aa395ff459fca7c) ので、もしScaling Configをチューニングする必要が出てきたら、多少参考になるかもしれません。
筆者は思うようにInstanceが増えたり減ったりしないから、一生懸命この設定をいじったりいじらなかったりする人たちを見てきました。
結構コスト最適化するのは大変です。

## Application Load Balancer with みんな

上の2つと比べると完全無料で運用はできず、自分一人で使うアプリケーションを作る時というより、公開してみんなに使ってもらうサービスを本気で作る時とか、企業で小さなアプリケーションを作る時に使う構成です。
Application Load Balancerを一番前に置いて、後ろに各種プロダクトを必要に応じて配置します。
LBは構築するコンポーネントが多いので、慣れるまでは理解するのが大変かもしれませんが、慣れてしまえば、順番に並べていくだけです。
この構成は柔軟性が高く、ユースケースに合わせて強力なGoogle Cloudの機能をたくさん利用することができます。
ちょうど今あなたがこの記事を読んでいるZennもこの構成で作られているようです。 ([Zennのバックエンドを Google App Engine から Cloud Run へ移行しました（無停止！YES！）](https://zenn.dev/team_zenn/articles/migrate-appengine-to-cloudrun)

LBを前に置けば [AppEngineにCustom Domain設定時にLatencyが増加する問題](https://cloud.google.com/appengine/docs/standard/mapping-custom-domains?hl=en) もありませんし、 [Cloud CDN](https://cloud.google.com/cdn/docs/overview) や[Cloud Armor](https://cloud.google.com/armor/docs/cloud-armor-overview) , [Identity-Aware Proxy](https://cloud.google.com/iap) も使えます。

![](/images/mini-system-architecture/global-external-application-lb.png)

## 長時間かかる処理を行うパターン

いずれの構成を使ったとしても長時間かかる処理はアーキテクチャを考える必要があります。
サーバーレスプロダクトはタイムアウトの時間がそんなに長くないものが多いので、
長時間かかる処理の中でよくある2つのパターンについて考えてみます。

### サーバ側の処理に時間がかかるパターン

リクエストされてから、サーバ側で処理が始まり、時間がかかるパターンです。
この場合、処理を開始するリクエストとレスポンスを貰うリクエストを分けます。
処理を開始するリクエストではJobIDを受け取り、Jobの完了までポーリングして待ちます。
Google CloudのAPIでもこの形式はよく見ます。
例えばCompute Engineはリソースの操作に時間がかかるので、レスポンスとしてOperationというものが返ってきて、Operationの状態を取得することで、結果が分かります。

* https://cloud.google.com/compute/docs/reference/rest/v1/instances/start
* https://cloud.google.com/compute/docs/reference/rest/v1/zoneOperations
* https://cloud.google.com/compute/docs/reference/rest/v1/zoneOperations/get

BigQueryも同じような感じですね。
Queryを実行するとJobが返ってきて、Jobを取得することで、Queryの結果を後で知ります。

* https://cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query
* https://cloud.google.com/bigquery/docs/reference/rest/v2/jobs/get
* https://cloud.google.com/bigquery/docs/reference/rest/v2/jobs/getQueryResults

このように処理を開始するリクエストと、結果を受け取るリクエストを別にすることで効率良くマシンリソースを扱えます。

![](/images/mini-system-architecture/async-worker.png)

#### 処理を分割する

処理を開始するリクエストと結果を受け取るリクエストを分けたことで、処理を実行するWorkerを分離することができました。
それにより、選択肢が増えています。
Cloud RunやApp Engineで同じように実行するもよし、Compute EngineやCloud Build, Dataflowを使うもよし、色んな選択肢があります。
処理の内容で最適なものが変わるので、好きなものを使いましょう。
Cloud RunやApp Engineを使う場合はServiceを分けることも視野に入れると良いです。
Concurrentlyやマシンスペックなどを調整することができます。
例えばAPI用のServiceはConcurrentry=80, 1 CPU, Memory 512MiBで動かしているが、重たい処理が同時リクエストの中に混ざるとメモリが足らなくなるので、Worker用のServieとしてConcurrentry=1, 1 CPU, Memory 1GiBを用意します。

この時、分割できる処理なのであれば、分割することで、処理が終わる時間を短くしたり、リトライ範囲を細かくすることができます。
特にサーバーレスプロダクトは分散するのは得意だけど、長時間処理は苦手だったりするので、分割実行とは相性が良いです。
分割する方法も色々ありますが、Cloud TasksやCloud Pub/Subにタスクを分割して入れて、発火するのが楽です。
例えば1年分の売上データのCSVを作りたい時にCloud Tasksに1月担当のタスク、2月担当のタスク・・・という感じで入れていきます。
そうすれば、12分割されて実行できます。
できあがった12個のCSVを [Composite objects](https://cloud.google.com/storage/docs/composite-objects) を使い、合体させることで完成させます。

![](/images/mini-system-architecture/distributed-cloud-tasks.png)

### レスポンスのダウンロード自体に時間がかかる

CSVやPDFなどレスポンス自体のサイズが大きい場合は、Cloud Storageの [SignedURL](https://cloud.google.com/storage/docs/access-control/signed-urls) を使ってCloud Storageから直接ダウンロードしてもらうのが良いです。

## おまけ

自分の周りで動いてるシステムたちの構成

### [GCPUG](https://gcpug.jp)

App Engine Standard Environmentで動いてる1枚だけのWebページ。
Firebase Hostingで良いのだけど、昔からの名残。

### [技術書典](https://techbookfest.org/)

Fastlyが前にいて、後ろにCloud Runがいる構成。
Cloud RunはGraphQL用、Web Front用などいくつかある。

### 社内限定Q&Aアプリケーション

メルカリ社内で使っているQ&Aアプリケーション。
Firebase HostingとCloud Firestoreで動いている。
Cloud Firestore Security Rulesによって、社員かどうかを判別している。

### 社内限定Documentアプリケーション

メルカリ社内で使っているDocument共有アプリケーション。
[MKDocs](https://www.mkdocs.org/) で生成したHTMLをCloud Runから配信している。
Application Load Balancerが前にいてIdentity-Aware Proxyによって、社員かどうかを判別している。
細かい構成は [Cloud Run with IAP / 任意の環境のURLを作る](https://zenn.dev/sinmetal/articles/cloudrun-pr-deploy) に書いた通り。
