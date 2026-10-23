#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
APP="Zest.app"

echo "Building Zest ($CONFIG)…"
swift build -c "$CONFIG"

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Zest" "$APP/Contents/MacOS/Zest"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Ship media tools when available so Finder-launched instances do not
# depend on a shell PATH. Set ZEST_TOOLS_SRC to pick a Tools directory
# explicitly; otherwise use the first app bundle that ships both binaries.
TOOLS_SRC="${ZEST_TOOLS_SRC:-}"
if [ -z "$TOOLS_SRC" ]; then
    for candidate in /Applications/*.app/Contents/Resources/Tools; do
        if [ -x "$candidate/ffmpeg" ] && [ -x "$candidate/cwebp" ]; then
            TOOLS_SRC="$candidate"
            break
        fi
    done
fi
if [ -n "$TOOLS_SRC" ] && [ -d "$TOOLS_SRC" ]; then
    echo "Bundling media tools…"
    mkdir -p "$APP/Contents/Resources/Tools"
    cp -R "$TOOLS_SRC/." "$APP/Contents/Resources/Tools/"
fi

if [ -d "Resources/Tools" ]; then
    mkdir -p "$APP/Contents/Resources/Tools"
    cp -R "Resources/Tools/." "$APP/Contents/Resources/Tools/"
fi

echo "Signing ad-hoc…"
codesign --force --deep --sign - "$APP"

echo "Built $APP"
