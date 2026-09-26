#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 1 ]; then
    echo "usage: scripts/validate-sbom.sh <SBOM.cdx.json>" >&2
    exit 64
fi
if ! JQ="$(command -v jq)"; then
    echo "SBOM validation requires jq." >&2
    exit 1
fi
"$JQ" -e -f "$ROOT/scripts/validate-sbom.jq" "$1" > /dev/null
echo "SBOM-VALID"
