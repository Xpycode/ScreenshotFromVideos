#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/thumbnail-renderer-retry-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
# Production render loop + decoder double only. No app host, media reads,
# preferences, UI, network or app startup hooks. All build outputs are temporary.
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$test_dir/module-cache" \
    "$project_root/01_Project/ScreenshotFromVideos/Thumbnail/ThumbnailRenderer.swift" \
    "$project_root/scripts/tests/ThumbnailRendererRetryTests.swift" \
    -o "$test_dir/thumbnail-renderer-retry-tests"
"$test_dir/thumbnail-renderer-retry-tests"
