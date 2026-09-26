#!/bin/bash
# Source-level regression gate for the application network boundary. This is not
# a substitute for endpoint firewall enforcement or binary security review.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
    echo "RUNTIME NETWORK POLICY FAIL: $1" >&2
    exit 1
}

swift_tree_matches() {
    local root="$1"
    local pattern="$2"
    local matched=1
    local path

    while IFS= read -r -d '' path; do
        if /usr/bin/grep -EHn "$pattern" "$path"; then
            matched=0
        fi
    done < <(find "$root" -type f -name '*.swift' -print0)

    return "$matched"
}

if swift_tree_matches Sources \
    'URLSession|URLRequest|URLProtocol|NWListener|NWConnection|CFSocket|CFStreamCreatePairWithSocket|socket[[:space:]]*\(|import[[:space:]]+Network'; then
    fail "application source contains a direct networking primitive"
fi

/usr/bin/grep -Fq 'ModelHub.offlineMode = true' Sources/SpeechEngine/SpeechModels.swift \
    || fail "FluidAudio model hub is not forced offline"

if swift_tree_matches Sources/LockedInFlowApp \
    'Downloading speech model|Download / Load Now|Models download once|one-time model download'; then
    fail "application UI still promises runtime model acquisition"
fi

for entitlement in com.apple.security.network.client com.apple.security.network.server; do
    if /usr/libexec/PlistBuddy -c "Print :$entitlement" entitlements.plist >/dev/null 2>&1; then
        fail "application entitlements contain $entitlement"
    fi
done

echo "Runtime network source policy passed."
