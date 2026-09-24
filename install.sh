#!/bin/bash
set -e

# ==========================================
# build_script installer
# ==========================================
# Symlinks `build_release` into ~/.local/bin so it's available globally.
#
# Usage:
#   ./install.sh              Install
#   ./install.sh --uninstall  Remove

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$REPO_DIR/scripts/build_release.sh"
BIN_DIR="$HOME/.local/bin"
LINK_NAME="build_release"
LINK_PATH="$BIN_DIR/$LINK_NAME"

# ------------------------------------------
# Uninstall
# ------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  if [ -L "$LINK_PATH" ]; then
    rm "$LINK_PATH"
    echo "✅ Removed $LINK_PATH"
  else
    echo "ℹ️  Nothing to remove — $LINK_PATH does not exist."
  fi
  exit 0
fi

# ------------------------------------------
# Install
# ------------------------------------------
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "❌ Script not found: $SCRIPT_PATH"
  echo "   Run this from the build_script repo root."
  exit 1
fi

chmod +x "$SCRIPT_PATH"
mkdir -p "$BIN_DIR"
ln -sf "$SCRIPT_PATH" "$LINK_PATH"

echo "✅ Installed: $LINK_PATH → $SCRIPT_PATH"

# Check PATH
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo ""
    echo "⚠️  $BIN_DIR is not in your PATH."
    echo "   Add this to your ~/.zshrc (or ~/.bashrc):"
    echo ""
    echo "     export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "   Then restart your terminal or run: source ~/.zshrc"
    exit 0
    ;;
esac

echo ""
echo "🚀 Ready! Run 'build_release --help' from any Flutter project."
