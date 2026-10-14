#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_iconset=build/OpenSound.iconset
mkdir -p "$task_iconset"
for task_size in 16 32 128 256 512; do
  sips -z "$task_size" "$task_size" Resources/Icon/OpenSound.png --out "$task_iconset/icon_${task_size}x${task_size}.png" >/dev/null
  task_retina=$((task_size * 2))
  sips -z "$task_retina" "$task_retina" Resources/Icon/OpenSound.png --out "$task_iconset/icon_${task_size}x${task_size}@2x.png" >/dev/null
done
iconutil -c icns "$task_iconset" -o Resources/Icon/OpenSound.icns
