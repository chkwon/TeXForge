#!/bin/bash
# Build TeXForge from the command line
# Usage: ./build.sh [Debug|Release]

CONFIG="${1:-Debug}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$PROJECT_DIR/build/$CONFIG/TeXForge.app"

echo "Building TeXForge ($CONFIG)..."

# xcodebuild will fail at the final CodeSign step because macOS auto-sets
# FinderInfo on .nib/.rtfd package directories. We let it fail, then strip
# extended attributes and re-sign manually below.
xcodebuild -project "$PROJECT_DIR/TeXForge.xcodeproj" \
    -scheme TeXForge \
    -configuration "$CONFIG" \
    build \
    SYMROOT="$PROJECT_DIR/build" \
    2>&1 | grep -E '(^CompileC|^Ld |^CodeSign |error:|BUILD)' || true

if [ ! -f "$APP/Contents/MacOS/TeXForge" ]; then
    echo "ERROR: Compilation failed - binary not found"
    exit 1
fi

# Strip ALL extended attributes, then re-sign everything.
# macOS auto-sets FinderInfo on package directories (.nib, .rtfd, .app)
# which blocks code signing. xattr -rc clears them all.
xattr -rc "$APP"

# Re-sign with --deep (signs all nested code in one pass)
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/TeXForge.entitlements" \
    "$APP"

codesign --verify --deep "$APP"
echo "Build successful: $APP"
