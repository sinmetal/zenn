---
title: "Google Cloud Serverless Product History"
emoji: "♥"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: false
---

sinmetalから見たGoogle Cloud Serverless Productたちの歴史と現状を振り返ります。

## リリース順

* Google App Engine Standard Environment
* Google App Engine Flexible Environment
* Cloud Functions
* Cloud Run

## Google App Engine Standard Environment

最古のServerless Productで昔はServerlessという言葉は使われておらず、WebアプリケーションのためのPlatform as a Serviceと呼ばれていました。
Google Cloudより昔からあるため、App Engine単体でPlatformになっています。
Google App EngineはPlatformなので、単純に自分のアプリケーションを動かすだけではなく、Webアプリケーションでよく必要になる要素がセットです。
全文検索のAPIや画像処理用のAPIなど様々なものがありました。
セットで提供されている者たちは独自のAPIだったため、SDKもLocal環境もすべて独自で用意されていました。
ただ、逆に制約も多くありました。
ローカルディスクへの書き込みができなかったり、外へ通信するにも専用のAPIを利用する必要がありました。
筆者は当時Javaを使っていましたが、JavaにはThe JRE Class White Listというものがあり、使えるものはここに載っているものだけでした。

![](/images/serverless-history/app-engine-standard-architecture.png)

これはこれでこの世界の中で生きていくには便利だったのですが、時が流れるに連れ、世界は変わっていきます。
Webアプリケーションに求められる機能も増えていき、スマートフォンの登場により、APIサーバの側面も強くなっていきました。

Cloudに求められるものも変わっていきました。
動画処理をしたり、ビッグデータ処理をしたり、現在では機械学習にもよく使われています。

また、Googleのビジネスも変わったように感じます。
昔は検索と広告の会社だったわけですが、今のGoogleは必ずしもそうではありません。
そのため、Web上に情報を増やすのを簡単にするためのGoogle App EngineというのはGoogleからすると必ずしも必要ではなくなった気がします。

### 技術的な歴史

Google App Engine Standardは歴史が長いため、いくつかターニングポイントがあります。

1つ目のターニングポイントはThe JRE Class White Listのような制約がなくなり、外への通信も標準の方法でできるようになった瞬間です。
これは [gVisor](https://github.com/google/gvisor) によってもたらされました。
元々、存在していた制約は同じホストでマルチテナンシーでアプリケーションが動いてるため、他のアプリケーションを害しないように作られていました。
gVisorはアプリケーションをサンドボックスで区切り、それぞれの環境の外に悪影響を与えないようにすることができます。

2つ目のターニングポイントはPlatformとして一度限界を迎えたことで起こりました。
非常に多くの独自APIを持っていましたが、これらはGoogle App Engineからしか使えなかったため、それ以外のプロダクトを使っている人からすると存在しないものでした。
そして、Google Cloudには多くのプロダクトがリリースされていきます。
Google Compute Engine, Google Kubernetes Engine, Cloud Dataflow, Cloud Functions, Cloud Run...
自分のコードを動かせるものたちは多くありますが、それらからはGoogle App Engine専用のAPIは呼びことができます。
IAMも同じProjectのGoogle App Engineから無条件に呼べるだけで、現在のGoogle Cloudと親和性はありません。

運用が必要だけど、使う人は増えないプロダクトたち・・・という状態になってしまったので、一度区切りが付けられようとしました。
各Runtimeの特定Version以上は2nd genとして、Google App Engine固有のAPIは使えないとされました。
しかし、これは既存のユーザには非常に厳しいものでした。
Google App Engine固有のAPIを本気出せば置き換えれるかもしれませんが、かなりの労力が必要になります。
運用はしているが開発はもうしてないようなサービスだとなかなか大変です。

というわけで、結局、この世界線は消えて、2nd genでもGoogle App Engine固有のAPIは使えるようになりました。
中々の大混乱があったので、[Document上は今でも2nd genではGoogle App Engine固有のAPIが使えない雰囲気](https://cloud.google.com/appengine/docs/standard/runtimes?hl=en) になっています。
apstndbさんの [ポエム](https://qiita.com/apstndb/items/314e461aed518a4ad26f) もずいぶん長くなってしまっています。
ただ、今後はGoogle App Engine固有のAPIにUPDATEは入らないでしょうし、緩やかな死を迎える状態だと思うので、使う場合は消すよーって言われたら、適当に移行できるような形で組み込んでおくと良いと思います。

ちなみに筆者が地味に使いたいのは [Memcache API](https://cloud.google.com/appengine/docs/standard/services/memcache?tab=go) です。
これはKey Value Store式のシンプルなキャッシュなのですが、Shared Memcacheなら指定したExpireより前に消えてしまう可能性はあるけど、無料という存在なので、お値段以上の効果がありました。

### 現在

これから新しくGoogle App Engineを使うなら、少なくともGoogle App Engine固有のAPIは使わない方が良いでしょう。
また、上記のような歴史があるので、Google App Engineの古い記事は参考にならないと言うか、参考にするには歴史的経緯を含めた知識が要求される状態になっているため、注意しましょう。

## Google App Engine Flexible Environment

