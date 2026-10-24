#!/bin/zsh
# Build and run the external Finder drag harness.
#   ./Harness/run.sh            every scenario
#   ./Harness/run.sh basic      one scenario
#   ./Harness/run.sh all --keep-running   reuse a running Zest
set -euo pipefail

# The app only writes drag-trace log lines (Wheel/Choice/Drag) when this flag
# is set; release builds are quiet by default. Enable for the run, restore on exit.
defaults write com.zest.app verboseLog -bool true
trap 'defaults delete com.zest.app verboseLog 2>/dev/null' EXIT
cd "$(dirname "$0")/.."
mkdir -p .build/harness
swiftc -O Harness/dragtest.swift -o .build/harness/dragtest \
  -framework AppKit -framework ApplicationServices -framework PDFKit -framework ImageIO
# No exec: the EXIT trap that restores quiet logging must survive the run.
.build/harness/dragtest "$@"
