#!/bin/bash
set -e

# ==========================================
# build_script installer
# ==========================================
# Installs `build_release` CLI and its dependencies.
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
# Install dependencies
# ------------------------------------------
install_dependencies() {
  local need_ruby=false need_bundler=false need_fastlane=false

  command -v ruby    &>/dev/null || need_ruby=true
  command -v bundle  &>/dev/null || need_bundler=true
  command -v fastlane &>/dev/null || need_fastlane=true

  if [ "$need_ruby" = false ] && [ "$need_bundler" = false ] && [ "$need_fastlane" = false ]; then
    echo "✅ Dependencies: ruby $(ruby -e 'print RUBY_VERSION'), bundler, fastlane — all present."
    return 0
  fi

  echo ""
  echo "📦 Installing missing dependencies..."

  # Prefer brew on macOS
  if command -v brew &>/dev/null; then
    if [ "$need_ruby" = true ]; then
      echo "   Installing Ruby via Homebrew..."
      brew install ruby
    fi

    if [ "$need_fastlane" = true ]; then
      echo "   Installing Fastlane via Homebrew..."
      brew install fastlane
      need_bundler=false  # brew fastlane bundles bundler
    fi

    if [ "$need_bundler" = true ]; then
      echo "   Installing Bundler..."
      gem install bundler
    fi
  else
    # No brew — require it
    echo "❌ Homebrew is required to install dependencies."
    echo "   Install Homebrew first: https://brew.sh"
    echo "   Then re-run this installer."
    exit 1
  fi

  echo "✅ Dependencies installed."
}

# ------------------------------------------
# Install CLI
# ------------------------------------------
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "❌ Script not found: $SCRIPT_PATH"
  echo "   Run this from the build_script repo root."
  exit 1
fi

echo "⚙️  Installing build_release CLI..."
echo ""

install_dependencies

echo ""
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

# Ensure standard credential directories exist
mkdir -p "$HOME/.config/gplay" "$HOME/.config/appstore"

echo "📁 Credential directories ready:"
echo "   - ~/.config/gplay/    (Place Google Play service-account.json here)"
echo "   - ~/.config/appstore/ (Place App Store Connect AuthKey_*.p8 here)"

echo ""
echo "🚀 Ready! Run 'build_release --help' from any Flutter project."
