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

# Cloud Firestore

# BigQuery