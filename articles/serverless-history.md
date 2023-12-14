---
title: "Google Cloud Serverless Product History"
emoji: "🐕"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: true
---

[Google Cloud Champion Innovators Advent Calendar 2023](https://adventar.org/calendars/9217) の6日目の記事です。

sinmetalから見たGoogle Cloud Serverless Productたちの歴史と現状を振り返ります。

## リリース順

* App Engine Standard Environment (2008年)
* App Engine Flexible Environment (2016年)
* Cloud Functions (2017年)
* Cloud Run (2018年)

## App Engine Standard Environment

最古のServerless Productで昔はServerlessという言葉は使われておらず、WebアプリケーションのためのPlatform as a Serviceと呼ばれていました。
Google Cloudより昔からあるため、App Engine単体でPlatformになっています。
App EngineはPlatformなので、単純に自分のアプリケーションを動かすだけではなく、Webアプリケーションでよく必要になる要素がセットです。
全文検索のAPIや画像処理用のAPIなど様々なものがありました。
セットで提供されている者たちは独自のAPIだったため、SDKもLocal環境もすべて独自で用意されていました。
ただ、逆に制約も多くありました。
ローカルディスクへの書き込みができなかったり、外と通信するにも専用のAPIを利用する必要がありました。
筆者は当時Javaを使っていましたが、JavaにはThe JRE Class White Listというものがあり、使えるものはここに載っているものだけでした。

![](/images/serverless-history/app-engine-standard-architecture.png)

これはこれでこの世界の中で生きていくには便利だったのですが、時が流れるに連れ、世界は変わっていきます。
Webアプリケーションに求められる機能も増えていき、スマートフォンの登場により、APIサーバの側面も強くなっていきました。

Cloudに求められるものも変わっていきました。
動画処理をしたり、ビッグデータ処理をしたり、現在では機械学習にもよく使われています。

また、Googleのビジネスも変わったように感じます。
昔は検索と広告の会社だったわけですが、今のGoogleは必ずしもそうではありません。
そのため、Web上に情報を増やすのを簡単にするためのApp EngineというのはGoogleからすると必ずしも必要ではなくなった気がします。

### 技術的な歴史

App Engine Standardは歴史が長いため、いくつかターニングポイントがあります。

1つ目のターニングポイントはThe JRE Class White Listのような制約がなくなり、外への通信も標準の方法でできるようになった瞬間です。
これは [gVisor](https://github.com/google/gvisor) によってもたらされました。
元々、存在していた制約は同じホストでマルチテナンシーでアプリケーションが動いてるため、他のアプリケーションを害しないように作られていました。
gVisorはアプリケーションをサンドボックスで区切り、それぞれの環境の外に悪影響を与えないようにすることができます。

2つ目のターニングポイントはPlatformとして一度限界を迎えたことで起こりました。
多くの独自APIを持っていましたが、これらはApp Engineからしか使えなかったため、それ以外のプロダクトを使っている人からすると存在しないものでした。
そして、Google Cloudには多くのプロダクトがリリースされていきます。
Compute Engine, Google Kubernetes Engine, Dataflow, Cloud Functions, Cloud Run...
自分のコードを動かせるものたちは多くありますが、それらからはApp Engine専用のAPIは呼び出せません。
IAMも同じProjectのApp Engineから無条件に呼べるだけで、現在のGoogle Cloudの一般的なAPIとは親和性はありません。

Googleからすると運用が必要だけど、使う人は増えないプロダクトたち・・・という状態になってしまったので、一度区切りが付けられようとしました。
各Runtimeの特定Version以上は2nd genとして、App Engine固有のAPIは使えないとされました。
しかし、これは既存のユーザには非常に厳しいものでした。
App Engine固有のAPIを本気出せば別の何かに置き換えれるかもしれませんが、かなりの労力が必要になります。
運用はしているが開発はもうしてないようなサービスだとなかなか大変です。

というわけで、結局、この世界線は消えて、2nd genでもApp Engine固有のAPIは使えるようになりました。
中々の大混乱があったので、[Document上は今でも2nd genではApp Engine固有のAPIが使えない雰囲気](https://cloud.google.com/appengine/docs/standard/runtimes?hl=en) になっています。
apstndbさんの [ポエム](https://qiita.com/apstndb/items/314e461aed518a4ad26f) もずいぶん長くなってしまっています。
ただ、今後はApp Engine固有のAPIにUPDATEは入らないでしょうし、緩やかな死を迎える状態だと思うので、使う場合は消すよーって言われたら、適当に移行できるような形で組み込んでおくと良いと思います。

ちなみに筆者が地味に使いたいのは [Memcache API](https://cloud.google.com/appengine/docs/standard/services/memcache?tab=go) です。
これはKey Value Storeのシンプルなキャッシュなのですが、Shared Memcacheなら指定したExpireより前に消えてしまうことはあるけど、お値段が無料というのが大きな魅力でした。

### 現在

これから新しくApp Engineを使うなら、少なくともApp Engine固有のAPIは使わない方が良いでしょう。
使う場合は移行することを常に意識してコードを組んでおくのが良いと思います。
また、上記のような歴史があるので、App Engineの古い記事は参考にならないと言うか、参考にするには歴史的経緯を含めた知識が要求される状態になっているため、注意しましょう。

## App Engine Flexible Environment

Flexible EnvironmentはVM上でApp EngineのContainerを動作させるプロダクトです。
元々用意されているRuntimeを使うこともできますが、任意のDockerfileを動かすことも可能です。
VersioningなどStandard Environmentと同様の機能もありますが、VMなのでSpinupが1minほどかかるし、App Engine固有のAPIは使えないので、微妙になんとも言い難いプロダクトでした。

### 技術的な歴史

Standard Environemntが多くの制約を抱えていた頃、その制約を乗り越えるために作り出されました。
生み出されるまで結構な時間がかかっており、VM-based Backends -> Managed VMs -> Flexible Environmentと名前を変えています。
[Managed VMs誕生までの歴史を振り返る](https://qiita.com/sinmetal/items/68f0e21e1f33e3a553a1) で振り返ったことがあるので、興味がある方は読んでみてください。

### 現在

Standard Environmentの制約の多くがなくなり、Containerを動かすならCloud RunやGoogle Kubernetes Engineがある今、Flexible Environmentのポジションは結構微妙です。
正直、筆者は何に使うのかよく分かりません。
時代の波の合間で生まれたが、流れには乗り切れず、中途半端になってしまった少しかわいそうなプロダクトです。

## Cloud Functions

Serverlessという言葉が流行り始めて、Function as a Serviceが流行った時に誕生しました。
1 Functionにつき1つDeployするので、これでアプリケーションを作るというよりは、画像がアップロードされたらサムネイルを作るといった何かをトリガーして1つだけ処理を行う時に使います。
リリース当初は元々App Engineがあるので、Cloud Function使う理由ってあんまりないんじゃ・・・？と思ったりしていましたが、シンプルなプロダクトではありました。

### 現在

Function as a Serviceとしてシンプルなポジションを確立しています。
[1st genと2nd genがあり](https://cloud.google.com/functions/docs/concepts/version-comparison) 、ユースケースでどちらを使うか選択できます。
1st genの方がThe Function as a Serviceといった感じの構成で、2nd genは柔軟性が上がって、インフラの利用効率が良くなっている印象です。
Event Triggerも1st gen時代はCloud Function専用に用意されていましたが、その後、 [Eventarc](https://cloud.google.com/eventarc/docs/overview) がGoogle Cloud全体のイベントトリガープロダクトとなりました。
2nd genではEventarcが中心になっています。

1st genと2nd genの使い分けですが、以下のような感じでしょうか。
ちょっとしたことを行うなら1st gen、重たい処理や多くのRequestを処理するなら2nd genですね。

#### 1st genが向きそう

* Requestが少ない
* 1 Instanceで同時に複数Request処理できない

#### 2nd genが向きそう

* Requestが多い
* 1 Instanceで同時に複数Request処理できる
* spinupに時間がかかるので、新しいInstanceが作られる頻度を減らしたい

## Cloud Run

App Engine Standard, Flexible Environment, Cloud Functions...と歴史を重ねて最終的に出てきたのがCloud Runです。
HTTP Requestを受け取る任意のContainer ImageをDeployして動かすことができます。
もう全部こいつでいいんじゃ？と思えるほどのポテンシャルを秘めており、機能追加も盛んなプロダクトになっています。

App EngineはWebアプリケーションのためのプラットフォームでしたが、Cloud RunはGoogle Cloudで現在のServerlessプロダクトを作るとしたら、こうなるだろうという感じのプロダクトです。
[gRPC](https://cloud.google.com/run/docs/triggering/grpc) や [Web Socket](https://cloud.google.com/run/docs/triggering/websockets) など、App Engine Standard Environmentで期待されたけど、実現できなかった機能が搭載されており、現代の技術でもう一回Serverlssプロダクトを作った感じがあります。

### 現在

[Direct VPC](https://cloud.google.com/run/docs/configuring/vpc-direct-vpc?hl=en), [Sidecar Container](https://cloud.google.com/run/docs/deploying?hl=en#sidecars) など欲しいなーと思う機能がリリースされていっていて、人類の期待を背負っています。

[Cloud Runにも1st genと2nd gen](https://cloud.google.com/run/docs/about-execution-environments) があります。
使い分けは公式ドキュメントの通りですね。

## Serverlessプロダクトの最近

役割分けされているServerlessプロダクトたちですが、裏の仕組みは整理され、統合されていってる気配があります。
Containerを動かすというところは同じになっているので、 [buildpacks](https://github.com/GoogleCloudPlatform/buildpacks) で各プロダクトのContainer Imageを作るようになっています。
仕組みが整備されたことで、Runtimeの更新が早くなりました。
App Engineも各Runtimeの新しいVersionに対応するのに昔は年単位でかかっていましたが、最近は早くなりました。

App Engine Standardの1st gen, 2nd genとCloud Functions, Cloud Runの1st gen, 2nd genは内容が異なります。
App Engine Standardは2nd genが主にgVisorですが、Cloud FunctionsとCloud Runは1st genがgVisorです。([Cloud Run](https://cloud.google.com/run/docs/container-contract), [Cloud Functions](https://cloud.google.com/functions/docs/securing?hl=ja#isolation_and_sandboxing))
リリース時期などを考えるとApp Engine Standard 2nd genと似た仕組みで動いていたのではないかと思います。
gVisorの場合、spinupは早くて良いのですが、Linuxと完全な互換性はないため、なんでも動くわけでは有りません。([gVisor syscall 互換性リファレンス](https://gvisor.dev/docs/user_guide/compatibility/linux/amd64/))
Cloud Functions gen2はCloud Run gen1の上で動くようになったので仕組みが統一された形になりました。

Cloud Run gen2はgVisorがなくなり、Linuxとの完全な互換性を持っています。
spinupが少し遅くなったのと必要なマシンスペックが上がっていますが、起動してしまえば早いといった感じになっています。
max concurrent requestも2以上を指定できるようになっているので、DBに接続する必要があるFunctionでRequestが多い場合などはgen2を使った方が効率よく処理できるようになりました。

|  | 1st gen | 2nd gen |
| ---- | ---- | ---- |
| App Engine Standard | 謎 | gVisor |
| Cloud Functions | gVisor | gVisor |
| Cloud Run | gVisor | VM |

長時間処理を行うための [Cloud Run Jobs](https://cloud.google.com/run/docs/execute/jobs) が登場したりと、まだ、Serverlessプロダクトには多くのことが求められています。
App EngineはWebのためのものでしたが、Cloud RunはContainerになってたらなんでも乗せたい人類の夢が集められてますね。
今後のアップデートにも期待しましょう。