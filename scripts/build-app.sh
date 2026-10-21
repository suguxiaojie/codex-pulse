#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/build/CodexNotchMonitor.app"
requested_arch="${1:-native}"

case "$requested_arch" in
  native)
    build_arch="$(uname -m)"
    ;;
  arm64|x86_64|universal)
    build_arch="$requested_arch"
    ;;
  *)
    echo "用法：$0 [native|arm64|x86_64|universal]" >&2
    exit 2
    ;;
esac

cd "$project_dir"

build_one_architecture() {
  local architecture="$1"
  local scratch_path="$project_dir/.build/$architecture"
  swift build -c release --arch "$architecture" --scratch-path "$scratch_path"
  swift build -c release --arch "$architecture" --scratch-path "$scratch_path" --show-bin-path
}

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
mkdir -p "$app_dir/Contents/Resources/Fonts"
# Remove the retired helper from reused build bundles.
rm -f "$app_dir/Contents/Helpers/CodexMonitorHook"
rmdir "$app_dir/Contents/Helpers" 2>/dev/null || true

if [[ "$build_arch" == "universal" ]]; then
  arm64_bin_dir="$(build_one_architecture arm64 | tail -n 1)"
  x86_64_bin_dir="$(build_one_architecture x86_64 | tail -n 1)"

  mkdir -p "$app_dir/Contents/Helpers"
  lipo -create "$arm64_bin_dir/ClaudePulseHelper" "$x86_64_bin_dir/ClaudePulseHelper" -output "$app_dir/Contents/Helpers/ClaudePulseHelper"
  lipo -create \
    "$arm64_bin_dir/CodexNotchMonitor" \
    "$x86_64_bin_dir/CodexNotchMonitor" \
    -output "$app_dir/Contents/MacOS/CodexNotchMonitor"
else
  bin_dir="$(build_one_architecture "$build_arch" | tail -n 1)"
  mkdir -p "$app_dir/Contents/Helpers"
  cp "$bin_dir/ClaudePulseHelper" "$app_dir/Contents/Helpers/ClaudePulseHelper"
  cp "$bin_dir/CodexNotchMonitor" "$app_dir/Contents/MacOS/CodexNotchMonitor"
fi

verify_architectures() {
  local binary="$1"
  local architectures
  architectures="$(lipo -archs "$binary")"
  if [[ "$build_arch" == "universal" ]]; then
    [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
      echo "Universal 构建缺少架构：$binary ($architectures)" >&2
      exit 1
    }
  else
    [[ " $architectures " == *" $build_arch "* ]] || {
      echo "构建架构不匹配：$binary ($architectures)" >&2
      exit 1
    }
  fi
}

verify_architectures "$app_dir/Contents/MacOS/CodexNotchMonitor"
verify_architectures "$app_dir/Contents/Helpers/ClaudePulseHelper"
chmod 755 "$app_dir/Contents/Helpers/ClaudePulseHelper"
codesign --force --sign - "$app_dir/Contents/Helpers/ClaudePulseHelper"

cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp \
  "$project_dir/Resources/CodexActivityRippleGlowShader.txt" \
  "$app_dir/Contents/Resources/CodexActivityRippleGlowShader.txt"
# Retired selectable Particle Orb asset; existing build directories may contain it.
rm -f "$app_dir/Contents/Resources/CodexActivityParticleOrbShader.txt"
cp \
  "$project_dir/Resources/CoverAI-Logo.png" \
  "$app_dir/Contents/Resources/CoverAI-Logo.png"
cp "$project_dir/Resources/Pulse-Logo.svg" "$app_dir/Contents/Resources/Pulse-Logo.svg"
cp "$project_dir/Resources/Pulse-AppIcon.icns" "$app_dir/Contents/Resources/Pulse-AppIcon.icns"
ditto "$project_dir/Resources/Fonts" "$app_dir/Contents/Resources/Fonts"
cp "$project_dir/Resources/ThirdPartyNotices.txt" "$app_dir/Contents/Resources/ThirdPartyNotices.txt"
for asset in "$project_dir"/Resources/DashboardReset*.svg "$project_dir"/Resources/IslandPreview-*.png "$project_dir/Resources/Island-Codex.svg"; do
  cp "$asset" "$app_dir/Contents/Resources/"
done
chmod 755 "$app_dir/Contents/MacOS/CodexNotchMonitor"
codesign --force --deep --sign - "$app_dir"

echo "主程序架构：$(lipo -archs "$app_dir/Contents/MacOS/CodexNotchMonitor")"
echo "$app_dir"
