#!/bin/bash
# generate_xcode_project.sh
# Thin wrapper — use `make generate` directly for full control.
#
# Usage: ./generate_xcode_project.sh
# Requirements: brew install xcodegen

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v xcodegen &> /dev/null; then
    echo "xcodegen not found. Install it with: brew install xcodegen"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/CortexOSApp/local.yml" ]; then
    echo "Missing CortexOSApp/local.yml — copy the example and set your DEVELOPMENT_TEAM:"
    echo "  cp CortexOSApp/local.yml.example CortexOSApp/local.yml"
    exit 1
fi

cd "$SCRIPT_DIR"
make generate
echo ""
echo "Open with: open CortexOSApp/CortexOS.xcodeproj"
