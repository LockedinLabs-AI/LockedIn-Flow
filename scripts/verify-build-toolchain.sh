#!/bin/bash
set -euo pipefail

EXPECTED_XCODE_VERSION="26.6"
EXPECTED_XCODE_BUILD="17F113"
EXPECTED_SWIFT_VERSION="6.3.3"
EXPECTED_MACOS_SDK_VERSION="26.5"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

xcode_version="$(xcodebuild -version)"
xcode_name="$(printf '%s\n' "$xcode_version" | sed -n '1p')"
xcode_build="$(printf '%s\n' "$xcode_version" | sed -n '2p')"
[ "$xcode_name" = "Xcode $EXPECTED_XCODE_VERSION" ] \
    || fail "expected Xcode $EXPECTED_XCODE_VERSION, found ${xcode_name:-unknown}."
[ "$xcode_build" = "Build version $EXPECTED_XCODE_BUILD" ] \
    || fail "expected Xcode build $EXPECTED_XCODE_BUILD, found ${xcode_build:-unknown}."

swift_version="$(swift --version 2>&1)"
printf '%s\n' "$swift_version" \
    | grep -Eq "Apple Swift version ${EXPECTED_SWIFT_VERSION//./\\.}([[:space:]]|$)" \
    || fail "expected Apple Swift $EXPECTED_SWIFT_VERSION; swift --version reported a different toolchain."

sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
[ "$sdk_version" = "$EXPECTED_MACOS_SDK_VERSION" ] \
    || fail "expected macOS SDK $EXPECTED_MACOS_SDK_VERSION, found ${sdk_version:-unknown}."

echo "Verified release toolchain: Xcode $EXPECTED_XCODE_VERSION ($EXPECTED_XCODE_BUILD), Apple Swift $EXPECTED_SWIFT_VERSION, macOS SDK $EXPECTED_MACOS_SDK_VERSION."
