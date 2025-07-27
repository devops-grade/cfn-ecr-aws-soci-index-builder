variable "resource_prefix" {
  type        = string
  description = "Prefix for AWS resources (Lambda functions, IAM roles, etc.) created by the SOCI implementation. Used to ensure unique resource names and identify SOCI-related resources. Default is `ecr-soci-indexer`."
  default     = "Soci"
}

locals {
  resource_prefix = var.resource_prefix != "" ? var.resource_prefix : ""
}


# Install dependencies for Ubuntu 24.04 before building Go Lambda
resource "null_resource" "install_dependencies" {
  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/setup-go-lambda-env.sh"
  }
}
# Build Go Lambda function using null_resource
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
