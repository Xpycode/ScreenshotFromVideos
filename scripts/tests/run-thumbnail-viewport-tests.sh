#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/thumbnail-viewport-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
# Compiles only the Foundation helper and assertions; no app host, preferences,
# media access, desktop control, network, or app startup hooks.
swiftc -module-cache-path "$test_dir/module-cache" \
    "$project_root/01_Project/ScreenshotFromVideos/Thumbnail/ThumbnailViewport.swift" \
    "$project_root/scripts/tests/ThumbnailViewportTests.swift" \
    -o "$test_dir/thumbnail-viewport-tests"
"$test_dir/thumbnail-viewport-tests"
