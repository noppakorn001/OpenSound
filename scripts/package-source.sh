#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist build
task_stage=$(mktemp -d "$PWD/dist/.source-stage.XXXXXX")
task_package="$task_stage/OpenSound-source"
mkdir -p "$task_package" "$task_package/tests" "$task_package/scripts" "$task_package/Sources/Native"
cp -R Sources/Core Sources/App "$task_package/Sources/"
cp Sources/Native/WFBridge.h Sources/Native/WFBridge.mm Sources/Native/WFTransport.h Sources/Native/WFTransport.mm Sources/Native/HardwareTests.mm Sources/Native/SettingsRestorationTests.mm "$task_package/Sources/Native/"
cp -R Resources docs "$task_package/"
cp README.md CONTRIBUTING.md SECURITY.md CHANGELOG.md LICENSE LICENSE.SonyBridge LICENSE.SonyHeadphonesClient THIRD_PARTY_NOTICES.md "$task_package/"
cp tests/ProtocolTests.cpp tests/FeatureCatalogTests.py tests/SecurityTests.cpp tests/DiagnosticLogTests.mm tests/ReconnectPolicyTests.swift "$task_package/tests/"
cp scripts/build.sh scripts/build-icon.sh scripts/test.sh scripts/security-test.sh scripts/package-source.sh scripts/hardware-test.sh scripts/settings-hardware-test.sh scripts/generate-feature-catalog.py "$task_package/scripts/"
if [[ -d .github ]]; then cp -R .github "$task_package/"; fi
printf '/build/\n/dist/\n/analysis/\n*.ipa\n.DS_Store\n' > "$task_package/.gitignore"
COPYFILE_DISABLE=1 tar -czf dist/OpenSound-source.tar.gz -C "$task_stage" OpenSound-source
if [[ -d dist/OpenSound-source ]]; then
  task_previous=$(mktemp -d "$PWD/build/source-package-previous.XXXXXX")
  mv dist/OpenSound-source "$task_previous/"
fi
mv "$task_package" dist/OpenSound-source
rmdir "$task_stage"
echo "Source package: $PWD/dist/OpenSound-source.tar.gz"
