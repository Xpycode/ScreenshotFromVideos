#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/seek-coalescer-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
# Headless executable; injected seeks, empty players/in-memory composition only.
# No app host/startup hooks, media files, preferences, network, or desktop control.
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -module-cache-path "$test_dir/module-cache" \
    "$project_root/01_Project/ScreenshotFromVideos/Thumbnail/SeekCoalescer.swift" \
    "$project_root/scripts/tests/SeekCoalescerTests.swift" \
    -o "$test_dir/seek-coalescer-tests"
"$test_dir/seek-coalescer-tests"
