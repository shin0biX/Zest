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
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ship media tools when available so Finder-launched instances do not
# depend on a shell PATH. Set ZEST_TOOLS_SRC to pick a Tools directory
# explicitly; otherwise use the first app bundle that ships both binaries.
# A candidate must actually start: an expired or wrongly signed build can sit
# on disk and shadow the working Homebrew copy at runtime.
tool_runs() {
    [ -x "$1" ] || return 1
    # The inner shell keeps the "Trace/BPT trap" notice out of the build log
    # when a candidate dies on launch.
    sh -c '"$1" -version >/dev/null 2>&1 || exit 1' _ "$1" 2>/dev/null
}

TOOLS_SRC="${ZEST_TOOLS_SRC:-}"
if [ -z "$TOOLS_SRC" ]; then
    for candidate in /Applications/*.app/Contents/Resources/Tools; do
        if tool_runs "$candidate/ffmpeg" && tool_runs "$candidate/cwebp"; then
            TOOLS_SRC="$candidate"
            break
        fi
    done
fi
if [ -n "$TOOLS_SRC" ] && [ -d "$TOOLS_SRC" ]; then
    echo "Bundling media tools from ${TOOLS_SRC}…"
    mkdir -p "$APP/Contents/Resources/Tools"
    cp -R "$TOOLS_SRC/." "$APP/Contents/Resources/Tools/"
else
    echo "No working media tools found to bundle; falling back to Homebrew/PATH."
fi

if [ -d "Resources/Tools" ]; then
    mkdir -p "$APP/Contents/Resources/Tools"
    cp -R "Resources/Tools/." "$APP/Contents/Resources/Tools/"
fi

# Never ship a tool that cannot start: ToolFinder validates at runtime too,
# but a broken copy in the bundle is dead weight and confusing in About.
if [ -d "$APP/Contents/Resources/Tools" ]; then
    for binary in ffmpeg cwebp; do
        path="$APP/Contents/Resources/Tools/$binary"
        if [ -e "$path" ] && ! tool_runs "$path"; then
            echo "Removing unusable $binary from the bundle."
            rm -f "$path"
        fi
    done
    if [ -z "$(ls -A "$APP/Contents/Resources/Tools" 2>/dev/null)" ]; then
        rmdir "$APP/Contents/Resources/Tools"
    fi
fi

echo "Signing ad-hoc…"
codesign --force --deep --sign - "$APP"

echo "Built $APP"
