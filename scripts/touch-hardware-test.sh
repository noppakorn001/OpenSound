#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build analysis
# Close other controllers. Temporarily changes both touch presets and restores
# the saved pair. Intended for the documented WF-1000XM4 test configuration.
xcrun clang++ -std=c++17 -fobjc-arc Sources/Native/TouchAssignmentTests.mm Sources/Native/WFBridge.mm Sources/Native/WFTransport.mm Sources/Core/WFProtocol.cpp -framework Foundation -framework IOBluetooth -o build/touch-assignment-tests
codesign --force --sign - build/touch-assignment-tests
build/touch-assignment-tests
