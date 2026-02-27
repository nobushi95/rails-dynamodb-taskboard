# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

DynamoDBのシングルテーブル設計を学ぶためのRails製タスク管理アプリ。User, Project, Taskの3エンティティを1つの`TaskBoard`テーブルに格納する。

## 開発環境

Docker + DynamoDB Localで動作する。ActiveRecordは使わず、aws-record + aws-sdk-dynamodbを使用。

```bash
# 起動（テーブルは自動作成される）
docker compose up --build

# サンプルデータ投入
docker compose exec web bundle exec rake dynamodb:seed

# テーブル再作成
docker compose exec web bundle exec rake dynamodb:create_tables

# Lint
bundle exec rubocop
bundle exec rubocop -a  # 自動修正
```

アクセス: http://localhost:3000

## アーキテクチャ

### Rails構成
- Rails 7.2 (API非使用、通常のMVC)
- ActiveRecordなし: `config/application.rb`でActiveModel/ActionController/ActionViewのみロード
- フロントエンド: Hotwire (Turbo + Stimulus) + Importmap

### DynamoDBシングルテーブル設計

テーブル名: `TaskBoard`

| エンティティ | PK | SK |
|---|---|---|
| User | `USER#<user_id>` | `METADATA` |
| Project | `USER#<owner_id>` | `PROJECT#<project_id>` |
| Task | `PROJECT#<project_id>` | `TASK#<due_date>#<task_id>` |

GSI1: `STATUS#<status>` / `<due_date>#<task_id>` — ステータス別タスク検索
GSI2: `ASSIGNEE#<user_id>` / `<due_date>#<task_id>` — 担当者別タスク検索

### モデル層のパターン

モデル(`app/models/`)はaws-recordのマッピングと、`Aws::DynamoDB::Client`を直接使うクエリメソッドを併用するハイブリッド設計。

- `aws-record`: 基本的なsave/find（GetItem相当）
- `Aws::DynamoDB::Client`: Query, begins_with, BETWEEN, GSIクエリなど複雑な操作

各モデルの`save_as_*`メソッドでPK/SKを自動設定してからsaveする。

### ルーティング

- `resources :users` / `resources :projects` (tasksがネスト)
- `GET /tasks/by_status/:status` / `GET /tasks/by_assignee/:user_id` — GSI経由の横断検索
- ルート: `projects#index`

## コード規約

- RuboCop: `rubocop-rails-omakase`プリセットを使用
