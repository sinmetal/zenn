---
title: "小さなWebアプリケーションをGoogle Cloudで作る場合の構成例"
emoji: "🐁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: false
---

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
エッジキャッシュについては [昔少し書いた](https://qiita.com/sinmetal/items/37c105a098174fb6bf77) ので、気になる方は確認してください

ドメインも PROJECT_ID.REGION_ID.r.appspot.com が付与されているので、自分で用意する必要はありません。
カスタムドメインも設定できるのですが、 [東京リージョン(asia-northeast1)でカスタムドメインを設定すると、むしろus-central1にDeployするより遅くなってしまう](https://cloud.google.com/appengine/docs/standard/mapping-custom-domains?hl=en) ことに注意です。
この挙動はなかなかびっくりするもので、Zennでも [昔ハマった](https://zenn.dev/catnose99/articles/56f523d39cca43) みたいですね。

特定のGoogle WorkspaceのDomainや、Google Groupに所属している人だけにWebアプリケーションを見せたい時に [Identity-Aware Proxy](https://cloud.google.com/iap) で簡単に覆えるのも便利です。

App Engineの問題としては独自要素が多く、App Engine固有の知識が必要になります。
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
ちょうど今あなたがこの記事を読んでいるZennもこの構成で作られているみたいです。 ([Zennのバックエンドを Google App Engine から Cloud Run へ移行しました（無停止！YES！）](https://zenn.dev/team_zenn/articles/migrate-appengine-to-cloudrun)

LBを前に置けば [AppEngineにCustom Domain設定時にLatencyが増加する問題](https://cloud.google.com/appengine/docs/standard/mapping-custom-domains?hl=en) もありませんし、 [Cloud CDN](https://cloud.google.com/cdn/docs/overview) や[Cloud Armor](https://cloud.google.com/armor/docs/cloud-armor-overview) , [Identity-Aware Proxy](https://cloud.google.com/iap) も使えます。



## 長時間かかる処理を行うパターン