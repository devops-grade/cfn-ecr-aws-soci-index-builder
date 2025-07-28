variable "aws_region" {
  description = "AWS region information"
  type        = string
}

variable "soci_repository_image_tag_filters" {
  type        = list(string)
  default     = ["*:*"]
  description = <<-EOT
  List of repository:tag filter patterns for SOCI index generation.
  These filters determine which ECR images will have SOCI indexes generated when pushed.
  Format: ["repository:tag", ...] where both repository and tag support wildcards (*).
  Examples:
  - ["*:*"] - Generate SOCI index for all images in all repositories (default)
  - ["app-repo:prod-*"] - Only for images in 'app-repo' with tags starting with 'prod-'
  - ["frontend:latest", "backend:v*"] - For specific repository/tag combinations
  EOT
}

# Note: deployment_assets_bucket, deployment_assets_key_prefix, and ecr_image_filter_lambda_asset_path
# variables have been removed as the S3 bucket is now created automatically by Terraform
variable "ecr_image_filter_lambda_handler" {
  type        = string
  default     = "ecr_image_action_event_filtering_lambda_function.lambda_handler"
  description = "Name of the handler function in the ECR image filter Lambda. Default is `ecr_image_action_event_filtering_lambda_function.lambda_handler`. Required if not using the `copy-lambda-code` module."
}
variable "ecr_image_filter_lambda_runtime" {
  type        = string
  default     = "python3.10"
  description = "Runtime of the ECR image filter Lambda. Default is `python3.9`. Required if not using the `copy-lambda-code` module."
}
# Note: soci_index_generator_lambda_asset_path variable has been removed as the Lambda zip
# is now built and uploaded automatically by Terraform
variable "soci_index_generator_lambda_handler" {
  type        = string
  default     = "main"
  description = "Name of the handler function in the SOCI index generator Lambda. Default is `soci_index_generator_lambda_function.lambda_handler`. Required if not using the `copy-lambda-code` module."
}
variable "soci_index_generator_lambda_runtime" {
  type        = string
  default     = "provided.al2"
  description = "Runtime of the SOCI index generator Lambda. Default is `provided.al2`. Required if not using the `copy-lambda-code` module."
}
variable "resource_prefix" {
  type        = string
  description = "Prefix for AWS resources (Lambda functions, IAM roles, etc.) created by the SOCI implementation. Used to ensure unique resource names and identify SOCI-related resources. Default is `ecr-soci-indexer`."
  default     = "Soci"
}

variable "soci_ecr_lambda_log_retention_days" {
  type        = number
  description = "Number of days to retain logs for the Soci ECR image action event filtering Lambda function in CloudWatch Logs."
  default     = 14
}

variable "soci_ecr_image_filter_lambda_timeout" {
  type        = number
  description = "Timeout (in seconds) for the ECR Image Action Event Filtering Lambda function. Maximum allowed by AWS is 900 seconds."
  default     = 900
}

variable "soci_index_generator_lambda_ephemeral_storage" {
  type        = number
  description = "Ephemeral storage size (in MB) for the SOCI Index Generator Lambda function. Must be between 512 and 10240 (10 GB max)."
  default     = 10240
}

variable "soci_index_generator_lambda_memory_size" {
  type        = number
  description = "Amount of memory (in MB) allocated to the SOCI Index Generator Lambda function. Must be between 128 and 10240."
  default     = 1024
}

variable "soci_index_version" {
  type        = string
  description = "The version of SOCI index to generate V1, V2"
  default     = "V2"
}
