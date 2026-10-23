#!/bin/zsh
# Build and run the external Finder drag harness.
#   ./Harness/run.sh            every scenario
#   ./Harness/run.sh basic      one scenario
#   ./Harness/run.sh all --keep-running   reuse a running Zest
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/harness
swiftc -O Harness/dragtest.swift -o .build/harness/dragtest \
  -framework AppKit -framework ApplicationServices -framework PDFKit -framework ImageIO
exec .build/harness/dragtest "$@"
