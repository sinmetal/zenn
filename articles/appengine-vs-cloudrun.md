---
title: "Google App Engine VS Cloud Run"
emoji: "🦁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["GoogleAppEngine","CloudRun","GoogleCloudPlatform"]
published: true
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
cron で定期的に起動するような時やリクエスト頻度が少なくぽつぽつ来るケースだと Cloud Run が有利で、心が Cloud Run に傾く。

### マシンスペック

App Engine は規定されたいくつかの種類から選択するが、Cloud Run は CPU コア数と Memory を選択できるので、Memory だけ増やすことができて便利。
最大スペックも Cloud Run の方が大きいので、心が Cloud Run に傾く。

#### App Engine Instance Class

|Instance Class|Memory Limit|CPU Limit|
|---|---|---|---|
|B1|128 MiB|600 Mhz|
|B2|256 MiB|1.2 Ghz|
|B4|512 MiB|2.4 Ghz|
|B4_1G|1024 MiB|2.4 Ghz|
|B8|1024 MiB|4.8 Ghz|
|F1|128 MiB|600 Mhz|
|F2|256 MiB|1.2 Ghz|
|F4|512 MiB|2.4 Ghz|
|F4_1G|1024 MiB|2.4 Ghz|

#### Cloud Run

* CPU 1 ~ 4 Core
* Memory 128 MiB ~ 8 GiB

### Deploy

App Engine は Deploy ([gcloud app deploy](https://cloud.google.com/sdk/gcloud/reference/app/deploy)) を実行すると Cloud Build が暗黙的に動いて Deploy が行われるが、これがなかなか時間がかかる。
開発環境だと CI でとりあえず main branch に merge されたら、Deploy したりするけど、Deploy を Skip してもよいような時でも CI 回してると Deploy を待つことになって、ちょっとめんどうに感じる。
更にこの仕組みは成果物は Deploy しないと生まれないので、CI と CDを分離しづらい。

Cloud Run は [Container Registry](https://cloud.google.com/container-registry) and [Artifact Registry](https://cloud.google.com/artifact-registry) の Container Image を Deploy できるので、App Engine より短い時間で CI を完了できる。
Container Image を作ってさえおけば、Deploy は簡単にできるので、CI と CD を分離しやすい。

### スピンアップタイム

App Engine for Go はスピンアップタイムが爆速なので、ここは App Engine for Go が圧倒的。
ただ、App Engine for Java 使ってた時は 3sec ぐらいかかっていたので、現状の Cloud Run にそんなに不満はない。
[min-instances](https://cloud.google.com/run/docs/configuring/min-instances) を指定すれば、スピンアップに当たる数は少なくできるし、要件がよほどシビアでなければ、問題ないだろう。

### Runtime

App Engine は最新の Version から 1つか２つぐらい遅れるが、幸い Go は後方互換を大事にする文化なので、むちゃくちゃ困ってはいない。
Cloud Run だと コマンドラインツール で提供されているものも動かせることの方が嬉しいかもしれない。

### 認証

[Identity Aware Proxy](https://cloud.google.com/iap) を使う場合、Cloud Runは [Serverless NEG](https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts?hl=en) が必要となるため、完全無料ではできない。
完全無料を目指していない場合は、App EngineとCloud Runでどちらを選択するに影響するような差はない。

### Static Contents

App Engine には Static Contents Server があるので、html, js などを配信するのはとても簡単だけど、Cloud Run にはそういった機能はないので、何かしら考えてやる必要がある。
[Firebase Hosting](https://firebase.google.com/docs/hosting) 使うか、後述する Serverless NEG を使って App Engine か Cloud Storage から返してやることになるだろうか。

### Deadline

1 Request を処理する Deadline が [App Engine](https://cloud.google.com/appengine/docs/standard/go/how-instances-are-managed?hl=en#scaling_types) と [Cloud Run](https://cloud.google.com/run/docs/configuring/request-timeout?hl=en) で違う点がある。
気になるのは Cloud Tasks, Cloud Scheduler から Cloud Run を起動した時の Deadline が 30min になること。
現実的には 1 task に 30min かけることは少ないので、そんなに気にならないかもしれないが、Cloud Run 自体の Deadline が 60min なので、合わせて欲しい気持ちになる。

#### HTTP Request Deadline

* App Engine Automatic Scaling : 10min
* App Engine Basic Scaling and Manual Scaling : 24h
* Cloud Run : 60min

#### Cloud Tasks, Cloud Scheduler

Cloud Run 自体の Deadline は 60min だが、Cloud Run に Request を送るために使う HTTP Target Task が 30min までなので、こっちに引っ張られてしまう。

* App Engine HTTP Task to Basic Scaling and Manual Scaling : 24h
* [HTTP Target Task](https://cloud.google.com/tasks/docs/creating-http-target-tasks?hl=en#handler) : 30min

### Observability

[Cloud Profiler](https://cloud.google.com/profiler) が Cloud Run では動かないので、少々残念。

# Cloud Run で悩ましいところ

~~全体を見ると、Cloud Run がとても魅力的ではあるが、Cloud Run は Request を処理していない間、CPU割当がなくなり、しばらくした後、その Instance を使い回すという点が、少し引っかかっている。
この挙動は Cloud Run 特有で、Local や Unit Test でチェックするのが難しいので、問題を発見するのが難しそうだと感じる。
gRPC のコネクションの管理や使っている Library が裏で何かしていないかを気にしておかないと、思いも寄らないタイミングで膝に矢を受けてしまいそうだ。~~

[Always CPU](https://cloud.google.com/run/docs/configuring/cpu-allocation?hl=en) の機能が増えたので、この部分がつらいなら、Always CPUにすれば解決するようになった。

# App Engine と Cloud Run を Mix するために

現状だと、App Engine と Cloud Run をやりたいことに合わせて使い分けたい。
それができる機能として [Serverless NEG](https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts) がある。
Serverless NEG はざっくり言うと [External HTTP(S) Load Balancing](https://cloud.google.com/load-balancing/docs/https?hl=en) の後ろに App Engine, Cloud Run, Cloud Functions を持ってこれるサービス。
Google Cloud Customer Engineer の Seiji Ariga さんが [噛み砕いた記事](https://medium.com/google-cloud-jp/serverless-neg-%E3%81%A7%E3%82%B7%E3%82%B9%E3%83%86%E3%83%A0%E9%96%8B%E7%99%BA%E3%82%92%E3%82%88%E3%82%8A%E6%9F%94%E8%BB%9F%E3%81%AB-4f9cebd2780f) を書いてくれている。
Path ごとに向き先を設定できるので、 `/api/*` は App Engine `/image/upload` はマシンスペックを大きくした Cloud Run に送ることができる。

更に External HTTP(S) Load Balancing が前にいれば、 [Cloud Armor](https://cloud.google.com/armor) が使えたり、Tokyo Region の [App Engine, Cloud Run に Custom Domain を割り当てた時に遅くなる問題](https://cloud.google.com/appengine/docs/standard/go/mapping-custom-domains?hl=en) が解決されるなど良いことが多い。

ただ、Severless NEG はApp EngineやCloud Runをそのまま使うのに比べて [制限事項](https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts?hl=en#limitations) がそれなりにある。
Deadline が 30sec 固定は地味に気になるが、User からの Request で、30sec 以上かけることはあんまりないから、なんとかなるだろう。
この制限があるので、Cloud Tasks, Cloud Scheduler からの Request は Serverless NEG 経由ではなく、直接送った方がいいかもしれない。
Cloud Armor を ON にしている時に Cloud Tasks, Cloud Scheduler の Request をかける必要はないし、External HTTP(S) Load Balancing の料金の節約にもなる。

# 余談

Cloud Run を見ていると、App Engine が一度目指した世界を今の技術でもう一度！という感じがします。
[Managed VMs](https://qiita.com/sinmetal/items/68f0e21e1f33e3a553a1) が生まれて5年ほどが経ち、現在の App Engine Flex になったわけですが、微妙にこれじゃない感がありました。
App Engine 自体が Google Cloud Platform より昔から存在していたこともあり、GCPに馴染んでいない点もちょいちょいあるわけですが、Cloud Run は今の GCP でもう一度 Serverless を作るなら、こうするぞ！という王道を爆走してる感じがあります。
課金体系も App Engine がまだベータだった時のものに近い リソース利用時間での課金となり、あの日の夢をもう一度見させてくれそうです。

Cloud Runに実装された双方向ストリーミングや WebSocketは、App Engineに要望はあったけど、実現されなかったものです。
App Engine Image Service など Web Application を作る上で便利で安価なサービスが詰まっていた Platform としての App Engine は失われていくけど、時代に合わせて進化していくGCPが来年も楽しみです。

# Cloud Functions は？

ここまで読んだ読者の中には、Serverless には [Cloud Functions](https://cloud.google.com/functions) もあるけど・・・？と思っている方もいるでしょう。
現状、僕はあまりCloud Functionsを使うことがありません。
まず、Cloud Functions は Web Application を作るのには適しません。
1 Instance 1 Function なので 10 API 作ろうと 10 Function Deployすることになり、アクセス権の制御など下回りの共通処理の UPDATE を考えると Deploy 祭りになってしまうのもつらいところです。
1 Instance で同時に処理する Request は 1 なのも大人数が同時に利用し、1画面開くと同じユーザから複数 Request が実行される Web Application 向きではありません。

そのため、Cloud Functions に向いてるのはユーザからの Request より、独立したイベント処理です。
例えば、画像が新しくアップロードされたイベントから、サムネイルを作るとか、cron で 30秒毎にキャッシュを作っておくなどの処理です。
ただ、これらの処理は App Engine や Cloud Run を使ってもできる処理なので、あまり Cloud Functions に分けておこうというモチベーションはありません。

更に僕の場合、Go がメインですが、Go だと Dockerfile 書くのも簡単だし、main 関数で Web Server を立ち上げるのも簡単です。
Cloud Run に簡単に乗せられるので、Cloud Run に寄せておきたい気持ちになります。
そんな感じで、僕の場合は Cloud Functions を使う理由がないので、今のところほとんど使っていません。

## Cloud Functions にしかできないこと

Cloud Functions を選択するケースとして、Cloud Functions にしかない [Event Trigger](https://cloud.google.com/functions/docs/calling) を使うケースがあります。

* Cloud Firestore Trigger
* Google Analytics for Firebase Triggers
* Firebase Realtime Database Triggers
* Firebase Authentication Triggers
* Firebase Remote Config Triggers

これらの Trigger は Cloud Functions にしかないので、選択肢がありません。
ただ、 [Event Trigger も Cloud Run が追いかけてる](https://cloud.google.com/blog/products/serverless/build-event-driven-applications-in-cloud-run) ので、Cloud Run 側の対応が進めば、好きな方を選べるようになりそうです。