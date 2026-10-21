#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Clang module caches embed absolute paths; a moved checkout needs a fresh namespace.
task_module_cache="build/module-cache/$(printf '%s' "$PWD" | shasum -a 256 | cut -c1-16)"
mkdir -p build "$task_module_cache"
xcrun clang++ -std=c++17 -ISources/Core -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  Sources/Core/WFProtocol.cpp tests/ProtocolTests.cpp -o build/protocol-tests
build/protocol-tests
xcrun swiftc -module-cache-path "$task_module_cache" Sources/App/ReconnectPolicy.swift tests/ReconnectPolicyTests.swift -o build/reconnect-tests
build/reconnect-tests
