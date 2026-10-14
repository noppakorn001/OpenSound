#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Changes sound settings temporarily, saves baseline first, and restores them.
# Pair/connect WF-1000XM4 and close other control sessions before running.
mkdir -p build analysis
xcrun clang++ -std=c++17 -fobjc-arc Sources/Native/HardwareTests.mm Sources/Native/WFTransport.mm \
  Sources/Core/WFProtocol.cpp -framework Foundation -framework IOBluetooth -o build/hardware-tests
codesign --force --sign - build/hardware-tests
WF_PROTOCOL_LOG="$PWD/analysis/hardware-tests-latest-frames.jsonl" build/hardware-tests
