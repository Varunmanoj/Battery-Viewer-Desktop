#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="dist/Battery % Viewer.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" build/swift-cache
for arch in arm64 x86_64; do
    xcrun swiftc -O -target "${arch}-apple-macos13.0" -module-cache-path build/swift-cache macOS/*.swift -o "build/BatteryViewer-$arch"
done
lipo -create build/BatteryViewer-{arm64,x86_64} -output "$bundle/Contents/MacOS/BatteryViewer"
cp macOS/Info.plist "$bundle/Contents/"
cp "MAC AppFiles/Project Files/App Icon.icns" "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$bundle"
case "${1:-run}" in
    --build) exit 0 ;;
    run|--verify)
        pkill -x BatteryViewer || true
        open -n "$bundle"
        if [[ "${1:-run}" == --verify ]]; then sleep 1; pgrep -x BatteryViewer; fi ;;
    *) echo "Usage: $0 [--build|--verify]" >&2; exit 2 ;;
esac
