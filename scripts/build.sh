#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Clang module caches embed absolute paths; a moved checkout needs a fresh namespace.
task_module_cache="build/module-cache/$(printf '%s' "$PWD" | shasum -a 256 | cut -c1-16)"
task_app=dist/OpenSound.app
task_images=${OPENSOUND_DEVICE_IMAGES:-bundled}
case "$task_images" in
  bundled|none) ;;
  *) echo "OPENSOUND_DEVICE_IMAGES must be bundled or none" >&2; exit 1 ;;
esac
mkdir -p "$task_module_cache" "$task_app/Contents/MacOS" "$task_app/Contents/Resources/licenses"
task_sdk=$(xcrun --sdk macosx --show-sdk-path)
for source in Sources/Core/WFProtocol.cpp Sources/Native/WFTransport.mm Sources/Native/WFBridge.mm; do
  task_object="build/$(basename "${source%.*}").o"
  if [[ "$source" == *.mm ]]; then
    xcrun clang++ -std=c++17 -fobjc-arc -O2 -arch arm64 -isysroot "$task_sdk" -mmacosx-version-min=14.0 -c "$source" -o "$task_object"
  else
    xcrun clang++ -std=c++17 -O2 -arch arm64 -isysroot "$task_sdk" -mmacosx-version-min=14.0 -c "$source" -o "$task_object"
  fi
done
xcrun swiftc -parse-as-library -O -swift-version 5 -module-cache-path "$task_module_cache" -module-name OpenSound -target arm64-apple-macos14.0 -sdk "$task_sdk" \
  -import-objc-header Sources/Native/WFBridge.h Sources/App/*.swift \
  build/WFProtocol.o build/WFTransport.o build/WFBridge.o \
  -framework Foundation -framework AppKit -framework SwiftUI -framework IOBluetooth -lc++ \
  -o "$task_app/Contents/MacOS/OpenSound"
[[ -f Resources/Icon/OpenSound.icns ]] || bash scripts/build-icon.sh
cp Resources/Icon/OpenSound.icns "$task_app/Contents/Resources/OpenSound.icns"
cp Resources/Icon/OpenSound.png "$task_app/Contents/Resources/OpenSound.png"
mkdir -p "$task_app/Contents/Resources/Devices"
# Clear stale renders when switching an existing build to image-free mode.
rm -f "$task_app/Contents/Resources/Devices/"*.png
if [[ "$task_images" == bundled ]]; then
  shopt -s nullglob
  task_device_images=(Resources/Devices/*.png)
  if (( ${#task_device_images[@]} )); then
    cp "${task_device_images[@]}" "$task_app/Contents/Resources/Devices/"
  fi
fi
cp Resources/Devices/NOTICE.md "$task_app/Contents/Resources/Devices/NOTICE.md"
cp THIRD_PARTY_NOTICES.md "$task_app/Contents/Resources/licenses/THIRD_PARTY_NOTICES.md"
cp docs/LICENSING.md "$task_app/Contents/Resources/licenses/LICENSING.md"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
cp LICENSE.SonyBridge "$task_app/Contents/Resources/licenses/SonyBridge.txt"
cp LICENSE.SonyHeadphonesClient "$task_app/Contents/Resources/licenses/SonyHeadphonesClient.txt"
cp LICENSE "$task_app/Contents/Resources/licenses/OpenSound.txt"
codesign --force --options runtime --sign - "$task_app"
codesign --verify --strict "$task_app"
echo "Built: $PWD/$task_app"
