#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_app=dist/OpenSound.app
mkdir -p build/module-cache "$task_app/Contents/MacOS" "$task_app/Contents/Resources/licenses"
task_sdk=$(xcrun --sdk macosx --show-sdk-path)
for source in Sources/Core/WFProtocol.cpp Sources/Native/WFTransport.mm Sources/Native/WFBridge.mm; do
  task_object="build/$(basename "${source%.*}").o"
  if [[ "$source" == *.mm ]]; then
    xcrun clang++ -std=c++17 -fobjc-arc -O2 -arch arm64 -isysroot "$task_sdk" -mmacosx-version-min=14.0 -c "$source" -o "$task_object"
  else
    xcrun clang++ -std=c++17 -O2 -arch arm64 -isysroot "$task_sdk" -mmacosx-version-min=14.0 -c "$source" -o "$task_object"
  fi
done
xcrun swiftc -parse-as-library -O -swift-version 5 -module-cache-path build/module-cache -module-name OpenSound -target arm64-apple-macos14.0 -sdk "$task_sdk" \
  -import-objc-header Sources/Native/WFBridge.h Sources/App/*.swift \
  build/WFProtocol.o build/WFTransport.o build/WFBridge.o \
  -framework Foundation -framework AppKit -framework SwiftUI -framework IOBluetooth -lc++ \
  -o "$task_app/Contents/MacOS/OpenSound"
[[ -f Resources/Icon/OpenSound.icns ]] || bash scripts/build-icon.sh
cp Resources/Icon/OpenSound.icns "$task_app/Contents/Resources/OpenSound.icns"
cp Resources/Icon/OpenSound.png "$task_app/Contents/Resources/OpenSound.png"
mkdir -p "$task_app/Contents/Resources/Devices"
cp Resources/Devices/*.png "$task_app/Contents/Resources/Devices/"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
cp LICENSE.SonyBridge "$task_app/Contents/Resources/licenses/SonyBridge.txt"
cp LICENSE.SonyHeadphonesClient "$task_app/Contents/Resources/licenses/SonyHeadphonesClient.txt"
cp LICENSE "$task_app/Contents/Resources/licenses/OpenSound.txt"
codesign --force --options runtime --sign - "$task_app"
codesign --verify --strict "$task_app"
echo "Built: $PWD/$task_app"
