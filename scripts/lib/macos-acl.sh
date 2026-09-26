#!/bin/bash

# Reject every extended macOS ACL entry on the narrow system-managed model
# trust path. POSIX modes are not a complete authorization boundary when an
# allow ACL is present, and inherited deny entries can make deployment behavior
# unpredictable. User evaluation caches intentionally do not use this check.
lockedin_require_no_extended_acl() {
    if [ "$#" -eq 0 ]; then
        echo "ERROR: no managed trust-path item was provided for ACL verification." >&2
        return 64
    fi

    local item listing
    for item in "$@"; do
        if ! listing="$(LC_ALL=C /bin/ls -lde "$item" 2>&1)"; then
            echo "ERROR: could not inspect extended ACLs on managed trust-path item: $item" >&2
            return 1
        fi
        if printf '%s\n' "$listing" \
            | /usr/bin/awk '
                NR > 1 && /^[[:space:]]*[0-9]+:/ { found = 1 }
                END { exit(found ? 0 : 1) }
            '
        then
            echo "ERROR: managed trust-path item must not have extended ACL entries: $item" >&2
            return 1
        fi
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    lockedin_require_no_extended_acl "$@"
fi
