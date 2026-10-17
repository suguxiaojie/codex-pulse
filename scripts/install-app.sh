#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/build/CodexNotchMonitor.app"
target_app="/Applications/CodexNotchMonitor.app"
architecture="${1:-native}"

"$project_dir/scripts/build-app.sh" "$architecture"

if [[ -d "$target_app" ]]; then
  backup_dir="$project_dir/build/backups"
  mkdir -p "$backup_dir"
  backup_app="$backup_dir/CodexNotchMonitor-$(date +%Y%m%d-%H%M%S).app"
  ditto "$target_app" "$backup_app"
  echo "已备份旧版本：$backup_app"
fi

pkill -f '/Applications/CodexNotchMonitor.app/Contents/MacOS/CodexNotchMonitor' 2>/dev/null || true
rm -f "$target_app/Contents/Helpers/CodexMonitorHook"
rmdir "$target_app/Contents/Helpers" 2>/dev/null || true
ditto "$source_app" "$target_app"
codesign --verify --deep --strict "$target_app"
open "$target_app"

echo "应用已安装：$target_app"
