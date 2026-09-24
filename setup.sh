#!/bin/bash
set -e

# ==========================================
# Remote installer — curl one-liner entry point
# ==========================================
# curl -fsSL https://raw.githubusercontent.com/huyxoann/flutter-build-script/main/setup.sh | bash

INSTALL_DIR="$HOME/.build_script"
REPO_URL="https://github.com/huyxoann/flutter-build-script.git"

echo "⚙️  Flutter Build Script — Remote Setup"
echo ""

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "📥 Updating existing installation..."
  git -C "$INSTALL_DIR" pull --quiet
else
  echo "📥 Cloning to $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

echo ""
exec "$INSTALL_DIR/install.sh"
