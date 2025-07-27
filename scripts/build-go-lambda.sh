#!/bin/bash
set -euo pipefail

# ─── COLORS ─────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}ℹ $1${NC}"; }
log_success() { echo -e "${GREEN}✔ $1${NC}"; }
log_error()   { echo -e "${RED}✖ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠ $1${NC}"; }

# ─── GO TO FUNCTION SOURCE ──────────────────────────────
log_info "📦 Building Go Lambda function..."
cd "$(dirname "$0")/../functions/source/soci-index-generator-lambda"

# ─── SET GO PROXY ───────────────────────────────────────
export GOPROXY=direct

# ─── CLEAN OLD ARTIFACTS ────────────────────────────────
log_info "🧹 Cleaning old build files..."
rm -f bootstrap soci_index_generator_lambda.zip

# ─── DOWNLOAD DEPENDENCIES ──────────────────────────────
log_info "🔄 Downloading Go module dependencies..."
if ! go mod download > /dev/null 2>&1; then
  log_error "Failed to download Go module dependencies"
  log_warn  "Please check your internet connection or go.mod"
  exit 1
fi
log_success "Go module dependencies downloaded"

# ─── BUILD LAMBDA ───────────────────────────────────────
log_info "🛠 Building Go Lambda binary with Make..."
if ! make > /dev/null 2>&1; then
  log_error "Failed to build Go Lambda function"
  log_warn  "Check the Makefile output for build errors"
  exit 1
fi

# ─── VERIFY ZIP OUTPUT ──────────────────────────────────
if [ ! -f "soci_index_generator_lambda.zip" ]; then
  log_error "Expected output 'soci_index_generator_lambda.zip' not found"
  exit 1
fi
log_success "Go Lambda function built successfully"
echo "DEBUG: TF_CALLING_REPO_ROOT=$TF_CALLING_REPO_ROOT"
# ─── COPY ZIP TO CALLING REPO PATH ──────────────────────
# Get original working directory from Terraform via PWD env
CALLING_REPO_ROOT="${TF_CALLING_REPO_ROOT:-$PWD}"

log_info "📁 Copying ZIP to: $CALLING_REPO_ROOT"

cp soci_index_generator_lambda.zip "$CALLING_REPO_ROOT/soci_index_generator_lambda.zip"

log_success "Copied to: $CALLING_REPO_ROOT/soci_index_generator_lambda.zip ✅"

log_success "Output: soci_index_generator_lambda.zip ✅"
