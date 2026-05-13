output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.bedrock_lambda.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.bedrock_lambda.arn
}

output "invoke_command" {
  description = "AWS CLI command to invoke the Lambda for testing"
  value       = <<-EOT
    aws lambda invoke \
      --region ${var.aws_region} \
      --function-name ${aws_lambda_function.bedrock_lambda.function_name} \
      --payload '{"userId":"user-123","prompt":"Hello!"}' \
      --cli-binary-format raw-in-base64-out \
      response.json && cat response.json
  EOT
}
