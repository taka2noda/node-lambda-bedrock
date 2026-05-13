variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "dd_api_key" {
  description = "Datadog API key"
  type        = string
  sensitive   = true
}

variable "dd_site" {
  description = "Datadog site (e.g. datadoghq.com, us3.datadoghq.com, datadoghq.eu)"
  type        = string
  default     = "datadoghq.com"
}

variable "dd_node_layer_version" {
  description = "Datadog Node20 Lambda layer version (check https://github.com/DataDog/datadog-lambda-js/releases)"
  type        = number
  default     = 116
}

variable "dd_extension_layer_version" {
  description = "Datadog Lambda Extension layer version (check https://github.com/DataDog/datadog-lambda-extension/releases)"
  type        = number
  default     = 96
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}
