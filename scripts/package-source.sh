#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist build
task_stage=$(mktemp -d "$PWD/dist/.source-stage.XXXXXX")
task_package="$task_stage/OpenSound-source"
trap 'rm -rf "$task_stage"' EXIT
python3 scripts/export-source.py "$task_package"
COPYFILE_DISABLE=1 tar -czf dist/OpenSound-source.tar.gz -C "$task_stage" OpenSound-source
if [[ -d dist/OpenSound-source ]]; then
  task_previous=$(mktemp -d "$PWD/build/source-package-previous.XXXXXX")
  mv dist/OpenSound-source "$task_previous/"
fi
mv "$task_package" dist/OpenSound-source
rmdir "$task_stage"
echo "Source package: $PWD/dist/OpenSound-source.tar.gz"
