#!/bin/sh
set -eu
REPO="ciscoriordan/storescreens-cli"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
URL="https://github.com/$REPO/releases/download/$TAG/storescreens-$TAG-macos.tar.gz"
install_temp=$(mktemp -d)
trap 'rm -rf "$install_temp"' EXIT
curl -fsSL "$URL" | tar xz -C "$install_temp"
mkdir -p "$INSTALL_DIR"
install -m 755 "$install_temp/storescreens" "$INSTALL_DIR/storescreens"
install -m 755 "$install_temp/storescreens-mcp" "$INSTALL_DIR/storescreens-mcp"
for install_bundle in "$install_temp/"*.bundle; do
  if [ -d "$install_bundle" ]; then cp -R "$install_bundle" "$INSTALL_DIR/"; fi
done
"$INSTALL_DIR/storescreens" --version
