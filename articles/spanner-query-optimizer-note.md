---
title: "Spanner Query Tuning Note"
emoji: "🐴"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp","spanner"]
published: true
---

sinmetalがQuery Tuningする時に使う覚書

## NOT NULL制約がない時に出てくる、謎のResidual Condition

シンプルなFilterでも `Seek Condition: IS_NOT_DISTINCT_FROM` と出た後に、 `Residual Condition` がかかることがある。
これは対象のColumnにNOT NULL制約がなくて、NULLが許容されているから。
この状態だと `@userID` にNULLが入る可能性があり、NULLを入れられてしまうと結果が `unknown` になってしまうので、Seek Conditionで取るつもりだけど、メモリ上でもう一回確認することになるので、Residual Conditionが追加で入ってくる。

```
CREATE TABLE Samples (
  UserID INT64,
  SampleID STRING(36) NOT NULL,
) PRIMARY KEY(UserID);

```

```
EXPLAIN
SELECT
  SampleID
FROM
  Samples
WHERE
  UserID = @userID 
```

```
+----+-----------------------------------------------------------------------------------------------------+
| ID | Query_Execution_Plan                                                                                |
+----+-----------------------------------------------------------------------------------------------------+
| *0 | Distributed Union (distribution_table: Samples, execution_method: Row, split_ranges_aligned: false) |
|  1 | +- Local Distributed Union (execution_method: Row)                                                  |
|  2 |    +- Serialize Result (execution_method: Row)                                                      |
| *3 |       +- Filter Scan (execution_method: Row, seekable_key_size: 0)                                  |
| *4 |          +- Table Scan (Table: Samples, execution_method: Row, scan_method: Row)                    |
+----+-----------------------------------------------------------------------------------------------------+
Predicates(identified by ID):
 0: Split Range: ($UserID = @userid)
 3: Residual Condition: ($UserID = @userid)
 4: Seek Condition: IS_NOT_DISTINCT_FROM($UserID, @userid)
```

### 対策

`@userID` にNULLが来た時の対応を明示的に入れてやる。
これでResidual Conditionがなくなる。

```
EXPLAIN
SELECT
  SampleID
FROM
  Samples
WHERE
  (UserID = @userID)
  OR (UserID IS NULL AND @userID IS NULL)
```

```
+----+-----------------------------------------------------------------------------------------------------+
| ID | Query_Execution_Plan                                                                                |
+----+-----------------------------------------------------------------------------------------------------+
| *0 | Distributed Union (distribution_table: Samples, execution_method: Row, split_ranges_aligned: false) |
|  1 | +- Local Distributed Union (execution_method: Row)                                                  |
|  2 |    +- Serialize Result (execution_method: Row)                                                      |
|  3 |       +- Filter Scan (execution_method: Row, seekable_key_size: 0)                                  |
| *4 |          +- Table Scan (Table: Samples, execution_method: Row, scan_method: Row)                    |
+----+-----------------------------------------------------------------------------------------------------+
Predicates(identified by ID):
 0: Split Range: IS_NOT_DISTINCT_FROM($UserID, @userid)
 4: Seek Condition: IS_NOT_DISTINCT_FROM($UserID, @userid)
```