data "aws_caller_identity" "current" {}

locals {
  resource_prefix = var.resource_prefix != "" ? var.resource_prefix : ""
}

# Build and package Python Lambda function
data "archive_file" "ecr_image_filter_lambda" {
  type        = "zip"
  source_file = "${path.module}/functions/source/ecr-image-action-event-filtering/ecr_image_action_event_filtering_lambda_function.py"
  output_path = "${path.root}/lambda.zip"
}

# Install dependencies for Ubuntu 24.04 before building Go Lambda
resource "null_resource" "install_dependencies" {
  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/setup-go-lambda-env.sh"
  }
}

# Build Lambda function using null_resource
resource "null_resource" "build_go_lambda" {
  depends_on = [null_resource.install_dependencies]

  triggers = {
    # Rebuild when any Go source files change
    go_mod_hash   = filemd5("${path.module}/functions/source/soci-index-generator-lambda/go.mod")
    go_sum_hash   = filemd5("${path.module}/functions/source/soci-index-generator-lambda/go.sum")
    handler_hash  = filemd5("${path.module}/functions/source/soci-index-generator-lambda/handler.go")
    makefile_hash = filemd5("${path.module}/functions/source/soci-index-generator-lambda/Makefile")
    # Include dependency installation to ensure it runs first
    dependency_install = null_resource.install_dependencies.id
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build-go-lambda.sh "
  }
}

# zip and copy the bootstrap to root location


resource "aws_lambda_function" "ecr_image_action_event_filtering" {
  function_name = "${local.resource_prefix}ECRImageActionEventFilterLambda"
  handler       = var.ecr_image_filter_lambda_handler
  runtime       = var.ecr_image_filter_lambda_runtime
  role          = aws_iam_role.ecr_image_action_event_filtering.arn
  timeout       = var.soci_ecr_image_filter_lambda_timeout
  logging_config {
    log_format = "Text"
  }
  filename         = data.archive_file.ecr_image_filter_lambda.output_path
  source_code_hash = data.archive_file.ecr_image_filter_lambda.output_base64sha256
  environment {
    variables = {
      soci_repository_image_tag_filters = join(",", var.soci_repository_image_tag_filters)
      soci_index_generator_lambda_arn   = aws_lambda_function.soci_index_generator.arn
    }
  }

}

resource "aws_lambda_function" "soci_index_generator" {
  function_name = "${local.resource_prefix}IndexGeneratorLambda"
  handler       = var.soci_index_generator_lambda_handler
  runtime       = var.soci_index_generator_lambda_runtime
  role          = aws_iam_role.soci_index_generator.arn
  timeout       = var.soci_ecr_image_filter_lambda_timeout

  filename         = data.archive_file.soci_index_generator_lambda.output_path
  source_code_hash = data.archive_file.soci_index_generator_lambda.output_base64sha256
  ephemeral_storage {
    size = var.soci_index_generator_lambda_ephemeral_storage # 10GB
  }
  memory_size = var.soci_index_generator_lambda_memory_size
  environment {
    variables = {
      soci_index_version = var.soci_index_version
    }
  }

}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecr_image_action_event_filtering" {
  name               = "${local.resource_prefix}ECRImageActionEventFilterLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

}

resource "aws_iam_policy" "ecr_image_action_event_filtering_lambda_invoke" {
  name   = "${local.resource_prefix}ECRImageActionEventFilterLambdaInvokePolicy"
  policy = data.aws_iam_policy_document.ecr_lambda_invoke.json
}

data "aws_iam_policy_document" "ecr_lambda_invoke" {
  statement {
    actions   = ["lambda:InvokeFunction", "lambda:InvokeAsync"]
    resources = [aws_lambda_function.soci_index_generator.arn]
  }
}

resource "aws_iam_role_policy_attachment" "ecr_image_action_event_filtering_lambda_invoke" {
  role       = aws_iam_role.ecr_image_action_event_filtering.name
  policy_arn = aws_iam_policy.ecr_image_action_event_filtering_lambda_invoke.arn
}

resource "aws_cloudwatch_log_group" "ecr_image_action_event_filtering" {
  name              = "/aws/lambda/${aws_lambda_function.ecr_image_action_event_filtering.function_name}"
  retention_in_days = var.soci_ecr_lambda_log_retention_days
}

resource "aws_iam_policy" "ecr_image_action_event_filtering_lambda_cloudwatch" {
  name   = "${local.resource_prefix}ECRImageActionEventFilterLambdaLogPolicy"
  policy = data.aws_iam_policy_document.ecr_image_action_event_filtering_lambda_cloudwatch.json
}

data "aws_iam_policy_document" "ecr_image_action_event_filtering_lambda_cloudwatch" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "${aws_cloudwatch_log_group.ecr_image_action_event_filtering.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "ecr_image_action_event_filtering_lambda_cloudwatch" {
  role       = aws_iam_role.ecr_image_action_event_filtering.name
  policy_arn = aws_iam_policy.ecr_image_action_event_filtering_lambda_cloudwatch.arn
}

# SociIndexGeneratorLambda IAM Role
resource "aws_iam_role" "soci_index_generator" {
  name               = "${local.resource_prefix}IndexGeneratorLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_cloudwatch_log_group" "soci_index_generator" {
  name              = "/aws/lambda/${aws_lambda_function.soci_index_generator.function_name}"
  retention_in_days = var.soci_ecr_lambda_log_retention_days
}

resource "aws_iam_policy" "soci_index_generator_lambda_cloudwatch" {
  name   = "${local.resource_prefix}IndexGeneratorLambdaLogPolicy"
  policy = data.aws_iam_policy_document.soci_index_generator_lambda_cloudwatch.json
}

data "aws_iam_policy_document" "soci_index_generator_lambda_cloudwatch" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "${aws_cloudwatch_log_group.soci_index_generator.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "soci_index_generator_lambda_cloudwatch" {
  role       = aws_iam_role.soci_index_generator.name
  policy_arn = aws_iam_policy.soci_index_generator_lambda_cloudwatch.arn
}

# RepositoryNameParsingLambda IAM Role
resource "aws_iam_role" "repository_name_parsing_lambda" {
  name               = "${local.resource_prefix}RepositoryNameParsingLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "archive_file" "repository_name_parsing_lambda_zip" {
  type        = "zip"
  output_path = "${path.root}/repository_name_parsing_lambda.zip"
  source_file = "${path.module}/index.py"
}

# Lambda Function for Parsing Repository Names
resource "aws_lambda_function" "repository_name_parsing" {
  function_name = "${local.resource_prefix}RepositoryNameParsingLambda"
  handler       = "index.handler"
  runtime       = "python3.9"
  role          = aws_iam_role.repository_name_parsing_lambda.arn

  filename         = data.archive_file.repository_name_parsing_lambda_zip.output_path
  source_code_hash = data.archive_file.repository_name_parsing_lambda_zip.output_base64sha256

  environment {
    variables = {
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    }
  }
}

data "aws_lambda_invocation" "repository_name_parsing" {
  function_name = aws_lambda_function.repository_name_parsing.function_name
  input = jsonencode({
    filters = var.soci_repository_image_tag_filters
  })
}

# ECR Repository Policy for SociIndexGeneratorLambda
resource "aws_iam_policy" "soci_index_generator_ecr_repository" {
  name   = "${local.resource_prefix}IndexGeneratorLambdaECRPolicy"
  policy = data.aws_iam_policy_document.soci_index_generator_ecr_repository.json
}

data "aws_iam_policy_document" "soci_index_generator_ecr_repository" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage"
    ]
    resources = jsondecode(jsondecode(data.aws_lambda_invocation.repository_name_parsing.result)["body"])["repository_arns"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }
}

# Attach ECR Policy to SociIndexGeneratorLambda Role
resource "aws_iam_role_policy_attachment" "soci_index_generator_ecr_repository" {
  role       = aws_iam_role.soci_index_generator.name
  policy_arn = aws_iam_policy.soci_index_generator_ecr_repository.arn
}

# EventBridge Rule to trigger Lambda on ECR image push
resource "aws_cloudwatch_event_rule" "ecr_image_action_event" {
  name        = "${local.resource_prefix}ECRImageActionEventBridgeRule"
  description = "Invokes Amazon ECR image action event filtering Lambda function when image is successfully pushed to ECR."

  event_pattern = jsonencode({
    source        = ["aws.ecr"]
    "detail-type" = ["ECR Image Action"]
    detail = {
      action-type = ["PUSH"]
      result      = ["SUCCESS"]
    }
    region = [var.aws_region]
  })

  state = "ENABLED"
}

# Target for the EventBridge Rule
resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.ecr_image_action_event.name
  target_id = "ecr-image-action-lambda-target"
  arn       = aws_lambda_function.ecr_image_action_event_filtering.arn
}

# Permission for EventBridge to invoke the Lambda function
resource "aws_lambda_permission" "allow_event_bridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecr_image_action_event_filtering.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_image_action_event.arn
}
