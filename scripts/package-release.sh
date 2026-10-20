#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
release_version=$(tr -d '\r\n' < VERSION)
release_output=${1:?Usage: package-release.sh OUTPUT_DIRECTORY}
mkdir -p "$release_output"
release_output=$(cd "$release_output" && pwd)
release_stage=$(mktemp -d)
trap 'rm -rf "$release_stage"' EXIT
swift build -c release
release_bin=$(swift build -c release --show-bin-path)
cp "$release_bin/storescreens" "$release_bin/storescreens-mcp" LICENSE "$release_stage/"
for release_bundle in "$release_bin/"*.bundle; do
    [[ -d "$release_bundle" ]] && cp -R "$release_bundle" "$release_stage/"
done
"$release_stage/storescreens" --version
"$release_stage/storescreens" setup --print-template > /dev/null
tar czf "$release_output/storescreens-v${release_version}-macos.tar.gz" -C "$release_stage" .
