#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang++ -std=c++17 -ISources/Core -fsanitize=address,undefined -fno-omit-frame-pointer -g Sources/Core/WFProtocol.cpp tests/SecurityTests.cpp -o build/security-tests
build/security-tests
xcrun clang++ -std=c++17 -fobjc-arc -ISources/Native -fsanitize=address,undefined -fno-omit-frame-pointer tests/DiagnosticLogTests.mm Sources/Native/WFTransport.mm Sources/Core/WFProtocol.cpp -framework Foundation -framework IOBluetooth -o build/diagnostic-log-tests
build/diagnostic-log-tests
