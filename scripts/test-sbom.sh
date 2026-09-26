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
FIXED_ID="urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79"

"$ROOT/scripts/generate-sbom.sh" "${COMMON_ARGS[@]}" --serial-number "$FIXED_ID" --output "$WORK/first.cdx.json" > /dev/null
"$ROOT/scripts/generate-sbom.sh" "${COMMON_ARGS[@]}" --serial-number "$FIXED_ID" --output "$WORK/second.cdx.json" > /dev/null
cmp -s "$WORK/first.cdx.json" "$WORK/second.cdx.json" \
    || fail "identical evidence and serial number did not produce byte-identical output"
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

# GitHub's pinned attestation action requires serialNumber to identify a
# CycloneDX document. Validate this contract before artifacts leave the build job.
"$ROOT/scripts/generate-sbom.sh" "${COMMON_ARGS[@]}" --output "$WORK/fresh-one.cdx.json" > /dev/null
"$ROOT/scripts/generate-sbom.sh" "${COMMON_ARGS[@]}" --output "$WORK/fresh-two.cdx.json" > /dev/null
"$ROOT/scripts/validate-sbom.sh" "$WORK/fresh-one.cdx.json" > /dev/null
"$ROOT/scripts/validate-sbom.sh" "$WORK/fresh-two.cdx.json" > /dev/null
test "$(jq -r '.serialNumber' "$WORK/fresh-one.cdx.json")" != "$(jq -r '.serialNumber' "$WORK/fresh-two.cdx.json")" \
    || fail "new documents reused a serial number"

for mutation in \
    'del(.serialNumber)' \
    '.serialNumber = ""' \
    '.serialNumber = "not-a-uuid"' \
    '.serialNumber = "urn:uuid:3e671687-395b-41f5-c30f-a58921a69b79"' \
    '.serialNumber = "urn:uuid:3e671687-395b-01f5-a30f-a58921a69b79"'; do
    jq "$mutation" "$EXPECTED" > "$WORK/invalid.cdx.json"
    if "$ROOT/scripts/validate-sbom.sh" "$WORK/invalid.cdx.json" > /dev/null 2>&1; then
        fail "validator accepted a missing or malformed document identity"
    fi
done
if "$ROOT/scripts/generate-sbom.sh" "${COMMON_ARGS[@]}" \
    --serial-number invalid --output "$WORK/rejected.cdx.json" > /dev/null 2>&1; then
    fail "generator accepted a malformed explicit document identity"
fi

echo "12 SBOM generation and validation tests passed."
