#!/bin/bash

set -euo pipefail

# Colors for logs
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}▶ $1${NC}"
}

log "Installing build tools..."
sudo apt-get update -y > /dev/null
sudo apt-get install -y --no-install-recommends \
  make \
  git \
  gcc \
  g++ \
  zip \
  zlib1g \
  zlib1g-dev \
  python3-pip

# Desired Go version
REQUIRED_GO_VERSION="1.24.4"
GO_DOWNLOAD_URL="https://go.dev/dl/go${REQUIRED_GO_VERSION}.linux-amd64.tar.gz"
GO_INSTALL_DIR="/usr/local"

# Version comparison function
version_ge() {
  [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

INSTALL_GO=false

# Check if Go is installed and version is sufficient
if command -v go &>/dev/null; then
  INSTALLED_GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
  log "Go is installed: version $INSTALLED_GO_VERSION"
  if ! version_ge "$INSTALLED_GO_VERSION" "$REQUIRED_GO_VERSION"; then
    log "Go version is outdated. Will install $REQUIRED_GO_VERSION"
    INSTALL_GO=true
  fi
else
  log "Go is not installed. Will install $REQUIRED_GO_VERSION"
  INSTALL_GO=true
fi

# Install or upgrade Go
if [ "$INSTALL_GO" = true ]; then
  curl -fsSL "$GO_DOWNLOAD_URL" -o go${REQUIRED_GO_VERSION}.linux-amd64.tar.gz
  sudo rm -rf "$GO_INSTALL_DIR/go"
  sudo tar -C "$GO_INSTALL_DIR" -xzf go${REQUIRED_GO_VERSION}.linux-amd64.tar.gz
  rm go${REQUIRED_GO_VERSION}.linux-amd64.tar.gz
  log "Go $REQUIRED_GO_VERSION installed to $GO_INSTALL_DIR/go"
fi

# Set environment variables for this shell session (important for local-exec and GitHub Actions)
export PATH=$PATH:/usr/local/go/bin

# Verify
log "Final Go version: $(go version)"
