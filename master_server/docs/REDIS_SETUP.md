# Redis State Management Setup Guide

## 概要

Whisper Orchard Master ServerでRedisを使用してWorker Nodeのステータスとジョブの状態を管理します。

## インストール

### 1. Redisのインストール

**Windows (WSL推奨):**
```powershell
# WSL内でRedisをインストール
wsl
sudo apt update
sudo apt install redis-server
sudo service redis-server start
```

**または Docker:**
```powershell
docker run -d -p 6379:6379 redis:latest
```

### 2. Pythonパッケージのインストール

```powershell
cd master_server
pip install -r requirements.txt
```

## 機能

### 1. Worker Node管理

- **ステータス追跡**: online/offline/busy
- **自動タイムアウト**: 5分間更新がないWorkerは自動削除
- **ヘルスチェック**: `/workers` API呼び出し時に自動更新

### 2. ジョブ管理

- **ジョブライフサイクル**: created → purifying → splitting → processing → aggregating → completed/failed
- **チャンク追跡**: 各チャンクの処理状況をリアルタイム追跡
- **自動クリーンアップ**: 1時間後に自動削除

### 3. 統計情報

- Worker数（total/online/busy/offline）
- ジョブ数（total/active/completed）

## API エンドポイント

### ジョブ管理

**全ジョブ取得:**
```bash
GET /jobs
```

**特定ジョブ取得:**
```bash
GET /jobs/<job_id>
```

**統計情報:**
```bash
GET /stats
```

### レスポンス例

**ジョブステータス:**
```json
{
  "job_id": "abc123-456-789",
  "filename": "lecture.mp3",
  "status": "processing",
  "total_chunks": 5,
  "completed_chunks": 3,
  "created_at": "2025-11-20T10:30:00",
  "chunks": [
    {
      "chunk_id": "abc123_chunk_0",
      "worker_url": "http://172.22.1.222:8080",
      "status": "completed",
      "started_at": "2025-11-20T10:30:05",
      "completed_at": "2025-11-20T10:30:15"
    }
  ]
}
```

**統計情報:**
```json
{
  "workers": {
    "total": 3,
    "online": 2,
    "busy": 1,
    "offline": 0
  },
  "jobs": {
    "total": 10,
    "active": 2,
    "completed": 8
  }
}
```

## フォールバック動作

Redisが利用できない場合、自動的にメモリ内ストレージにフォールバックします。

```python
# Redis接続失敗時のログ
[Redis] Connection failed: ...
[Redis] Fallback to in-memory mode
```

**制限事項（フォールバックモード）:**
- サーバー再起動で全データ消失
- マルチプロセス対応なし

## Redis CLI での確認

```bash
# Redisに接続
redis-cli

# 全Worker確認
KEYS worker:*

# 全Job確認
KEYS job:*

# 特定Workerの詳細
GET worker:http://172.22.1.222:8080

# 特定Jobの詳細
GET job:abc123-456-789
```

## トラブルシューティング

### Redisに接続できない

```powershell
# Redisサービス確認（WSL）
wsl sudo service redis-server status

# Redisサービス起動
wsl sudo service redis-server start

# ポート確認
netstat -an | findstr 6379
```

### ジョブが残り続ける

```bash
# 古いジョブを手動削除
redis-cli
KEYS job:*
DEL job:<job_id>

# 全ジョブ削除（注意！）
FLUSHDB
```

## パフォーマンス

- Worker更新: ~1ms
- ジョブ作成: ~2ms
- ジョブ状態更新: ~1ms
- TTL（自動削除）による自動クリーンアップ

## セキュリティ

本番環境では以下の対策を推奨:

1. Redisに認証を設定
2. ファイアウォールでポート6379を保護
3. TLS/SSL接続の使用

```python
# 認証付き接続
redis_manager = RedisManager(
    host='localhost',
    port=6379,
    password='your_password'
)
```
