#!/bin/bash
# Build TeXForge from the command line
# Usage: ./build.sh [Debug|Release]

CONFIG="${1:-Debug}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$PROJECT_DIR/build/$CONFIG/TeXForge.app"
MARKETING_VERSION_OVERRIDE="${TEXFORGE_MARKETING_VERSION:-}"
CURRENT_PROJECT_VERSION_OVERRIDE="${TEXFORGE_CURRENT_PROJECT_VERSION:-}"
ARCHS_OVERRIDE="${TEXFORGE_ARCHS:-}"

echo "Building TeXForge ($CONFIG)..."

XCODEBUILD_ARGS=(
    -project "$PROJECT_DIR/TeXForge.xcodeproj"
    -scheme TeXForge
    -configuration "$CONFIG"
    build
    SYMROOT="$PROJECT_DIR/build"
)

if [ -n "$MARKETING_VERSION_OVERRIDE" ]; then
    XCODEBUILD_ARGS+=(MARKETING_VERSION="$MARKETING_VERSION_OVERRIDE")
fi

if [ -n "$CURRENT_PROJECT_VERSION_OVERRIDE" ]; then
    XCODEBUILD_ARGS+=(CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION_OVERRIDE")
fi

if [ -n "$ARCHS_OVERRIDE" ]; then
    XCODEBUILD_ARGS+=(ARCHS="$ARCHS_OVERRIDE")
fi

rm -rf "$APP"

# xcodebuild will fail at the final CodeSign step because macOS auto-sets
# FinderInfo on .nib/.rtfd package directories. We let it fail, then strip
# extended attributes and re-sign manually below.
xcodebuild "${XCODEBUILD_ARGS[@]}" 2>&1 | grep -E '(^CompileC|^Ld |^CodeSign |error:|BUILD)' || true

if [ ! -f "$APP/Contents/MacOS/TeXForge" ]; then
    echo "ERROR: Compilation failed - binary not found"
    exit 1
fi

SIGN_IDENTITY="${TEXFORGE_SIGN_IDENTITY:--}"
ENTITLEMENTS="$PROJECT_DIR/TeXForge.entitlements"

CODESIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then
    CODESIGN_FLAGS+=(--options runtime --timestamp)
fi

# When using Developer ID, stage the bundle under $TMPDIR for signing.
# macOS Launch Services continuously re-attaches com.apple.FinderInfo to .app
# packages in the user's home directory, racing against codesign --timestamp
# (which is slow because it hits Apple's TSA). /tmp is not subject to this
# auto-tagging, so signing there is reliable. For ad-hoc we keep signing in
# place because it's fast enough to win the race.
if [ "$SIGN_IDENTITY" = "-" ]; then
    SIGN_TARGET="$APP"
else
    STAGE_DIR="$(mktemp -d)"
    SIGN_TARGET="$STAGE_DIR/TeXForge.app"
    ditto --noextattr "$APP" "$SIGN_TARGET"
fi

# Strip ALL extended attributes, then re-sign everything.
# macOS auto-sets FinderInfo on package directories (.nib, .rtfd, .app)
# which blocks code signing. xattr -rc clears them all.
xattr -rc "$SIGN_TARGET"

# Sign each nested signable item explicitly, leaves first. We avoid --deep
# because (a) it silently skips apps inside Resources/ such as ScriptRunner.app
# and (b) it carries forward stale entitlements on prebuilt helpers
# (ScriptRunner ships with com.apple.security.get-task-allow=true which Apple's
# notary service rejects). Explicit signing replaces those entitlements.
codesign "${CODESIGN_FLAGS[@]}" --entitlements "$ENTITLEMENTS" \
    "$SIGN_TARGET/Contents/Frameworks/OgreKit.framework"
codesign "${CODESIGN_FLAGS[@]}" --entitlements "$ENTITLEMENTS" \
    "$SIGN_TARGET/Contents/Library/Spotlight/TeX.mdimporter"
codesign "${CODESIGN_FLAGS[@]}" --entitlements "$ENTITLEMENTS" \
    "$SIGN_TARGET/Contents/Resources/ScriptRunner.app"

# macOS re-attaches FinderInfo to package directories whenever codesign
# touches them, so strip xattrs again before signing the outer bundle.
xattr -rc "$SIGN_TARGET"

codesign "${CODESIGN_FLAGS[@]}" --entitlements "$ENTITLEMENTS" "$SIGN_TARGET"

# Remove provenance attr that macOS adds to locally-built apps
# (can cause "can't be opened" dialog via LaunchServices)
xattr -dr com.apple.provenance "$SIGN_TARGET" 2>/dev/null

codesign --verify --deep --strict "$SIGN_TARGET"

# Optional notarize + staple. Triggered when either a stored notarytool
# keychain profile (TEXFORGE_NOTARY_PROFILE) or App Store Connect API key
# triple (TEXFORGE_NOTARY_API_KEY_PATH/_ID/_ISSUER_ID) is provided.
if [ -n "$TEXFORGE_NOTARY_PROFILE" ] || [ -n "$TEXFORGE_NOTARY_API_KEY_PATH" ]; then
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "ERROR: notarization requires TEXFORGE_SIGN_IDENTITY (Developer ID)"
        exit 1
    fi

    NOTARY_DIR="$(mktemp -d)"
    NOTARY_ZIP="$NOTARY_DIR/TeXForge.zip"
    ditto -c -k --sequesterRsrc --keepParent "$SIGN_TARGET" "$NOTARY_ZIP"

    if [ -n "$TEXFORGE_NOTARY_PROFILE" ]; then
        xcrun notarytool submit "$NOTARY_ZIP" \
            --keychain-profile "$TEXFORGE_NOTARY_PROFILE" \
            --wait
    else
        xcrun notarytool submit "$NOTARY_ZIP" \
            --key      "$TEXFORGE_NOTARY_API_KEY_PATH" \
            --key-id   "$TEXFORGE_NOTARY_API_KEY_ID" \
            --issuer   "$TEXFORGE_NOTARY_API_ISSUER_ID" \
            --wait
    fi

    xcrun stapler staple "$SIGN_TARGET"
    spctl --assess --type execute --verbose=2 "$SIGN_TARGET" || true
    rm -rf "$NOTARY_DIR"
fi

# If we staged the bundle for signing, replace the in-tree copy with the
# signed/stapled one. macOS may re-attach FinderInfo to the destination
# afterwards, but signatures and the stapled ticket are stored inside the
# bundle (not in xattrs), so distribution ZIPs of $APP remain valid.
if [ "$SIGN_TARGET" != "$APP" ]; then
    rm -rf "$APP"
    ditto --noextattr "$SIGN_TARGET" "$APP"
    rm -rf "$STAGE_DIR"
fi

echo "Build successful: $APP"
