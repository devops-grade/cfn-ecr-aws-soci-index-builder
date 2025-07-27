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
    command = <<-EOT
      echo "Installing dependencies for Ubuntu 24.04..."
      
      # Update package list
      echo "Updating package list..."
      sudo apt-get update -y
      
      # Install system dependencies as per Dockerfile
      echo "Installing system dependencies..."
      sudo apt-get install -y python3-pip make git zip gcc g++ zlib1g zlib1g-dev curl wget
      
      # Check if Go is installed and version is sufficient
      GO_INSTALLED=false
      if command -v go &> /dev/null; then
        GO_VERSION=$(go version | grep -o 'go[0-9]\+\.[0-9]\+' | sed 's/go//')
        REQUIRED_VERSION="1.23"
        if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
          GO_INSTALLED=true
          echo "✓ Go version: $(go version)"
        else
          echo "Go version $GO_VERSION is insufficient (required: $REQUIRED_VERSION+)"
        fi
      else
        echo "Go is not installed"
      fi
      
      # Install Go 1.24 if not present or insufficient version
      if [ "$GO_INSTALLED" = false ]; then
        echo "Installing Go 1.24..."
        
        # Download and install Go 1.24
        cd /tmp
        wget -q "https://golang.org/dl/go1.24.0.linux-amd64.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go1.24.0.linux-amd64.tar.gz"
        
        # Add Go to PATH
        if ! grep -q "/usr/local/go/bin" /etc/environment; then
          echo 'PATH="/usr/local/go/bin:$PATH"' | sudo tee -a /etc/environment
        fi
        
        # Add to current session
        export PATH="/usr/local/go/bin:$PATH"
        
        # Add to user's profile
        if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
          echo 'export PATH="/usr/local/go/bin:$PATH"' >> ~/.bashrc
        fi
        
        # Clean up
        rm -f "go1.24.0.linux-amd64.tar.gz"
        
        echo "✓ Go 1.24 installed successfully"
      fi
      
      # Final verification
      echo "Verifying all dependencies..."
      
      # Ensure Go is in PATH for this session
      export PATH="/usr/local/go/bin:$PATH"
      
      if ! command -v go &> /dev/null; then
        echo "Error: Go installation failed or not in PATH"
        exit 1
      fi
      
      if ! command -v make &> /dev/null; then
        echo "Error: make installation failed"
        exit 1
      fi
      
      echo "✓ Go version: $(go version)"
      echo "✓ Make version: $(make --version | head -n1)"
      echo "✓ GCC version: $(gcc --version | head -n1)"
      echo "✓ Git version: $(git --version)"
      echo "✓ All dependencies are installed and ready"
    EOT
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
    command = <<-EOT
      echo "Building Go Lambda function..."
      cd ${path.module}/functions/source/soci-index-generator-lambda
      
      # Ensure Go is in PATH
      export PATH="/usr/local/go/bin:$PATH"
      
      # Set GOPROXY as per Dockerfile
      export GOPROXY=direct
      
      # Clean any previous builds
      rm -f bootstrap soci_index_generator_lambda.zip
      
      # Download Go module dependencies (as per Dockerfile)
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

# Upload Go Lambda zip to S3
resource "aws_s3_object" "soci_index_generator_lambda" {
  depends_on = [null_resource.build_go_lambda]

  bucket = aws_s3_bucket.lambda_deployment_assets.bucket
  key    = "cfn-ecr-aws-soci-index-builder/functions/packages/soci-index-generator-lambda/soci_index_generator_lambda.zip"
  source = "${path.module}/functions/source/soci-index-generator-lambda/soci_index_generator_lambda.zip"
  etag   = filemd5("${path.module}/functions/source/soci-index-generator-lambda/soci_index_generator_lambda.zip")
}
