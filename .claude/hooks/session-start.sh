#!/bin/bash
set -euo pipefail

# Only run in remote (cloud) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

CRYSTAL_VERSION="1.19.1"

# Install Crystal compiler if not already present
if ! command -v crystal &> /dev/null; then
  # Install system dependencies required by Crystal
  apt-get update
  apt-get install -y libgmp-dev libxml2-dev libevent-dev libgc-dev

  # Download and install Crystal from GitHub releases
  curl -fsSL "https://github.com/crystal-lang/crystal/releases/download/${CRYSTAL_VERSION}/crystal-${CRYSTAL_VERSION}-1-linux-x86_64-bundled.tar.gz" -o /tmp/crystal.tar.gz
  mkdir -p /usr/local/crystal
  tar -xzf /tmp/crystal.tar.gz -C /usr/local/crystal --strip-components=2
  ln -sf /usr/local/crystal/bin/crystal /usr/local/bin/crystal
  ln -sf /usr/local/crystal/bin/shards /usr/local/bin/shards
  rm /tmp/crystal.tar.gz
fi

# Start Redis server if not already running
if ! redis-cli ping &> /dev/null 2>&1; then
  redis-server --daemonize yes
fi

# Install Crystal shard dependencies
cd "$CLAUDE_PROJECT_DIR"
shards install
