以下の要件で、TerraformでAWSのスタックを作成し、Datadogの監視設定を入れてください。
APMに対してServer-Side Custom Instrumentationで、ユーザーIDをattribute tagとして抽出してください。

Lambda
NodeJS
BedrockでLLM Call
Terraform

Lambdaに対してDatadogの監視実装
https://docs.datadoghq.com/serverless/aws_lambda/instrumentation/nodejs/?tab=terraform

APM：Server-Side Custom Instrumentationで、ユーザーIDをattribute tagとして抽出
https://docs.datadoghq.com/tracing/trace_collection/custom_instrumentation/server-side/?api_type=dd_api&prog_lang=node_js