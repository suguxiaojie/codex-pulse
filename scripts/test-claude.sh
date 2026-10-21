#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p .tmp/claude-tests
swiftc -swift-version 5 -parse-as-library Sources/ClaudePulseHelper/ClaudeHookProcess.swift \
  Tests/ClaudeHookProcessTests.swift -o .tmp/claude-tests/process-ancestry
.tmp/claude-tests/process-ancestry
swiftc -swift-version 5 Sources/ClaudePulseHelper/*.swift -o .tmp/claude-tests/helper
swiftc -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/ClaudeCodePricing.swift \
  Sources/CodexNotchMonitor/ClaudeCodeTranscript.swift \
  Sources/CodexNotchMonitor/ClaudeCodeUsage.swift \
  Sources/CodexNotchMonitor/ClaudeCodeBridge.swift \
  Sources/CodexNotchMonitor/ClaudeCodeInstaller.swift \
  Sources/CodexNotchMonitor/ClaudePermissionRequest.swift \
  Tests/ClaudeCodeTests.swift -o .tmp/claude-tests/core
.tmp/claude-tests/core "$project_dir/.tmp/claude-tests/helper"
# Build the runtime against the actual app types and views, excluding the app entry point.
clang -O2 -mmacosx-version-min=13.0 -c Vendor/Zstd/zstddeclib.c -o .tmp/claude-tests/zstd.o
sources=(Sources/CodexNotchMonitor/*.swift)
sources=(${sources:#Sources/CodexNotchMonitor/App.swift})
swiftc -I Vendor/Zstd/include .tmp/claude-tests/zstd.o -swift-version 5 -parse-as-library \
  "${sources[@]}" Tests/NativeActivityFixture.swift Tests/IslandApprovalTests.swift Tests/ClaudeRuntimeTests.swift -o .tmp/claude-tests/runtime
.tmp/claude-tests/runtime "$project_dir/.tmp/claude-tests/helper"
