#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p .tmp/grok-tests
fixture_dir="$(mktemp -d "$project_dir/.tmp/grok-tests/run.XXXXXX")"
swiftc -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/FastTimestamp.swift \
  Sources/CodexNotchMonitor/GrokData.swift \
  Sources/CodexNotchMonitor/GrokBillingClient.swift \
  Sources/CodexNotchMonitor/GrokSessionReader.swift \
  Tests/GrokTests.swift -o "$fixture_dir/core"
"$fixture_dir/core" "$fixture_dir/home"
swiftc -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/FastTimestamp.swift Sources/CodexNotchMonitor/GrokData.swift \
  Sources/CodexNotchMonitor/GrokQuestion.swift Sources/CodexNotchMonitor/GrokSharedClient.swift \
  Sources/CodexNotchMonitor/GrokLauncher.swift Tests/GrokQuestionTests.swift -o "$fixture_dir/questions"
"$fixture_dir/questions" "$fixture_dir/question-fixtures"
clang -O2 -mmacosx-version-min=13.0 -c Vendor/Zstd/zstddeclib.c -o "$fixture_dir/zstd.o"
sources=(Sources/CodexNotchMonitor/*.swift)
sources=(${sources:#Sources/CodexNotchMonitor/App.swift})
swiftc -whole-module-optimization -Onone -I Vendor/Zstd/include "$fixture_dir/zstd.o" \
  -swift-version 5 -parse-as-library "${sources[@]}" Tests/GrokRuntimeTests.swift -o "$fixture_dir/runtime"
"$fixture_dir/runtime" "$fixture_dir/runtime-fixtures"
