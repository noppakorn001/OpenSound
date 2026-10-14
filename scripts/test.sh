#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang++ -std=c++17 -ISources/Core -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  Sources/Core/WFProtocol.cpp tests/ProtocolTests.cpp -o build/protocol-tests
build/protocol-tests
xcrun swiftc -module-cache-path build/module-cache Sources/App/ReconnectPolicy.swift tests/ReconnectPolicyTests.swift -o build/reconnect-tests
build/reconnect-tests
