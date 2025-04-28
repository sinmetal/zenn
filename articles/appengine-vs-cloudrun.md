---
title: "App Engine VS Cloud Run"
emoji: "🦁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["GoogleAppEngine","CloudRun","gcp"]
published: true
---

ちょいちょい、これから Web Application を作るなら、[App Engine](https://cloud.google.com/appengine/) と [Cloud Run](https://cloud.google.com/run) どちらを使うべきか？と聞かれるので、思いの丈を綴っておこうと思う。

# 結論

僕はどちらにも好きなところと嫌いなところがあって、使い分けているが、だいたい Cloud Runを使っている。
App Engineを使うのは、Landing Pageのようなあまり複雑なことをしないケース。

この先は2つを比べて、僕がどちらを使うのかを判断する時の材料を書いていく。
App Engine には Standard と Flex があるが、この記事では Standard を主に扱っている。

# App Engine と Cloud Run を比べてみる

### 課金体系

App Engine は Instance 課金、Cloud Run は 使用したリソースでの課金になる。
App Engine(automatic scaling, basic scaling) は Instance が起動してから、最後のリクエストの15分後に終了するまでを単位にしている。
Cloud Run は 100ms 単位で切り上げで計算される。
そのため、1min毎に5sec処理するみたいなことをした時に、App Engine は Instance が終了しないので、ずっと課金対象だが、Cloud Run は都度 5000ms 課金されるだけで済む。
cron で定期的に起動するような時やリクエスト頻度が少なくぽつぽつ来るケースだと Cloud Run が有利で、心が Cloud Run に傾く。

### マシンスペック

App Engine は規定されたいくつかの種類から選択するが、Cloud Run は CPU コア数と Memory を選択できるので、Memory だけ増やすことができて便利。
最大スペックも Cloud Run の方が大きいので、心が Cloud Run に傾く。

#### App Engine Instance Class

| Instance Class | Memory Limit | CPU Limit |
| ---- | ---- | ---- |
| B1 | 128 MiB | 600 Mhz |
| B2 | 256 MiB | 1.2 Ghz |
| B4 | 512 MiB | 2.4 Ghz |
| B4_1G | 1024 MiB | 2.4 Ghz |
| B8 | 1024 MiB | 4.8 Ghz |
| F1 | 128 MiB | 600 Mhz |
| F2 | 256 MiB | 1.2 Ghz |
| F4 | 512 MiB | 2.4 Ghz |
| F4_1G | 1024 MiB | 2.4 Ghz |

#### Cloud Run

* CPU 0.08 ~ 8 Core (2nd gen は最小 0.5~)
* Memory 128 MiB ~ 32 GiB (2nd gen は最小 512MiB~)

### Deploy

App Engine は Deploy ([gcloud app deploy](https://cloud.google.com/sdk/gcloud/reference/app/deploy)) を実行すると Cloud Build が暗黙的に動いて Deploy が行われるが、これがなかなか時間がかかる。
開発環境だと CI でとりあえず main branch に merge されたら、Deploy したりするけど、Deploy を Skip してもよいような時でも CI 回してると Deploy を待つことになって、ちょっとめんどうに感じる。
更にこの仕組みは成果物は Deploy しないと生まれないので、CI と CDを分離しづらい。

Cloud Run は [Artifact Registry](https://cloud.google.com/artifact-registry) の Container Image を Deploy できるので、App Engine より短い時間で CI を完了できる。
Container Image を作ってさえおけば、Deploy は簡単にできるので、CI と CD を分離しやすい。

### スピンアップタイム

App Engine for Go はスピンアップタイムが爆速なので、ここは App Engine for Go が圧倒的。
ただ、App Engine for Java 使ってた時は 3sec ぐらいかかっていたので、現状の Cloud Run にそんなに不満はない。
[min-instances](https://cloud.google.com/run/docs/configuring/min-instances) を指定すれば、スピンアップに当たる数は少なくできるし、要件がよほどシビアでなければ、問題ないだろう。

### Runtime

App Engine は最新の Version から 1つか２つぐらい遅れるが、幸い Go は後方互換を大事にする文化なので、むちゃくちゃ困ってはいない。
Cloud Run だと コマンドラインツール で提供されているものも動かせることの方が嬉しいかもしれない。

### Static Contents

App Engine には Static Contents Server があるので、html, js などを配信するのはとても簡単だけど、Cloud Run にはそういった機能はないので、何かしら考えてやる必要がある。
[Firebase Hosting](https://firebase.google.com/docs/hosting) 使うか、後述する Serverless NEG を使って App Engine か Cloud Storage から返してやることになるだろうか。

### Deadline

App Engine, Cloud Runでそれなりに差があるが、結構長い。
Serverlessだと、長時間の処理は分割した方が良いので、どちらを使うか？という観点ではあまり気にならないかもしれない。

#### HTTP Request Deadline

シンプルにHTTP Requestを受け取った時の伸ばすことのできる最長のDeadline。
App EngineはScaling Configによって変わる。

* App Engine Automatic Scaling : 10min
* App Engine Basic Scaling and Manual Scaling : 24h
* Cloud Run : 60min

#### Cloud Tasks, Cloud Scheduler

App Engine Target Task だと 送信先がBasic Scaling or Manual Scaling なら timeoutは 24h
Cloud Run 自体の Deadline は 60min だが、Cloud Run に Request を送るために使う HTTP Target Task が 30min までなので、こっちに引っ張られてしまう。

* App Engine HTTP Task to Basic Scaling and Manual Scaling : 24h
* [HTTP Target Task](https://cloud.google.com/tasks/docs/creating-http-target-tasks?hl=en#handler) : 30min

#### [HTTP Target Task](https://cloud.google.com/tasks/docs/creating-http-target-tasks?hl=en)

`Timeouts: for all HTTP Target task handlers the default timeout is 10 minutes, with a maximum of 30 minutes.`

#### [HTTP Target Job attempt_deadline](https://cloud.google.com/scheduler/docs/reference/rpc/google.cloud.scheduler.v1#google.cloud.scheduler.v1.Job)

`For HTTP targets, the default is 3 minutes. The deadline must be in the interval [15 seconds, 30 minutes].`

### Observability

[Cloud Profiler](https://cloud.google.com/profiler) が [Always CPU](https://cloud.google.com/run/docs/configuring/cpu-allocation?hl=en) をONにしていない場合は、Cloud Run ではうまく動かないのは少し不便なところではある。
まぁ、CPU割当がちょくちょく停止するので、仕方ない気もする。

# App Engine と Cloud Run を Mix するために

App Engine と Cloud Run をやりたいことに合わせてMixして使うのも結構強力だ。
それができる機能として [Serverless NEG](https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts) がある。
Serverless NEG はざっくり言うと [External Application Load Balancing](https://cloud.google.com/load-balancing/docs/https?hl=en) の後ろに App Engine, Cloud Run, Cloud Functions を持ってこれるサービス。
Google Cloud Customer Engineer の Seiji Ariga さんが [噛み砕いた記事](https://medium.com/google-cloud-jp/serverless-neg-%E3%81%A7%E3%82%B7%E3%82%B9%E3%83%86%E3%83%A0%E9%96%8B%E7%99%BA%E3%82%92%E3%82%88%E3%82%8A%E6%9F%94%E8%BB%9F%E3%81%AB-4f9cebd2780f) を書いてくれている。
Path ごとに向き先を設定できるので、 `/api/*` は App Engine `/image/upload` はマシンスペックを大きくした Cloud Run に送ることができる。

更に External Application Load Balancing が前にいれば、 [Cloud Armor](https://cloud.google.com/armor) が使えたり、Tokyo Region の [App Engine, Cloud Run に Custom Domain を割り当てた時に遅くなる問題](https://cloud.google.com/appengine/docs/standard/go/mapping-custom-domains?hl=en) が解決されるなど良いことが多い。

Severless NEGを使う場合、App EngineやCloud Runをそのまま使うのに比べて [制限事項](https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts?hl=en#limitations) があるので、一通り確認しておいた方がよい。
1 Projectでのシンプルな構成であれば問題なるものは少ないと思うが、複雑なことをやろうとしている場合、制限に引っかかるものがあるかもしれない。

Cloud Tasks, Cloud Pub/SubなどからのRequestをどこに送るのか？というのも少し気にする必要がある。
自分はLB経由ではなく直接App EngineやCloud Runに送ることが多い。
LBを経由する必要性をあまり感じないからだ。

# 余談

Cloud Run を見ていると、App Engine が一度目指した世界を今の技術でもう一度！という感じがします。
[Managed VMs](https://qiita.com/sinmetal/items/68f0e21e1f33e3a553a1) が生まれて5年ほどが経ち、現在の App Engine Flex になったわけですが、微妙にこれじゃない感がありました。
App Engine 自体が Google Cloud Platform より昔から存在していたこともあり、GCPに馴染んでいない点もちょいちょいあるわけですが、Cloud Run は今の GCP でもう一度 Serverless を作るなら、こうするぞ！という王道を爆走してる感じがあります。
課金体系も App Engine がまだベータだった時のものに近い リソース利用時間での課金となり、あの日の夢をもう一度見させてくれそうです。

Cloud Runに実装された双方向ストリーミングや WebSocketは、App Engineに要望はあったけど、実現されなかったものです。
App Engine Image Service など Web Application を作る上で便利で安価なサービスが詰まっていた Platform としての App Engine は失われていくけど、時代に合わせて進化していくGCPが来年も楽しみです。
