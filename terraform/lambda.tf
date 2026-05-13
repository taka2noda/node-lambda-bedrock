# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "node-lambda-bedrock-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "bedrock_policy" {
  name = "bedrock-invoke-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = [
        "arn:aws:bedrock:*::foundation-model/anthropic.*",
        "arn:aws:bedrock:*:*:inference-profile/us.anthropic.*",
      ]
    }]
  })
}

# Build Lambda deployment package
resource "null_resource" "npm_install" {
  triggers = {
    package_json = filemd5("${path.module}/../src/package.json")
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/../src && npm install --production"
  }
}

data "archive_file" "lambda_zip" {
  depends_on  = [null_resource.npm_install]
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/../lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "bedrock_lambda" {
  function_name    = "node-lambda-bedrock-${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  architectures    = ["x86_64"]
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  memory_size      = 256

  # Extensionレイヤーのみ使用（dd-trace / datadog-lambda-js はパッケージにバンドル）
  layers = [
    "arn:aws:lambda:${var.aws_region}:464622532012:layer:Datadog-Extension:${var.dd_extension_layer_version}",
  ]

  environment {
    variables = {
      # Datadog configuration
      DD_TRACE_ENABLED  = "true"
      DD_API_KEY        = var.dd_api_key
      DD_SITE           = var.dd_site
      DD_ENV            = var.environment
      DD_SERVICE        = "node-lambda-bedrock"
      DD_VERSION        = "1.0.0"

      # Application configuration
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/node-lambda-bedrock-${var.environment}"
  retention_in_days = 14
}
