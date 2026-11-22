#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./script/build_and_run.sh --build
bundle="dist/Battery % Viewer.app"
version=$(plutil -extract CFBundleShortVersionString raw "$bundle/Contents/Info.plist")
mkdir -p dist/release
staging=$(mktemp -d "$PWD/build/macos-disk-image.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT

codesign --verify --strict "$bundle"
ditto "$bundle" "$staging/Battery % Viewer.app"
ln -s /Applications "$staging/Applications"
image="dist/release/Battery-Viewer-$version-macOS-universal.dmg"
hdiutil create -ov -format UDZO -volname "Battery % Viewer $version" -srcfolder "$staging" "$image"
hdiutil verify "$image"
