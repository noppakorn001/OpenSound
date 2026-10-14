#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_app=dist/OpenSound.app
[[ -d "$task_app" ]] || bash scripts/build.sh
codesign --verify --deep --strict "$task_app"
task_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")
[[ "$task_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid app version.' >&2; exit 1; }
task_output="dist/OpenSound-${task_version}-macos-arm64.dmg"
task_stage=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
# Stage only the verified bundle and fixed layout, never the research folder.
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$task_app" "$task_stage/OpenSound.app"
ln -s /Applications "$task_stage/Applications"
cp Resources/Installer/FinderLayout.dsstore "$task_stage/.DS_Store"
hdiutil create -ov -volname OpenSound -srcfolder "$task_stage" -format UDZO -fs HFS+ -nospotlight "$task_output"
hdiutil verify "$task_output"
(
    cd dist
    shasum -a 256 "$(basename "$task_output")" > "$(basename "$task_output").sha256"
)
echo "Installer: $PWD/$task_output"
