#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ROOT/Tests/Fixtures/SBOM"
EXPECTED="$FIXTURE/expected.cdx.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lockedin-sbom-test.XXXXXX")"
cleanup() {
    rm -rf -- "$WORK"
}
trap cleanup EXIT

fail() {
    echo "SBOM TEST FAIL: $1" >&2
    exit 1
}

SOURCE_REVISION="1111111111111111111111111111111111111111"
COMMON_ARGS=(
    --root "$FIXTURE"
    --source-revision "$SOURCE_REVISION"
    --source-state clean
)

"$ROOT/scripts/generate-sbom.sh" "${COMMON_ARGS[@]}" --output "$WORK/first.cdx.json" > /dev/null
"$ROOT/scripts/generate-sbom.sh" "${COMMON_ARGS[@]}" --output "$WORK/second.cdx.json" > /dev/null
cmp -s "$WORK/first.cdx.json" "$WORK/second.cdx.json" \
    || fail "identical evidence did not produce byte-identical output"
cmp -s "$EXPECTED" "$WORK/first.cdx.json" \
    || fail "generated fixture differs from reviewed expected SBOM"
"$ROOT/scripts/validate-sbom.sh" "$WORK/first.cdx.json" > /dev/null

# The checked-in local profile is itself machine-readable JSON. The jq gate
# implements its cross-reference and safety assertions without adding a new
# package-manager dependency to the release toolchain.
jq -e '.title == "LockedIn Flow CycloneDX 1.6 build SBOM profile"' \
    "$ROOT/security/sbom-profile.schema.json" > /dev/null \
    || fail "local SBOM profile schema is invalid"

# A new Package.resolved pin must fail closed until a reviewed inventory entry
# is added. This prevents dependency upgrades from silently disappearing from
# the generated SBOM.
cp -R "$FIXTURE/." "$WORK/unknown-fixture"
jq '.pins += [{
    "identity": "unknown",
    "kind": "remoteSourceControl",
    "location": "https://github.com/example/Unknown.git",
    "state": {
      "revision": "cccccccccccccccccccccccccccccccccccccccc",
      "version": "9.9.9"
    }
  }]' "$FIXTURE/Package.resolved" > "$WORK/unknown-fixture/Package.resolved"
if "$ROOT/scripts/generate-sbom.sh" \
    --root "$WORK/unknown-fixture" \
    --output "$WORK/unknown.cdx.json" \
    --source-revision "$SOURCE_REVISION" \
    --source-state clean > "$WORK/unknown.stdout" 2> "$WORK/unknown.stderr"; then
    fail "generator accepted an uninventoryed Swift package"
fi
grep -Fq 'Package.resolved contains uninventoryed Swift package: unknown' \
    "$WORK/unknown.stderr" \
    || fail "unknown dependency failure was not explicit"
if grep -Fq "$WORK" "$WORK/unknown.stderr"; then
    fail "generator error exposed a local test path"
fi

echo "5 SBOM generation and validation tests passed."
