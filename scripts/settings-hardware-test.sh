#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build analysis
# Temporarily changes connection quality, auto-off and multipoint settings.
# Close OpenSound and all other controllers; the test saves and restores values.
xcrun clang++ -std=c++17 -fobjc-arc Sources/Native/SettingsRestorationTests.mm Sources/Native/WFBridge.mm Sources/Native/WFTransport.mm Sources/Core/WFProtocol.cpp -framework Foundation -framework IOBluetooth -o build/settings-restoration-tests
codesign --force --sign - build/settings-restoration-tests
build/settings-restoration-tests "$@"
