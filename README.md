# Rails DynamoDB TaskBoard

DynamoDBの **Sort Key（SK）**、**Global Secondary Index（GSI）**、**シングルテーブル設計** を実践的に学べるタスク管理アプリケーションです。

## 学べるDynamoDB機能

| 機能                     | 画面                 | 説明                                                   |
| ------------------------ | -------------------- | ------------------------------------------------------ |
| **複合キー（PK + SK）**  | ユーザー詳細取得     | `PK=USER#id, SK=METADATA` で1アイテム取得              |
| **SK prefix query**      | プロジェクト一覧     | `PK=USER#id, SK begins_with PROJECT#`                  |
| **SK range query**       | タスク一覧（期限順） | `PK=PROJECT#id, SK begins_with TASK#` でソート済み取得 |
| **GSI（ステータス別）**  | ステータスタブ       | GSI1: `gsi1pk=STATUS#status` でプロジェクト横断検索    |
| **GSI（担当者別）**      | 担当タスク一覧       | GSI2: `gsi2pk=ASSIGNEE#user_id` でプロジェクト横断検索 |
| **シングルテーブル設計** | 全体                 | User, Project, Task を1つの `TaskBoard` テーブルに格納 |

## テーブル設計

### テーブル: `TaskBoard`（シングルテーブル設計）

| アイテム | PK                   | SK                        |
| -------- | -------------------- | ------------------------- |
| User     | USER#<user_id>       | METADATA                  |
| Project  | USER#<owner_id>      | PROJECT#<project_id>      |
| Task     | PROJECT#<project_id> | TASK#<due_date>#<task_id> |

### GSI

| GSI  | PK                 | SK                   | 用途         |
| ---- | ------------------ | -------------------- | ------------ |
| gsi1 | STATUS#<status>    | <due_date>#<task_id> | ステータス別 |
| gsi2 | ASSIGNEE#<user_id> | <due_date>#<task_id> | 担当者別     |

## セットアップ

```bash
cd rails-dynamodb-taskboard
docker compose up --build
```

テーブルは自動作成されます（docker-entrypoint）。

サンプルデータの投入:

```bash
docker compose exec web bundle exec rake dynamodb:seed
```

<http://localhost:3000> にアクセスしてください。

## 技術スタック

- Ruby 3.3.10 / Rails 7.2
- aws-record + aws-sdk-dynamodb
- Hotwire (Turbo + Stimulus) / Importmap
- Docker + docker-compose + DynamoDB Local

## アクセスパターン

| #   | パターン                   | キー/インデックス                     | DynamoDB操作 |
| --- | -------------------------- | ------------------------------------- | ------------ |
| 1   | ユーザー取得               | `PK=USER#id, SK=METADATA`             | GetItem      |
| 2   | ユーザーのプロジェクト一覧 | `PK=USER#id, SK begins_with PROJECT#` | Query        |
| 3   | プロジェクト内タスク一覧   | `PK=PROJECT#id, SK begins_with TASK#` | Query        |
| 4   | 期限前タスク絞り込み       | `PK=PROJECT#id, SK BETWEEN`           | Query        |
| 5   | ステータス別タスク一覧     | GSI1: `gsi1pk=STATUS#status`          | Query (GSI)  |
| 6   | 担当者別タスク一覧         | GSI2: `gsi2pk=ASSIGNEE#user_id`       | Query (GSI)  |
