#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/swift "$ROOT/scripts/generate-sbom.swift" "$@"
