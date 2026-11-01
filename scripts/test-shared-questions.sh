#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p .tmp/shared-question-tests
clang -O2 -mmacosx-version-min=13.0 -c Vendor/Zstd/zstddeclib.c -o .tmp/shared-question-tests/zstd.o
swiftc -swift-version 5 -parse-as-library -I Vendor/Zstd/include .tmp/shared-question-tests/zstd.o \
 Sources/CodexNotchMonitor/FastTimestamp.swift Sources/CodexNotchMonitor/CountFormatter.swift \
 Sources/CodexNotchMonitor/CoverAILinks.swift Sources/CodexNotchMonitor/CodexProjectCatalog.swift \
 Sources/CodexNotchMonitor/Models.swift Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
 Sources/CodexNotchMonitor/ActivitySessionState.swift \
 Sources/CodexNotchMonitor/TurnTokenState.swift Sources/CodexNotchMonitor/SessionActivityService.swift \
 Sources/CodexNotchMonitor/CodexNativeActivityTypes.swift Sources/CodexNotchMonitor/CodexDesktopIPCClient.swift \
 Sources/CodexNotchMonitor/CodexDesktopRequestProjection.swift Sources/CodexNotchMonitor/CodexProxyTransport.swift \
 Sources/CodexNotchMonitor/CodexSharedQuestions.swift Tests/CodexSharedQuestionTests.swift \
 -o .tmp/shared-question-tests/questions
.tmp/shared-question-tests/questions
swiftc -swift-version 5 -parse-as-library Sources/CodexNotchMonitor/CodexProxyTransport.swift \
 Tests/CodexProxyTransportTests.swift -o .tmp/shared-question-tests/transport
.tmp/shared-question-tests/transport
