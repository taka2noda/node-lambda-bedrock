# node-lambda-bedrock

Node.js Lambda + Amazon Bedrock + Datadog APM の検証用スタック。

## 構成

```
.
├── datadog/
│   └── dashboard_bedrock_by_user.json  # Datadog ダッシュボード定義（エクスポート）
├── src/
│   ├── index.js          # Lambda ハンドラー（Bedrock呼び出し + Datadog Custom Instrumentation）
│   └── package.json      # Node.js 依存パッケージ
└── terraform/
    ├── main.tf           # プロバイダー設定
    ├── variables.tf      # 入力変数定義
    ├── lambda.tf         # Lambda / IAM / CloudWatch
    ├── outputs.tf        # 出力値
    └── terraform.tfvars.example  # 変数設定サンプル
```

### アーキテクチャ

```
呼び出し元
    │
    ▼
AWS Lambda (Node.js 20.x / us-west-2)
    │  ┌──────────────────────────────────────────────────┐
    │  │ デプロイパッケージ (node_modules にバンドル)      │
    │  │   - datadog-lambda-js  (ハンドラーラッパー)      │
    │  │   - dd-trace           (APM / Custom Instrumentation) │
    │  ├──────────────────────────────────────────────────┤
    │  │ Lambda Layer                                     │
    │  │   - Datadog-Extension  (メトリクス・ログ転送)    │
    │  └──────────────────────────────────────────────────┘
    │
    ├─→ Amazon Bedrock Inference Profile
    │     (us.anthropic.claude-haiku-4-5-20251001-v1:0)
    └─→ Datadog APM (usr.id タグ付きトレース)
```

### Datadog 監視構成

| コンポーネント | 方式 | 役割 |
|----------------|------|------|
| `datadog-lambda-js` | パッケージバンドル | ハンドラーラッパー・APM初期化 |
| `dd-trace` | パッケージバンドル | APMトレース・カスタム計装 |
| `Datadog-Extension` | Lambda Layer | メトリクス・ログ・トレースをDatadogへ転送 |

## Datadog 設定箇所

### 1. 依存パッケージ — `src/package.json`

```json
"dependencies": {
  "datadog-lambda-js": "^11.0.0",  // ハンドラーラッパー
  "dd-trace": "^5.0.0"             // APMトレース・カスタム計装
}
```

`dd-trace` と `datadog-lambda-js` はLambda Layerではなくデプロイパッケージにバンドルする。
---

### 2. ハンドラーラッパーとカスタム計装 — `src/index.js`

```js
// ① dd-trace を最初に初期化（他の require より前に行うこと）
const tracer = require('dd-trace').init();   // ← 必ず先頭で .init() する

// ② パッケージのインポート
const { datadog } = require('datadog-lambda-js');

// ③ APM Server-Side Custom Instrumentation
//    イベントから取得した userId を usr.id タグとしてスパンに付与
const span = tracer.scope().active();
if (span) {
  span.setTag('usr.id', userId);
}

// ④ ハンドラーをDatadogラッパーでエクスポート
module.exports.handler = datadog(myHandler);
```

> **重要**: `require('dd-trace').init()` は自動計装したいモジュール（`@aws-sdk` 等）より前に実行すること。
> dd-trace 公式ドキュメントでは **"The Node.js SDK needs to be imported and initialized before any other module"** と明記されている。

---

### 3. Terraform 変数定義 — `terraform/variables.tf`

| 変数 | 行 | 内容 |
|------|----|------|
| `dd_api_key` | 13–17 | DatadogのAPIキー（`sensitive = true`） |
| `dd_site` | 19–23 | Datadogサイト。デフォルト `datadoghq.com` |
| `dd_extension_layer_version` | 31–35 | Datadog Extension Layerのバージョン |

---

### 4. Lambda Layer と環境変数 — `terraform/lambda.tf`

**Layer（67–70行目）**

```hcl
layers = [
  "arn:aws:lambda:${var.aws_region}:464622532012:layer:Datadog-Extension:${var.dd_extension_layer_version}",
]
```

Extensionレイヤーのみを付与。`dd-trace` / `datadog-lambda-js` はパッケージバンドルのため、`Datadog-Node20-x` レイヤーは不要。

**ハンドラー設定**

```hcl
handler = "index.handler"
```

プログラム的ラッパー方式（`datadog()` 関数でハンドラーをラップ）を使用するため、`handler` は `index.handler` のままにする。
`DD_LAMBDA_HANDLER` 環境変数は不要。

**環境変数（74–80行目）**

```hcl
DD_TRACE_ENABLED = "true"               # APMトレースの有効化
DD_API_KEY       = var.dd_api_key       # terraform.tfvars で設定
DD_SITE          = var.dd_site          # terraform.tfvars で設定
DD_ENV           = var.environment      # Unified Service Tagging
DD_SERVICE       = "node-lambda-bedrock" # Unified Service Tagging
DD_VERSION       = "1.0.0"             # Unified Service Tagging
```

---

### 5. 秘匿情報の設定 — `terraform/terraform.tfvars`（gitignore対象）

```hcl
dd_api_key = "<YOUR_DATADOG_API_KEY>"
dd_site    = "datadoghq.com"
```


### 6. Datadog ダッシュボード

`datadog/dashboard_bedrock_by_user.json` に `usr.id` スパン属性を元にした Bedrock 呼び出し分析ダッシュボードのエクスポートを格納している。

| ウィジェット | 内容 |
|---|---|
| Toplist | ユーザー別呼び出し回数ランキング |
| Query Value（総数） | 全体の呼び出し総数（トレンド背景付き） |
| Query Value（ユーザー数） | アクティブユーザー数（`usr.id` カーディナリティ） |
| Timeseries | ユーザー別・時系列の呼び出し回数（棒グラフ） |
| Query Table | ユーザー別の呼び出し回数 + 平均レイテンシ (ms) |

このJSONを `upsert_datadog_dashboard`（Datadog MCP / API）に渡すことで別環境へのインポートや再デプロイが可能。


## Bedrock モデル

新しい Claude 4 系モデルは On-Demand での直接呼び出しが非対応のため、**Inference Profile** 経由で呼び出す。

```
# 直接呼び出し（不可）
anthropic.claude-haiku-4-5-20251001-v1:0

# Inference Profile 経由（正しい方法）
us.anthropic.claude-haiku-4-5-20251001-v1:0
```

利用可能な Inference Profile の一覧：

```bash
aws bedrock list-inference-profiles --region us-west-2 \
  --query 'inferenceProfileSummaries[?contains(inferenceProfileId, `anthropic`)].{id:inferenceProfileId,status:status}' \
  --output table
```

## 前提条件

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Node.js](https://nodejs.org/) >= 20
- AWS CLI（認証済み）
- Datadog アカウント・API キー

## デプロイ手順

### 1. 変数ファイルを作成

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`terraform/terraform.tfvars` を編集：

```hcl
aws_region  = "us-west-2"
environment = "dev"
dd_api_key  = "<YOUR_DATADOG_API_KEY>"
dd_site     = "datadoghq.com"  # US1: datadoghq.com / US3: us3.datadoghq.com
```

### 2. Datadog Extension レイヤーの最新バージョンを確認

Extension のバージョンは定期的に更新される。古いバージョンは `datadog-lambda-js` との互換性問題（メトリクス形式の不一致）を引き起こし、APMトレースが届かなくなる原因となる。デプロイ前に以下で最新バージョンを確認すること。

確認後、`terraform.tfvars` に明示的に指定：

```hcl
dd_extension_layer_version = 96  # 上記で確認した最新版に変更すること
```

### 3. Terraform を実行

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## 動作確認

デプロイ後に invoke：

```bash
aws lambda invoke \
  --region us-west-2 \
  --function-name node-lambda-bedrock-dev \
  --payload '{"userId":"user-123","prompt":"Hello!"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

レスポンス例：

```json
{
  "statusCode": 200,
  "body": "{\"userId\":\"user-123\",\"message\":\"Hello! How can I help you today?\"}"
}
```

Datadog APM（https://app.datadoghq.com/apm/traces）で `service:node-lambda-bedrock` を検索すると、`usr.id: user-123` タグ付きのトレースが確認できる。

確認できるスパン：
- `aws.lambda`（ルートスパン、`usr.id` タグ付き）
- `http.request`（Bedrock API 呼び出し）
- `aws.lambda.cold_start`（コールドスタート時）

## 削除

```bash
cd terraform
terraform destroy
```

## 参考ドキュメント

- [Datadog Lambda Instrumentation (Node.js / Terraform)](https://docs.datadoghq.com/serverless/aws_lambda/instrumentation/nodejs/?tab=terraform)
- [APM Server-Side Custom Instrumentation (Node.js)](https://docs.datadoghq.com/tracing/trace_collection/custom_instrumentation/server-side/?api_type=dd_api&prog_lang=node_js)
- [Amazon Bedrock Cross-Region Inference](https://docs.aws.amazon.com/bedrock/latest/userguide/cross-region-inference.html)
