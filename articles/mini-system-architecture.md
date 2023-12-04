---
title: "小さなWebアプリケーションをGoogle Cloudで作る場合の構成例"
emoji: "🐁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: false
---

筆者が小さなWebアプリケーションをGoogle Cloudで構築する場合の構成をいくつか紹介します。

# [Firebase Hosting](https://firebase.google.com/docs/hosting) with [Cloud Run](https://cloud.google.com/run/docs/overview/what-is-cloud-run)

Firebase Hostingは静的コンテンツをDeployして配信するのを簡単に行えるプロダクトです。
[VersioningやPreviewの機能](https://firebase.google.com/docs/hosting/test-preview-deploy) もあり、 [カスタムドメインの設定](https://firebase.google.com/docs/hosting/custom-domain) もあるので、便利です。
動的コンテンツを配信したい場合は [指定したPathをCloud Runに送ることができます。](https://firebase.google.com/docs/hosting/cloud-run?hl=ja#direct_requests_to_container) 

Firebase HostingのRequestのTimeoutは60secなので、それ以上かかるような処理は何か考える必要があります。

# Google App Engine Standard Environment

# LB