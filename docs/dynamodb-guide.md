# DynamoDB & aws-record 学習ガイド

rails-dynamodb-taskboard プロジェクトを題材に、DynamoDB の基本概念と aws-record gem の使い方を解説する。

---

## 目次

1. [DynamoDB の基本概念](#1-dynamodb-の基本概念)
2. [シングルテーブル設計](#2-シングルテーブル設計)
3. [DynamoDB の主要オペレーション](#3-dynamodb-の主要オペレーション)
4. [Global Secondary Index (GSI)](#4-global-secondary-index-gsi)
5. [aws-record gem の使い方](#5-aws-record-gem-の使い方)
6. [aws-sdk-dynamodb（低レベル Client）の使い方](#6-aws-sdk-dynamodb低レベル-clientの使い方)
7. [Sort Key の設計テクニック](#7-sort-key-の設計テクニック)
8. [本プロジェクトのコード対応表](#8-本プロジェクトのコード対応表)

---

## 1. DynamoDB の基本概念

### テーブル / アイテム / 属性

| DynamoDB の用語  | RDB での対応 | 説明                     |
| ---------------- | ------------ | ------------------------ |
| テーブル (Table) | テーブル     | データの格納先           |
| アイテム (Item)  | 行 (Row)     | 1つのレコード            |
| 属性 (Attribute) | 列 (Column)  | アイテム内の個々のデータ |

RDB と異なり、DynamoDB のアイテムはスキーマレスである。主キー以外の属性はアイテムごとに異なっていてもよい。

### Primary Key の2種類

**1. 単一キー（Partition Key のみ）**

```
PK だけでアイテムを一意に特定する
例: PK = "user123"
```

**2. 複合キー（Partition Key + Sort Key）**

```txt
PK と SK の組み合わせでアイテムを一意に特定する
例: PK = "USER#user1", SK = "METADATA"
例: PK = "USER#user1", SK = "PROJECT#proj1"
```

本プロジェクトでは**複合キー**を採用している。

### Partition Key (PK) と Sort Key (SK) の役割

- **Partition Key (PK)**: データがどのパーティションに保存されるかを決める。同じ PK を持つアイテムは同じパーティションに格納される。
- **Sort Key (SK)**: 同一パーティション内でアイテムをソート順に並べる。範囲クエリ（`begins_with`、`BETWEEN` など）が可能になる。

### RDB との考え方の違い

| RDB                                                      | DynamoDB                                                            |
| -------------------------------------------------------- | ------------------------------------------------------------------- |
| まずエンティティ（正規化）を設計し、後からクエリを考える | **アクセスパターンから逆算**してテーブルを設計する                  |
| JOIN で柔軟にデータを結合                                | JOIN はない。1回のクエリで必要なデータが取れるように設計する        |
| テーブルを正規化して分割                                 | 1つのテーブルに複数エンティティを同居させる（シングルテーブル設計） |
| インデックスは後付けで追加可能                           | GSI は事前にアクセスパターンを想定して設計する                      |

---

## 2. シングルテーブル設計

### なぜ1つのテーブルに複数エンティティを入れるのか

DynamoDB では JOIN ができないため、関連データを同一パーティションに配置して1回の Query で取得する設計が推奨される。本プロジェクトでは `TaskBoard` という1つのテーブルに User / Project / Task の3種類のエンティティを格納している。

### PK/SK の命名規約

エンティティの種類ごとにプレフィックスを付与し、同一テーブル内でエンティティを区別する。

| エンティティ | PK                     | SK                          |
| ------------ | ---------------------- | --------------------------- |
| User         | `USER#<user_id>`       | `METADATA`                  |
| Project      | `USER#<owner_id>`      | `PROJECT#<project_id>`      |
| Task         | `PROJECT#<project_id>` | `TASK#<due_date>#<task_id>` |

### TaskBoard テーブルの設計図

```txt
TaskBoard テーブル
┌─────────────────────┬───────────────────────────────┬────────────────────────┐
│ pk (HASH)           │ sk (RANGE)                    │ その他の属性           │
├─────────────────────┼───────────────────────────────┼────────────────────────┤
│ USER#user1          │ METADATA                      │ name, email, ...       │
│ USER#user1          │ PROJECT#proj1                 │ name, description, ... │
│ USER#user1          │ PROJECT#proj2                 │ name, description, ... │
│ USER#user2          │ METADATA                      │ name, email, ...       │
│ USER#user2          │ PROJECT#proj3                 │ name, description, ... │
│ PROJECT#proj1       │ TASK#2026-03-01#task1         │ title, status, ...     │
│ PROJECT#proj1       │ TASK#2026-03-05#task2         │ title, status, ...     │
│ PROJECT#proj1       │ TASK#2026-03-10#task3         │ title, status, ...     │
│ PROJECT#proj2       │ TASK#2026-03-02#task4         │ title, status, ...     │
│ ...                 │ ...                           │ ...                    │
└─────────────────────┴───────────────────────────────┴────────────────────────┘
```

**ポイント:**

- `USER#user1` パーティションに対して Query すると、そのユーザーのメタデータと全プロジェクトが1回で取得できる
- `PROJECT#proj1` パーティションに対して Query すると、そのプロジェクトの全タスクが due_date 順で取得できる

### entity_type 属性によるエンティティ判別

各アイテムに `entity_type` 属性（`"User"` / `"Project"` / `"Task"`）を持たせている。Scan で全件取得する際の `filter_expression` でエンティティ種別を絞り込むために使う。

---

## 3. DynamoDB の主要オペレーション

### GetItem — PK + SK を指定して1件取得

最も効率的な取得方法。主キー（PK + SK）を完全指定して1件だけ返す。

```ruby
# app/models/user.rb
def self.find(user_id)
  result = Aws::DynamoDB::Client.new.get_item(
    table_name: "TaskBoard",
    key: { "pk" => "USER##{user_id}", "sk" => "METADATA" }
  )
  return nil unless result.item
  build_from_item(result.item)
end
```

- **消費キャパシティ**: 最小（ピンポイントアクセス）
- **ユースケース**: IDがわかっているアイテムの取得

### Query — PK指定 + SK条件でソート済み取得

同一パーティション内のアイテムを SK の条件で絞り込む。結果は SK でソートされた状態で返る。

#### begins_with — プレフィックス一致

```ruby
# app/models/project.rb
def self.for_user(user_id)
  result = Aws::DynamoDB::Client.new.query(
    table_name: "TaskBoard",
    key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
    expression_attribute_values: {
      ":pk" => "USER##{user_id}",
      ":sk_prefix" => "PROJECT#"
    }
  )
  result.items.map { |item| build_from_item(item) }
end
```

`USER#user1` パーティション内で SK が `PROJECT#` で始まるアイテムだけを取得する。これにより、ユーザーに紐づくプロジェクト一覧を効率的に取得できる。

#### BETWEEN — 範囲指定

```ruby
# app/models/task.rb
def self.for_project_due_before(project_id, date)
  result = Aws::DynamoDB::Client.new.query(
    table_name: "TaskBoard",
    key_condition_expression: "pk = :pk AND sk BETWEEN :sk_start AND :sk_end",
    expression_attribute_values: {
      ":pk" => "PROJECT##{project_id}",
      ":sk_start" => "TASK#",
      ":sk_end" => "TASK##{date}~"
    }
  )
  result.items.map { |item| build_from_item(item) }
end
```

SK の範囲指定により、指定日以前の due_date を持つタスクだけを取得する。`~` は ASCII コードで `z` より後にあるため、`date` で始まるすべてのキーを含む。

### Scan — テーブル全件走査 + FilterExpression

テーブルの全アイテムを読み取り、フィルタ条件に合致するものだけを返す。

```ruby
# app/models/user.rb
def self.all_users
  result = Aws::DynamoDB::Client.new.scan(
    table_name: "TaskBoard",
    filter_expression: "entity_type = :type",
    expression_attribute_values: { ":type" => "User" }
  )
  result.items.map { |item| build_from_item(item) }
end
```

> **Scan の注意点**
>
> - Scan は**テーブル全体を読み取ってからフィルタする**。フィルタで絞り込まれても、消費キャパシティは全件分かかる。
> - データ量が増えるほどコストとレイテンシが増大する。
> - 管理画面のユーザー一覧など、頻度が低い操作に限定して使うべき。
> - 頻繁にアクセスするパターンには Query や GSI を使う。

### PutItem — アイテムの書き込み

主キーが同じアイテムがあれば上書き、なければ新規作成する。

```ruby
# lib/tasks/dynamodb.rake（seed タスクより抜粋）
client.put_item(
  table_name: "TaskBoard",
  item: {
    "pk" => "USER##{u[:id]}",
    "sk" => "METADATA",
    "user_id" => u[:id],
    "name" => u[:name],
    "email" => u[:email],
    "entity_type" => "User"
  }
)
```

### DeleteItem — アイテムの削除

主キーを指定してアイテムを削除する。aws-record の `delete!` メソッドで実行できる。

---

## 4. Global Secondary Index (GSI)

### GSI とは何か

ベーステーブルとは**別の PK/SK の組み合わせ**でデータにアクセスするための仕組み。ベーステーブルの主キーでは対応できないアクセスパターンを実現する。

### なぜ必要か

本プロジェクトのベーステーブルでは以下のクエリに対応できない:

- **ステータス別のタスク一覧**: PK が `PROJECT#xxx` なので、ステータスで横断的に検索できない
- **担当者別のタスク一覧**: 同様に、担当者で横断的に検索できない

これらのアクセスパターンに対応するため、GSI を2つ作成している。

### GSI の仕組み

GSI はベーステーブルのデータを**別の PK/SK で再編成したビュー**のようなもの。ベーステーブルのアイテムが更新されると、GSI も自動的に更新される。

```txt
ベーステーブル              GSI1 (ステータス別)         GSI2 (担当者別)
┌──────────┬──────────┐    ┌──────────┬──────────┐    ┌──────────┬──────────┐
│ pk       │ sk       │    │ gsi1pk   │ gsi1sk   │    │ gsi2pk   │ gsi2sk   │
├──────────┼──────────┤    ├──────────┼──────────┤    ├──────────┼──────────┤
│PROJECT#  │TASK#...  │    │STATUS#   │date#id   │    │ASSIGNEE# │date#id   │
│proj1     │task1     │───>│done      │          │───>│user1     │          │
└──────────┴──────────┘    └──────────┴──────────┘    └──────────┴──────────┘
```

### 本プロジェクトの GSI 設計

**GSI1: ステータス別タスク一覧**

| 項目          | 値                                                                    |
| ------------- | --------------------------------------------------------------------- |
| index_name    | `gsi1`                                                                |
| Partition Key | `gsi1pk` = `STATUS#<status>`                                          |
| Sort Key      | `gsi1sk` = `<due_date>#<task_id>`                                     |
| 用途          | `Task.by_status("todo")` — 特定ステータスのタスクを due_date 順で取得 |

```ruby
# app/models/task.rb
def self.by_status(status)
  result = Aws::DynamoDB::Client.new.query(
    table_name: "TaskBoard",
    index_name: "gsi1",
    key_condition_expression: "gsi1pk = :pk",
    expression_attribute_values: {
      ":pk" => "STATUS##{status}"
    }
  )
  result.items.map { |item| build_from_item(item) }
end
```

**GSI2: 担当者別タスク一覧**

| 項目          | 値                                                                   |
| ------------- | -------------------------------------------------------------------- |
| index_name    | `gsi2`                                                               |
| Partition Key | `gsi2pk` = `ASSIGNEE#<user_id>`                                      |
| Sort Key      | `gsi2sk` = `<due_date>#<task_id>`                                    |
| 用途          | `Task.by_assignee("user1")` — 特定担当者のタスクを due_date 順で取得 |

```ruby
# app/models/task.rb
def self.by_assignee(user_id)
  result = Aws::DynamoDB::Client.new.query(
    table_name: "TaskBoard",
    index_name: "gsi2",
    key_condition_expression: "gsi2pk = :pk",
    expression_attribute_values: {
      ":pk" => "ASSIGNEE##{user_id}"
    }
  )
  result.items.map { |item| build_from_item(item) }
end
```

### GSI の属性投影（Projection）

GSI にどの属性をコピーするかを指定する。

| 投影タイプ  | 説明                                                   |
| ----------- | ------------------------------------------------------ |
| `ALL`       | ベーステーブルの全属性をコピー（本プロジェクトで採用） |
| `KEYS_ONLY` | ベーステーブルの主キーと GSI のキーのみ                |
| `INCLUDE`   | 指定した属性のみ追加でコピー                           |

`ALL` はクエリ後にベーステーブルへの追加アクセスが不要だが、ストレージコストが増える。必要な属性が限られている場合は `INCLUDE` を検討する。

### GSI 更新時の注意点

- ベーステーブルのアイテムを更新すると、GSI のキー属性（`gsi1pk` 等）の値が変わった場合に GSI のエントリが自動的に再編成される
- 本プロジェクトの `save_as_task` メソッドでは、保存時に GSI のキー属性も一緒にセットしている:

```ruby
# app/models/task.rb
def save_as_task
  self.pk = "PROJECT##{project_id}"
  self.sk = "TASK##{due_date}##{task_id}"
  self.entity_type = "Task"
  self.gsi1pk = "STATUS##{status}"        # GSI1 のキーを設定
  self.gsi1sk = "#{due_date}##{task_id}"
  self.gsi2pk = "ASSIGNEE##{assignee_id}" # GSI2 のキーを設定
  self.gsi2sk = "#{due_date}##{task_id}"
  save
end
```

---

## 5. aws-record gem の使い方

aws-record は DynamoDB のアイテムを Ruby オブジェクトとしてマッピングする ORM ライクな gem である。

### モデル定義

```ruby
class User
  include Aws::Record                    # aws-record を有効化

  set_table_name "TaskBoard"             # 使用するテーブル名

  string_attr :pk, hash_key: true        # Partition Key
  string_attr :sk, range_key: true       # Sort Key
  string_attr :user_id                   # 通常の属性
  string_attr :name
  string_attr :email
  string_attr :entity_type
end
```

### 属性定義メソッド

| メソッド          | 説明                              |
| ----------------- | --------------------------------- |
| `string_attr`     | 文字列型（DynamoDB の `S` 型）    |
| `integer_attr`    | 整数型（DynamoDB の `N` 型）      |
| `boolean_attr`    | 真偽値型（DynamoDB の `BOOL` 型） |
| `hash_key: true`  | Partition Key として指定          |
| `range_key: true` | Sort Key として指定               |

### save メソッドによる書き込み

```ruby
user = User.new
user.pk = "USER#user1"
user.sk = "METADATA"
user.user_id = "user1"
user.name = "Alice"
user.entity_type = "User"
user.save  # DynamoDB に PutItem を実行
```

本プロジェクトでは `save_as_user` / `save_as_project` / `save_as_task` のようなラッパーメソッドで PK/SK を自動設定している。

### aws-record と Aws::DynamoDB::Client の使い分け

| 操作                  | aws-record          | Client 直接使用        |
| --------------------- | ------------------- | ---------------------- |
| 単一アイテムの保存    | `save`              | 不要                   |
| 単一アイテムの取得    | `find` (主キー指定) | `get_item`             |
| Query（条件付き取得） | 非対応              | `query`                |
| Scan（全件取得）      | 非対応              | `scan`                 |
| GSI を使った検索      | 非対応              | `query` + `index_name` |

aws-record はシンプルな CRUD に向いており、Query・Scan・GSI 検索のような条件付き操作は `Aws::DynamoDB::Client` を直接使う必要がある。本プロジェクトではモデルクラスの中で Client を直接呼び出す設計を採用している。

---

## 6. aws-sdk-dynamodb（低レベル Client）の使い方

### AWS 設定

```ruby
# config/initializers/aws.rb
Aws.config.update(
  region: "ap-northeast-1",
  endpoint: ENV.fetch("DYNAMODB_ENDPOINT", "http://localhost:8000"),
  credentials: Aws::Credentials.new("dummy", "dummy")
)
```

ローカル開発では DynamoDB Local（`http://localhost:8000`）を使用する。

### テーブル作成（create_table + GSI 定義）

```ruby
# lib/tasks/dynamodb.rake
client = Aws::DynamoDB::Client.new

client.create_table(
  table_name: "TaskBoard",
  key_schema: [
    { attribute_name: "pk", key_type: "HASH" },     # Partition Key
    { attribute_name: "sk", key_type: "RANGE" }      # Sort Key
  ],
  attribute_definitions: [
    { attribute_name: "pk", attribute_type: "S" },   # S = String
    { attribute_name: "sk", attribute_type: "S" },
    { attribute_name: "gsi1pk", attribute_type: "S" },
    { attribute_name: "gsi1sk", attribute_type: "S" },
    { attribute_name: "gsi2pk", attribute_type: "S" },
    { attribute_name: "gsi2sk", attribute_type: "S" }
  ],
  global_secondary_indexes: [
    {
      index_name: "gsi1",
      key_schema: [
        { attribute_name: "gsi1pk", key_type: "HASH" },
        { attribute_name: "gsi1sk", key_type: "RANGE" }
      ],
      projection: { projection_type: "ALL" }
    },
    {
      index_name: "gsi2",
      key_schema: [
        { attribute_name: "gsi2pk", key_type: "HASH" },
        { attribute_name: "gsi2sk", key_type: "RANGE" }
      ],
      projection: { projection_type: "ALL" }
    }
  ],
  billing_mode: "PAY_PER_REQUEST"    # オンデマンドキャパシティ
)
```

**注意点:**

- `attribute_definitions` にはキー属性（PK, SK, GSI のキー）のみを定義する。通常の属性は不要（スキーマレスのため）。
- `billing_mode: "PAY_PER_REQUEST"` はオンデマンド課金。開発・小規模向け。

### query メソッドの使い方

```ruby
client = Aws::DynamoDB::Client.new

# PK 指定 + SK の begins_with 条件
result = client.query(
  table_name: "TaskBoard",
  key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
  expression_attribute_values: {
    ":pk" => "USER#user1",
    ":sk_prefix" => "PROJECT#"
  }
)

# GSI を使った検索（index_name を指定）
result = client.query(
  table_name: "TaskBoard",
  index_name: "gsi1",                                    # GSI 名を指定
  key_condition_expression: "gsi1pk = :pk",
  expression_attribute_values: {
    ":pk" => "STATUS#todo"
  }
)
```

| パラメータ                    | 説明                                                                 |
| ----------------------------- | -------------------------------------------------------------------- |
| `table_name`                  | 対象テーブル                                                         |
| `index_name`                  | GSI を使う場合にインデックス名を指定                                 |
| `key_condition_expression`    | PK/SK の条件式。`=`, `begins_with`, `BETWEEN`, `<`, `>` 等が使える   |
| `expression_attribute_values` | 条件式内のプレースホルダ（`:pk` 等）に値をバインド                   |
| `filter_expression`           | （オプション）結果をさらにフィルタ。ただしキャパシティは節約できない |

### scan メソッドの使い方

```ruby
result = client.scan(
  table_name: "TaskBoard",
  filter_expression: "entity_type = :type",
  expression_attribute_values: { ":type" => "User" }
)
```

### get_item / put_item / delete_item

```ruby
# 1件取得
result = client.get_item(
  table_name: "TaskBoard",
  key: { "pk" => "USER#user1", "sk" => "METADATA" }
)

# 書き込み
client.put_item(
  table_name: "TaskBoard",
  item: { "pk" => "USER#user1", "sk" => "METADATA", "name" => "Alice", ... }
)

# 削除
client.delete_item(
  table_name: "TaskBoard",
  key: { "pk" => "USER#user1", "sk" => "METADATA" }
)
```

---

## 7. Sort Key の設計テクニック

### SK にプレフィックスを使う理由

SK にプレフィックス（`TASK#`, `PROJECT#` など）を付けることで、同一パーティション内の異なるエンティティを区別し、`begins_with` で種類ごとに絞り込める。

```
PK = "USER#user1" のパーティション:
  SK = "METADATA"         → User のメタ情報
  SK = "PROJECT#proj1"    → Project
  SK = "PROJECT#proj2"    → Project
```

`begins_with(sk, "PROJECT#")` で Project だけを取得できる。

### 日付を SK に含めることでソートを実現

DynamoDB は SK の値で自動的にソートする。日付を ISO 8601 形式（`YYYY-MM-DD`）で SK に含めると、日付順のソートが自然に実現する。

```
SK = "TASK#2026-03-01#task1"   ← 最初に返る
SK = "TASK#2026-03-05#task2"   ← 2番目
SK = "TASK#2026-03-10#task3"   ← 3番目
```

本プロジェクトの Task の SK 設計:

```ruby
# app/models/task.rb
self.sk = "TASK##{due_date}##{task_id}"
# 例: "TASK#2026-03-01#task1"
```

### begins_with と BETWEEN による範囲クエリ

**begins_with**: プレフィックスが一致するアイテムをすべて取得

```ruby
# PROJECT#proj1 配下の全タスク
key_condition_expression: "pk = :pk AND begins_with(sk, :prefix)"
# :prefix => "TASK#"
```

**BETWEEN**: 範囲を指定してアイテムを取得

```ruby
# 2026-03-07 以前が due_date のタスク
key_condition_expression: "pk = :pk AND sk BETWEEN :start AND :end"
# :start => "TASK#"
# :end   => "TASK#2026-03-07~"
```

`~` は ASCII で `z` より後ろの文字なので、`TASK#2026-03-07` で始まるすべてのキーを含む上限として機能する。

---

## 8. 本プロジェクトのコード対応表

| アクセスパターン           | モデルメソッド                          | DynamoDB 操作           | キー条件                                               |
| -------------------------- | --------------------------------------- | ----------------------- | ------------------------------------------------------ |
| ユーザーを ID で取得       | `User.find(user_id)`                    | GetItem                 | `pk=USER#<id>`, `sk=METADATA`                          |
| 全ユーザー一覧             | `User.all_users`                        | Scan + FilterExpression | `entity_type = "User"`                                 |
| ユーザーのプロジェクト一覧 | `Project.for_user(user_id)`             | Query + begins_with     | `pk=USER#<id>`, `sk begins_with PROJECT#`              |
| プロジェクトを取得         | `Project.find(owner_id, project_id)`    | GetItem                 | `pk=USER#<owner_id>`, `sk=PROJECT#<id>`                |
| プロジェクト ID で検索     | `Project.find_by_project_id(id)`        | Scan + FilterExpression | `entity_type="Project" AND project_id=<id>`            |
| 全プロジェクト一覧         | `Project.all_projects`                  | Scan + FilterExpression | `entity_type = "Project"`                              |
| プロジェクトのタスク一覧   | `Task.for_project(project_id)`          | Query + begins_with     | `pk=PROJECT#<id>`, `sk begins_with TASK#`              |
| 期限内タスク               | `Task.for_project_due_before(id, date)` | Query + BETWEEN         | `pk=PROJECT#<id>`, `sk BETWEEN TASK# AND TASK#<date>~` |
| ステータス別タスク         | `Task.by_status(status)`                | Query (GSI1)            | `gsi1pk=STATUS#<status>`                               |
| 担当者別タスク             | `Task.by_assignee(user_id)`             | Query (GSI2)            | `gsi2pk=ASSIGNEE#<id>`                                 |
| タスクを保存               | `task.save_as_task`                     | PutItem (aws-record)    | PK/SK/GSI キーを自動設定                               |
| ユーザーを保存             | `user.save_as_user`                     | PutItem (aws-record)    | PK/SK を自動設定                                       |
| プロジェクトを保存         | `project.save_as_project`               | PutItem (aws-record)    | PK/SK を自動設定                                       |
| ユーザーを保存             | `user.save_as_user`                     | PutItem (aws-record)    | PK/SK を自動設定                                       |
| プロジェクトを保存         | `project.save_as_project`               | PutItem (aws-record)    | PK/SK を自動設定                                       |
