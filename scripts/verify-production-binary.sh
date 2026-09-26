#!/bin/bash
# Fails when an internal diagnostic command or response marker is present in a
# production executable. Source-level compile guards are the primary control;
# this is the independent release-artifact backstop.
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 <production-executable>" >&2
    exit 2
fi

EXECUTABLE="$1"
if [ ! -s "$EXECUTABLE" ]; then
    echo "ERROR: production executable is empty: $EXECUTABLE" >&2
    exit 2
fi

FORBIDDEN_SIGNATURES=(
    "XCTestCase"
    "XCTestConfigurationFilePath"
    "--render-marketing-preview"
    "--selftest-stt"
    "--selftest-stt-soak"
    "--selftest-stt-unified"
    "--selftest-vad"
    "--selftest-live-capture"
    "--selftest-capture-preflight"
    "--insert-text"
    "--insert-diagnostics"
    "--insert-from-home"
    "SELFTEST-ERROR:"
    "LIVE-CAPTURE:"
    "LIVE-TRANSCRIPT:"
    "MARKETING-PREVIEW:"
    "INSERT-ERROR:"
    "INSERTED:"
    "PREFLIGHT-ERROR:"
    "PREFLIGHT-OK:"
)

STRINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/lockedin-release-strings.XXXXXX")"
cleanup() {
    rm -f -- "$STRINGS_FILE"
}
trap cleanup EXIT

/usr/bin/strings -a "$EXECUTABLE" > "$STRINGS_FILE"
for signature in "${FORBIDDEN_SIGNATURES[@]}"; do
    if /usr/bin/grep -Fq -- "$signature" "$STRINGS_FILE"; then
        echo "ERROR: production executable contains internal diagnostic signature: $signature" >&2
        exit 1
    fi
done

echo "Production binary diagnostic gate passed."
