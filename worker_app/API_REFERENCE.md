# Whisper Worker App API リファレンス

## 概要

Whisper Worker App は音声認識エンジン Whisper を HTTP サーバーとして公開し、音声ファイルをアップロードして文字起こし結果を取得できる REST API を提供します。

**Base URL**: `http://<デバイスIP>:8080`

---

## エンドポイント

### `POST /transcribe`

音声ファイルを送信し、文字起こし結果をセグメント単位のタイムスタンプ付きで取得します。

#### リクエスト

- **Content-Type**: `audio/wav` (または音声データの MIME タイプ)
- **Body**: 音声ファイルのバイナリデータ

#### クエリパラメータ

| パラメータ名            | 型      | 必須 | デフォルト | 説明                                                                 |
|------------------------|---------|------|-----------|----------------------------------------------------------------------|
| `include_formatted_log` | boolean | いいえ | `false`   | `true` の場合、CLI スタイルのタイムスタンプ付きログを `formatted_log` フィールドに含める |

#### レスポンス

**Status Code**: `200 OK`

**Content-Type**: `application/json; charset=utf-8`

**Body**:

```json
{
  "text": "全文の文字起こし結果",
  "time_ms": 13423,
  "metadata": {
    "model": "base",
    "language": "ja",
    "request_id": "1735012345678-1234",
    "server_time": "2024-12-24T03:45:45.678Z",
    "segments_count": 5
  },
  "segments": [
    {
      "start": "00:00:00.000",
      "end": "00:00:04.000",
      "start_ms": 0,
      "end_ms": 4000,
      "text": "最初のセグメントのテキスト"
    },
    {
      "start": "00:00:04.000",
      "end": "00:00:12.000",
      "start_ms": 4000,
      "end_ms": 12000,
      "text": "次のセグメントのテキスト"
    }
  ],
  "formatted_log": "[00:00:00.000 --> 00:00:04.000]  最初のセグメントのテキスト\n[00:00:04.000 --> 00:00:12.000]  次のセグメントのテキスト\n"
}
```

> **注意**: `formatted_log` は `?include_formatted_log=true` を指定した場合のみ含まれます。

---

## フィールド仕様

### トップレベルフィールド

| フィールド名      | 型     | 説明                                                                 |
|------------------|--------|----------------------------------------------------------------------|
| `text`           | string | 音声全体の文字起こし結果                                              |
| `time_ms`        | number | 処理時間（ミリ秒単位）                                               |
| `metadata`       | object | メタデータオブジェクト（詳細は下記）                                 |
| `segments`       | array  | セグメント配列（詳細は下記）                                         |
| `formatted_log`  | string | (オプション) CLI スタイルのタイムスタンプ付きログ                    |

### `metadata` オブジェクト

| フィールド名      | 型     | 説明                                                                 |
|------------------|--------|----------------------------------------------------------------------|
| `model`          | string | 使用された Whisper モデル名 (例: `base`, `small`, `large-v2`)        |
| `language`       | string | 認識言語コード (現在は `ja` 固定)                                    |
| `request_id`     | string | リクエスト固有ID（タイムスタンプ + ハッシュ形式）                    |
| `server_time`    | string | サーバー処理時刻 (UTC、ISO8601 形式)                                |
| `segments_count` | number | セグメント数                                                         |

### `segments` 配列要素

| フィールド名 | 型     | 説明                                                                 |
|-------------|--------|----------------------------------------------------------------------|
| `start`     | string | セグメント開始時刻（HH:MM:SS.mmm 形式）                              |
| `end`       | string | セグメント終了時刻（HH:MM:SS.mmm 形式）                              |
| `start_ms`  | number | セグメント開始時刻（ミリ秒単位、数値）                               |
| `end_ms`    | number | セグメント終了時刻（ミリ秒単位、数値）                               |
| `text`      | string | セグメントのテキスト                                                 |

---

## 使用例

### 基本的な文字起こし（formatted_log なし）

```bash
curl -X POST http://172.22.1.222:8080/transcribe \
  -H "Content-Type: audio/wav" \
  --data-binary @test_audio.wav
```

**レスポンス例**:

```json
{
  "text": "こんにちは、これはテストです。",
  "time_ms": 8543,
  "metadata": {
    "model": "base",
    "language": "ja",
    "request_id": "1735012345678-5678",
    "server_time": "2024-12-24T10:30:45.678Z",
    "segments_count": 2
  },
  "segments": [
    {
      "start": "00:00:00.000",
      "end": "00:00:02.500",
      "start_ms": 0,
      "end_ms": 2500,
      "text": "こんにちは"
    },
    {
      "start": "00:00:02.500",
      "end": "00:00:05.000",
      "start_ms": 2500,
      "end_ms": 5000,
      "text": "これはテストです。"
    }
  ]
}
```

### formatted_log 付き文字起こし

```bash
curl -X POST "http://172.22.1.222:8080/transcribe?include_formatted_log=true" \
  -H "Content-Type: audio/wav" \
  --data-binary @test_audio.wav
```

**レスポンス例**:

```json
{
  "text": "こんにちは、これはテストです。",
  "time_ms": 8543,
  "metadata": {
    "model": "base",
    "language": "ja",
    "request_id": "1735012345678-5678",
    "server_time": "2024-12-24T10:30:45.678Z",
    "segments_count": 2
  },
  "segments": [
    {
      "start": "00:00:00.000",
      "end": "00:00:02.500",
      "start_ms": 0,
      "end_ms": 2500,
      "text": "こんにちは"
    },
    {
      "start": "00:00:02.500",
      "end": "00:00:05.000",
      "start_ms": 2500,
      "end_ms": 5000,
      "text": "これはテストです。"
    }
  ],
  "formatted_log": "[00:00:00.000 --> 00:00:02.500]  こんにちは\n[00:00:02.500 --> 00:00:05.000]  これはテストです。\n"
}
```

---

## エラーレスポンス

### `500 Internal Server Error`

処理中にエラーが発生した場合に返されます。

**Body**:

```
Error: <エラーメッセージ>
```

---

## モデル管理

利用可能なモデルは以下の通りです：

- `tiny`: 最軽量・最速（精度は低め）
- `base`: 標準モデル（バランス型）
- `small`: 中程度のモデル（精度向上）
- `large-v2`: 最高精度（処理時間長め）

モデルの切り替えは GUI から実施可能で、API エンドポイントには影響しません。レスポンスの `metadata.model` で使用されたモデルを確認できます。

---

## 補足

- **対応音声形式**: WAV が推奨されますが、Whisper がサポートする他の形式（MP3, M4A など）も処理可能です。
- **推奨サンプリングレート**: 16kHz（モデルの内部処理に最適）
- **最大ファイルサイズ**: 制限なし（ただしメモリに依存）
- **並列処理**: 現在は単一リクエストのみ対応（複数同時リクエストはキューイングされません）

---

## バージョン情報

- **API バージョン**: 1.1.0
- **whisper_ggml パッケージ**: 1.7.0
- **言語**: Dart/Flutter
- **サーバーフレームワーク**: shelf
