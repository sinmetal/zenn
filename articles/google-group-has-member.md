---
title: "Google Groupにメンバーが存在するか？"
emoji: "🐾"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: false
---

Google Cloudを使っていると時折Google Groupにメンバーが存在するかをチェックしたくなる時があります。
ただ、Google GroupはGoogle Workspaceの機能なので、Google Cloud側から使おうとするとややこしかったりするので、まとめてみました。

## [Directory API](https://developers.google.com/admin-sdk/directory/v1/guides)



## [Cloud Identity Groups API](https://cloud.google.com/identity/docs/how-to/setup)

Google Workspace Enterprise Standard以上 or Cloud Identity Premiumのみで使えるAPIです。
そのため、おそらく無料のGoogle Groupには使えない(筆者は確かめてない)と思われます。
ビジネス用途でGoogle Workspaceを使っている場合はEnterprise Standard以上であることがほとんどだと思うので、さして問題にはならないと思います。

[groups.memberships.checkTransitiveMembership](https://cloud.google.com/identity/docs/reference/rest/v1/groups.memberships/checkTransitiveMembership) を使うことで任意のGroupにMemberが存在するかをチェックすることができます。
Groupが入れ子になっていても、全部見て、結果を返してくれる便利なAPIです。

### 権限設定

権限としては確認したいGoogle Group、そしてそのGroupの中に入っているGroupに参加する必要があります。
Service AccountでAPIを実行する場合はService Accountを参加させます。
Groupのメンバーであればよいので、オーナーとして参加する必要はありません。
この時、確認したいGoogle Groupの中のGroupの権限を持っていない場合は、権限があるところだけ見て、結果を返してくれます。
見れる範囲に探しているAccountが見つかれば、 `200 OK hasMembership:true` が返ってきます。
見れる範囲では見つからず、権限が無く、探せない入れ子になっているGoogle Groupがある場合は、403が返ってきて、detailには見れなかったGoogle Groupがあり、まだ探せる範囲があることを示されます。

### groups.memberships.checkTransitiveMembershipを試す前の準備

groups.memberships.checkTransitiveMembershipを試してみる時にパラメーターとしてparentに指定する値がちょっと特殊です。
探索したいGoogle Groupを指定するのですが、Google Groupのメールアドレスを指定するのではなく、Google Groupが中で使っているKeyを指定します。
このKeyはGoogle GroupのWeb UIでは確認できないので、別途APIで確認する必要があります。

[groups.search](https://cloud.google.com/identity/docs/reference/rest/v1/groups/search) を使うのが比較的探しやすいと思います。
組織内にGoogle Groupが少なければ [groups.list](https://cloud.google.com/identity/docs/reference/rest/v1/groups/list) でもよいですが、数が多い場合は検索ができるgroups.searchが便利です。
どちらを使うにしろ、WorkspaceのCustomerIDを指定する必要があります。
WorkspaceのCustomerIDは管理画面で見ることができます。

![Google Workspace Customer ID](/images/google-group-has-member/google-workspace-customer-id.png)

#### query指定時に注意すること

google.searchでGoogle Groupのメールアドレスを検索条件に入れようとした時に一つ注意することがあります。
`parent == 'customers/XXXXXXX' && groupKey.contains('dev')` のようにqueryに指定して実行した場合、 `400 INVALID_ARGUMENT Request contains an invalid argument.` と返ってきます。
正解は `parent == 'customers/XXXXXXX' && group_key.contains('dev')` です。
ドキュメントの例だと `groupKey` と書いてありますが、実際には `group_key` と指定します。
[Client Libraryのコメント](https://github.com/googleapis/google-api-go-client/blob/af6aa38b90461f3a5d1bfe13a86aa788f4b08da1/cloudidentity/v1/cloudidentity-gen.go#L9020-L9026) を見ると、 `member_key_id` と書いてあるので、こっちが正しいです。
これはなかなかのトラップです。
ドキュメント上はキャメルケースだけど、本当はスネークケースを指定するという事象、昔もどこかで遭遇した気がするので、疑ってかかった方が良いポイントなのかもしれません。

### groups.memberships.checkTransitiveMembershipを試す

[groups.memberships.checkTransitiveMembership](https://cloud.google.com/identity/docs/reference/rest/v1/groups.memberships/checkTransitiveMembership) を実行するための値は揃いました。
parentには [groups.search](https://cloud.google.com/identity/docs/reference/rest/v1/groups/search) or [groups.list](https://cloud.google.com/identity/docs/reference/rest/v1/groups/list) で分かったGroupのKeyを指定します。
`groups/XXXXXXXXX` のような値です。
queryには `member_key_id == '{メールアドレス}'` を指定します。
これでResponseが得られます。
