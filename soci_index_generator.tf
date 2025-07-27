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
    command = "bash ./scripts/setup-go-lambda-env.sh"
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
    command = <<-EOT
      echo "Building Go Lambda function..."
      cd ${path.module}/functions/source/soci-index-generator-lambda
      
      
      # Set GOPROXY as per Dockerfile
      export GOPROXY=direct
      
      # Clean any previous builds
      rm -f bootstrap soci_index_generator_lambda.zip
      
      # Download Go module dependencies
      echo "Downloading Go module dependencies..."
      if ! go mod download; then
        echo "Error: Failed to download Go module dependencies"
        echo "Please check your internet connection and Go module configuration"
        exit 1
      fi
      
      echo "✓ Go module dependencies downloaded successfully"
      
      # Run make with error handling
      echo "Building Go Lambda binary..."
      if ! make; then
        echo "Error: Failed to build Go Lambda function"
        echo "Please check the build output above for details"
        exit 1
      fi
      
      # Verify the zip file was created
      if [ ! -f "soci_index_generator_lambda.zip" ]; then
        echo "Error: Expected zip file 'soci_index_generator_lambda.zip' was not created"
        exit 1
      fi
      
      echo "✓ Go Lambda function built successfully"
      echo "✓ Created: soci_index_generator_lambda.zip"
    EOT
  }
}
