---
title: "どこで実行すべきか？Google Cloud Compute Option (アプリケーション編)"
emoji: "🐕‍🦺"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: false
---

昔と比べるとGoogle Cloudは多くのプロダクトがあり、同じことをしようとしても選択肢が多くあります。
昔からずっとやっていって、各プロダクトがリリースされていたのを見ていた人ならともかく、これから始める人はどれから触るか悩むと思います。
公式でもよくこの話やっています。

* 2020年: [Where should I run my stuff? Choosing compute options](https://www.youtube.com/watch?v=q_5AgiI7KFQ)
* 2021年: [どこで実行すべきか。Google Cloud のコンピューティング オプションの選択](https://cloud.google.com/blog/ja/topics/developers-practitioners/where-should-i-run-my-stuff-choosing-google-cloud-compute-option)
* 2022年: [アプリケーションはどこで動かすべきか 2022 春](https://www.youtube.com/watch?v=BxCIi21irMA)
* 2023年: Comming Soon

筆者はやりたいこととスキルセットがクロスすることで最適なものが変わると思っているので、最終的には趣味かなと思っています。
ということで、この記事では筆者が選ぶ時の判断基準について書いていきます。
筆者のスキルセットとしてはインフラ構築とかは得意ではないので、フルマネージドサービスを使うことが多いです。
[sinmetalはなぜGoogle Cloudが好きなのか？](https://zenn.dev/google_cloud_jp/articles/google-cloud-love) を読むと好みが分かります。

## どこで実行すべきか？

HTTPリクエストを処理するアプリケーションを作る時の第一の選択肢は [Cloud Run](https://cloud.google.com/run/docs/overview/what-is-cloud-run) です。
Cloud Runの良いところはContainer Imageを用意して、Deployするだけで、他に考えることが少ないのが楽です。
リクエストの数に応じてオートスケールし、 [リクエストログとアプリケーションログはCloud Loggingに送られ](https://cloud.google.com/run/docs/logging) 、 [MetricsはCloud Monitoringに送られます](https://cloud.google.com/run/docs/monitoring) 。
[認証機能もあるので](https://cloud.google.com/run/docs/authenticating/overview) 必要に応じて、設定できます。
HTTPSでアクセスできるURLも発行してくれるので、ちょっとしたアプリケーションを作るのはとても簡単です。

### Cloud Runに向かない要件

Containerになってれば、とりあえずDeployできるCloud Runですが、向いてないこともあります。
公式ドキュメントにも [アプリケーションが向いてるかどうか](https://cloud.google.com/run/docs/fit-for-run) を考えるページがあります。

#### 任意の数のInstanceを動かしたい

1台だけ動作させたいといったことは向きません。
[Min Instance](https://cloud.google.com/run/docs/configuring/min-instances) , [Max Instance](https://cloud.google.com/run/docs/configuring/max-instances) という設定がありますが、これを両方1にしたからと言って、必ず1台だけ立ち上がっている状態になるわけではありません。
そのため、1つしかアプリケーションは同時に存在しないはずといった前提で書いているアプリケーションを動作させる環境としてはCloud Runは向きません。

#### アプリケーションを動かし続けたい

ChatBotでコネクションを張りっぱなしにしたいなど、アプリケーションを動作させ続けたい場合はCloud Runは向きません。
Min Instanceを指定した場合でも、その数のInstanceが存在するように制御してくれるだけで、同じInstanceが動作し続けるわけではありません。
Instanceは入れ替わることがあります。

#### Containerの起動に時間がかかる

起動に時間がかかるフレームワークを使っているなど、Container起動してから、HTTPリクエストを処理できるようになるまで時間がかかるものは向きません。
処理できるInstanceがいない場合、待つことになるからです。
ただ、Min Instanceを指定することで軽減はできるので、許容範囲内に収まるのであれば、なんとかなります。
[ZennもContainerの起動にそこそこ時間がかかるので、Min Instanceが無い時はCloud Runで動かすのを断念したようですが、Min Instanceを設定することで許容範囲内になった](https://zenn.dev/team_zenn/articles/migrate-appengine-to-cloudrun) ようです。
[Elasticsearchを動かしてる根性入った人](https://zenn.dev/tellernovel_inc/articles/3b38a1a17128c6) もいますし、 [技術書典](https://techbookfest.org/) ではSolrを動かしていて、Containerの起動に1min以上かかっています。
まぁ、遅いだけと言えば、遅いだけなので、どのぐらい許容できるかです。

筆者はContainerの起動速度をとても気にする人間なので、シングルバイナリが作れて小さなContainer Imageを作れる [Go](https://go.dev/) を使っています。

### Cloud Runに向かないやつは何で動かしてる？

#### [GKE Autopilot](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview)

任意の数のInstanceを動かしたい、アプリケーションを動かし続けたい、状態をメモリ内で保持したい場合時は [GKE Autopilot](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview) を使っています。
GKE Autopilotを使えば、Cloud Runと同じようにContainer ImageをDeployするだけで動かせます。
インターネットからリクエストを受け取るとなると少々大変ですが、中から外にリクエストを送る用途であれば、割と楽です。
GEK Autopilotの場合、 [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) が必須なので、最初にこの設定をするのがちょっと手こずるかもしれません。
慣れてしまえば、まぁ、なんとかなります。

GKEは [Clusterごとに管理手数料](https://cloud.google.com/kubernetes-engine/pricing?hl=ja#cluster_management_fee_and_free_tier) がかかります。
Billing Accountに対して1 Clusterは無料なので、Clusterをたくさん作るより1つのClusterにある程度まとめた方が安くなります。
そのため筆者はGEK Cluster用のProjectを作って、そこにClusterはまとめています。
Cloud StorageやFirestoreなど、Cluster以外のリソースは各Projectに置いてます。

#### Compute Engine

かなり大きなマシンスペックが必要なもの、MinecraftやARKのようにインストールしてDiskにセーブデータを持つようなものはCompute Engineを使っています。
筆者がCompute Engineを使う場合、Instanceを起動したままにすることは少なく、Cloud Runから起動停止を行います。

## おわりに

アプリケーションを動かすプロダクト選択の筆者の趣味で話でした。
バッチジョブを動かす場合は更に多くの選択が出てくるので、やる気が出れば、書いてみようと思います。