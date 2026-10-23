#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
test_binary="$(mktemp /tmp/codex-notch-monitor-tests.XXXXXX)"
cost_test_binary="$(mktemp /tmp/codex-notch-cost-tests.XXXXXX)"
catalog_test_binary="$(mktemp /tmp/codex-notch-catalog-tests.XXXXXX)"
tibo_test_binary="$(mktemp /tmp/codex-notch-tibo-tests.XXXXXX)"
reset_test_binary="$(mktemp /tmp/codex-notch-reset-tests.XXXXXX)"
continuity_test_binary="$(mktemp /tmp/codex-notch-continuity-tests.XXXXXX)"
ripple_test_binary="$(mktemp /tmp/codex-notch-ripple-tests.XXXXXX)"
activity_island_test_binary="$(mktemp /tmp/codex-notch-activity-island-tests.XXXXXX)"
activity_preferences_test_binary="$(mktemp /tmp/codex-notch-activity-preferences-tests.XXXXXX)"
setup_test_binary="$(mktemp /tmp/codex-notch-setup-tests.XXXXXX)"
update_test_binary="$(mktemp /tmp/codex-notch-update-tests.XXXXXX)"
trap 'rm -f "$test_binary" "$cost_test_binary" "$catalog_test_binary" "$tibo_test_binary" "$reset_test_binary" "$continuity_test_binary" "$ripple_test_binary" "$activity_island_test_binary" "$activity_preferences_test_binary" "$setup_test_binary" "$update_test_binary"' EXIT

cd "$project_dir"
swiftc -swift-version 5 -parse-as-library Sources/CodexNotchMonitor/CountFormatter.swift Sources/CodexNotchMonitor/SettingsSummaryText.swift Tests/SettingsSummaryTextTests.swift -o "$test_binary"
"$test_binary"
swiftc -swift-version 5 -parse-as-library Sources/CodexNotchMonitor/ActivityIslandPreferences.swift Sources/CodexNotchMonitor/NotificationAuthorizationPolicy.swift Tests/CompletionCelebrationTests.swift -o "$test_binary"
"$test_binary"
swiftc -swift-version 5 -parse-as-library Sources/CodexNotchMonitor/IslandAlert.swift Sources/CodexNotchMonitor/ActivityIslandLifecycle.swift Tests/IslandAlertTests.swift -o "$test_binary"
"$test_binary"
mkdir -p .tmp/test-runtime
zstd_object="$project_dir/.tmp/test-runtime/zstddeclib.o"
clang -O2 -mmacosx-version-min=13.0 -c Vendor/Zstd/zstddeclib.c -o "$zstd_object"
swiftc -swift-version 5 -parse-as-library Sources/CodexNotchMonitor/CountFormatter.swift Tests/CountFormatterTests.swift -o "$test_binary"
"$test_binary"

swiftc Sources/CodexNotchMonitor/CountFormatter.swift -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/Models.swift \
  Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
  Sources/CodexNotchMonitor/GlanceLayout.swift \
  Sources/CodexNotchMonitor/GlanceContentPreferences.swift \
  Sources/CodexNotchMonitor/GlanceForecast.swift \
  Sources/CodexNotchMonitor/ClaudeCodePricing.swift \
  Sources/CodexNotchMonitor/ClaudeCodeTranscript.swift \
  Sources/CodexNotchMonitor/ClaudeCodeUsage.swift \
  Tests/GlanceForecastTests.swift -o "$test_binary"
"$test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" -swift-version 5 -parse-as-library Sources/CodexNotchMonitor/RolloutReader.swift Tests/RolloutReaderTests.swift -o "$test_binary"
"$test_binary"
swiftc -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/MonitorDesktopStyle.swift \
  Sources/CodexNotchMonitor/AnalysisPresentation.swift \
  Tests/AnalysisPresentationTests.swift \
  -o "$test_binary"
"$test_binary"

swiftc Sources/CodexNotchMonitor/CountFormatter.swift -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/CoverAILinks.swift \
  Sources/CodexNotchMonitor/CodexProjectCatalog.swift \
  Sources/CodexNotchMonitor/CodexExecutableLocator.swift \
  Sources/CodexNotchMonitor/CodexAppServerClient.swift \
  Sources/CodexNotchMonitor/Models.swift \
  Sources/CodexNotchMonitor/MenuBarQuotaRing.swift \
  Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
  Sources/CodexNotchMonitor/QuotaService.swift \
  Sources/CodexNotchMonitor/AccountUsageSnapshot.swift \
  Sources/CodexNotchMonitor/SessionActivityService.swift \
  Sources/CodexNotchMonitor/CodexNativeActivityTypes.swift \
  Sources/CodexNotchMonitor/TurnTokenState.swift \
  Tests/ModelSmokeTests.swift \
  -o "$test_binary"
"$test_binary"

swiftc Sources/CodexNotchMonitor/CountFormatter.swift -I Vendor/Zstd/include "$zstd_object" -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/CoverAILinks.swift \
  Sources/CodexNotchMonitor/CodexProjectCatalog.swift \
  Sources/CodexNotchMonitor/Models.swift \
  Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
  Sources/CodexNotchMonitor/TurnTokenState.swift \
  Sources/CodexNotchMonitor/SessionActivityService.swift \
  Sources/CodexNotchMonitor/CodexNativeActivityTypes.swift \
  Sources/CodexNotchMonitor/ActivitySessionState.swift \
  Tests/ActivitySessionStateTests.swift \
  -o "$activity_island_test_binary"
"$activity_island_test_binary"

swiftc Sources/CodexNotchMonitor/CountFormatter.swift -I Vendor/Zstd/include "$zstd_object" -swift-version 5 -parse-as-library Sources/CodexNotchMonitor/CoverAILinks.swift Sources/CodexNotchMonitor/CodexProjectCatalog.swift Sources/CodexNotchMonitor/Models.swift Sources/CodexNotchMonitor/ActivityIslandPreferences.swift Sources/CodexNotchMonitor/TurnTokenState.swift Sources/CodexNotchMonitor/SessionActivityService.swift Sources/CodexNotchMonitor/CodexNativeActivityTypes.swift Sources/CodexNotchMonitor/CodexDesktopIPCClient.swift Sources/CodexNotchMonitor/CodexDesktopRequestProjection.swift Sources/CodexNotchMonitor/NativeActivityObserver.swift Sources/CodexNotchMonitor/ActivitySessionState.swift Tests/NativeActivityFixture.swift Tests/NativeActivityTests.swift -o "$activity_island_test_binary"
"$activity_island_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/Models.swift \
  Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
  Sources/CodexNotchMonitor/RippleGlowOrb.swift \
  Tests/RippleGlowRuntimeTests.swift \
  -o "$ripple_test_binary"
"$ripple_test_binary"

swiftc Sources/CodexNotchMonitor/CountFormatter.swift -I Vendor/Zstd/include "$zstd_object" -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/CoverAILinks.swift \
  Sources/CodexNotchMonitor/CodexProjectCatalog.swift \
  Sources/CodexNotchMonitor/Models.swift \
  Sources/CodexNotchMonitor/TurnTokenState.swift \
  Sources/CodexNotchMonitor/SessionActivityService.swift \
  Sources/CodexNotchMonitor/CodexNativeActivityTypes.swift \
  Sources/CodexNotchMonitor/ActivitySessionState.swift \
  Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
  Sources/CodexNotchMonitor/ActivityIslandLifecycle.swift \
  Sources/CodexNotchMonitor/RippleGlowOrb.swift \
  Sources/CodexNotchMonitor/ActivityIslandMotion.swift \
  Sources/CodexNotchMonitor/MonitorDesktopStyle.swift \
  Sources/CodexNotchMonitor/ActivityIslandGlass.swift \
  Sources/CodexNotchMonitor/ActivityIslandUsageCapsule.swift \
  Sources/CodexNotchMonitor/ActivityIslandTaskEffectHost.swift \
  Sources/CodexNotchMonitor/ActivityIslandEffects.swift \
  Sources/CodexNotchMonitor/ActivityIslandStateSmoke.swift \
  Sources/CodexNotchMonitor/ActivityIslandScrollingText.swift \
  Sources/CodexNotchMonitor/ActivityIslandApprovalCard.swift \
  Sources/CodexNotchMonitor/IslandAlert.swift \
  Sources/CodexNotchMonitor/IslandAlertCard.swift \
  Sources/CodexNotchMonitor/ActivityIslandView.swift \
  Sources/CodexNotchMonitor/ActivityIslandDesktopPreview.swift \
  Sources/CodexNotchMonitor/ActivityIslandMascot.swift \
  Sources/CodexNotchMonitor/ActivityIslandFocusCard.swift \
  Sources/CodexNotchMonitor/ActivityIslandUsageDashboard.swift \
  Sources/CodexNotchMonitor/IslandDashboardChartScroll.swift \
  Sources/CodexNotchMonitor/IslandDashboardPageLayout.swift \
  Sources/CodexNotchMonitor/IslandDashboardCost.swift \
  Sources/CodexNotchMonitor/IslandClaudeUsage.swift \
  Sources/CodexNotchMonitor/IslandUsagePresentation.swift \
  Sources/CodexNotchMonitor/IslandUsageSections.swift \
  Sources/CodexNotchMonitor/ClaudeCodePricing.swift \
  Sources/CodexNotchMonitor/ClaudeCodeTranscript.swift \
  Sources/CodexNotchMonitor/ClaudeCodeUsage.swift \
  Sources/CodexNotchMonitor/IslandDashboardTicket.swift \
  Sources/CodexNotchMonitor/IslandDashboardResetPage.swift \
  Sources/CodexNotchMonitor/IslandDashboardResetActionStyle.swift \
  Sources/CodexNotchMonitor/IslandDashboardResetFlight.swift \
  Sources/CodexNotchMonitor/AstaSansFont.swift \
  Sources/CodexNotchMonitor/AccountUsageSnapshot.swift \
  Sources/CodexNotchMonitor/IslandDashboardHeatmap.swift \
  Sources/CodexNotchMonitor/PricingCatalog.swift \
  Sources/CodexNotchMonitor/ModelPricing.swift \
  Sources/CodexNotchMonitor/UsageAccountContext.swift \
  Sources/CodexNotchMonitor/RolloutReader.swift \
  Sources/CodexNotchMonitor/CostService.swift \
  Sources/CodexNotchMonitor/ActivityIslandTaskScroll.swift \
  Sources/CodexNotchMonitor/ActivityIslandPanel.swift \
  Sources/CodexNotchMonitor/ActivityIslandCompletionConfetti.swift \
  Tests/IslandMascotTests.swift \
  Tests/IslandHardwareBlackTests.swift \
  Tests/IslandDesktopPreviewTests.swift \
  Tests/ActivityIslandPanelTests.swift \
  -o "$activity_island_test_binary"
"$activity_island_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/ActivityIslandLifecycle.swift \
  Tests/ActivityIslandLifecycleTests.swift \
  -o "$activity_island_test_binary"
"$activity_island_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/CountFormatter.swift \
  Sources/CodexNotchMonitor/StatusItemLayout.swift \
  Tests/StatusItemLayoutTests.swift \
  -o "$activity_island_test_binary"
"$activity_island_test_binary"

swiftc Sources/CodexNotchMonitor/CountFormatter.swift -I Vendor/Zstd/include "$zstd_object" -swift-version 5 -parse-as-library \
  Sources/CodexNotchMonitor/TurnTokenState.swift \
  Tests/TurnTokenStateTests.swift \
  -o "$activity_island_test_binary"
"$activity_island_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
  Tests/ActivityIslandPreferencesTests.swift \
  -o "$activity_preferences_test_binary"
"$activity_preferences_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/AppPaths.swift \
  Sources/CodexNotchMonitor/CodexExecutableLocator.swift \
  Sources/CodexNotchMonitor/CodexSetupService.swift \
  Tests/CodexSetupServiceTests.swift \
  -o "$setup_test_binary"
"$setup_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/AppPaths.swift \
  Sources/CodexNotchMonitor/AppUpdateService.swift \
  Tests/AppUpdateServiceTests.swift \
  -o "$update_test_binary"
"$update_test_binary"

if [[ "${SKIP_COST_SMOKE_TESTS:-0}" != "1" ]]; then
swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/PricingCatalog.swift \
  Sources/CodexNotchMonitor/ModelPricing.swift \
  Sources/CodexNotchMonitor/CodexProjectCatalog.swift \
  Sources/CodexNotchMonitor/TokenActivityLayout.swift \
  Sources/CodexNotchMonitor/UsageAccountContext.swift \
  Sources/CodexNotchMonitor/RolloutReader.swift \
  Sources/CodexNotchMonitor/CostService.swift \
  Tests/CostSmokeTests.swift \
  -o "$cost_test_binary"
"$cost_test_binary"
else
  echo "SKIP CostSmokeTests: real usage log access disabled"
fi

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/PricingCatalog.swift \
  Sources/CodexNotchMonitor/ModelPricing.swift \
  Tests/PricingCatalogTests.swift \
  -o "$catalog_test_binary"
"$catalog_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/AppPaths.swift \
  Sources/CodexNotchMonitor/TiboFeedService.swift \
  Sources/CodexNotchMonitor/CodexResetRadarService.swift \
  Tests/TiboFeedTests.swift \
  -o "$tibo_test_binary"
"$tibo_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/AppPaths.swift \
  Sources/CodexNotchMonitor/Models.swift \
  Sources/CodexNotchMonitor/ActivityIslandPreferences.swift \
  Sources/CodexNotchMonitor/TiboFeedService.swift \
  Sources/CodexNotchMonitor/CodexResetRadarService.swift \
  Sources/CodexNotchMonitor/QuotaResetMonitor.swift \
  Sources/CodexNotchMonitor/ActivityIslandLifecycle.swift \
  Sources/CodexNotchMonitor/IslandAlert.swift \
  Sources/CodexNotchMonitor/SystemNotificationContent.swift \
  Tests/SystemNotificationTests.swift \
  Tests/QuotaResetMonitorTests.swift \
  -o "$reset_test_binary"
"$reset_test_binary"

swiftc -I Vendor/Zstd/include "$zstd_object" \
  -swift-version 5 \
  -parse-as-library \
  Sources/CodexNotchMonitor/AppPaths.swift \
  Sources/CodexNotchMonitor/CodexExecutableLocator.swift \
  Sources/CodexNotchMonitor/CodexAppServerClient.swift \
  Sources/CodexNotchMonitor/CodexProjectCatalog.swift \
  Sources/CodexNotchMonitor/CodexAccountStateWatcher.swift \
  Sources/CodexNotchMonitor/UsageAccountContext.swift \
  Sources/CodexNotchMonitor/AccountContinuity.swift \
  Sources/CodexNotchMonitor/RolloutReader.swift \
  Sources/CodexNotchMonitor/SessionContinuityService.swift \
  Sources/CodexNotchMonitor/CodexSidebarCleanupService.swift \
  Sources/CodexNotchMonitor/SessionExportService.swift \
  Sources/CodexNotchMonitor/SessionExportImages.swift \
  Sources/CodexNotchMonitor/SessionImportService.swift \
  Sources/CodexNotchMonitor/ProjectTransferService.swift \
  Sources/CodexNotchMonitor/SessionRecoveryService.swift \
  Tests/ContinuityTests.swift \
  -o "$continuity_test_binary"
"$continuity_test_binary"

zsh scripts/test-claude.sh
