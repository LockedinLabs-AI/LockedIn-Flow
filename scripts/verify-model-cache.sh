#!/bin/bash
set -euo pipefail

SELECTION="all"
VERIFY_MANAGED_PERMISSIONS=0
VERIFY_INSTALLED_MANAGED_TREE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --default|--all)
            SELECTION="${1#--}"
            shift
            ;;
        --managed)
            if [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ]; then
                echo "ERROR: --managed and --managed-installed are mutually exclusive." >&2
                exit 64
            fi
            VERIFY_MANAGED_PERMISSIONS=1
            shift
            ;;
        --managed-installed)
            if [ "$VERIFY_MANAGED_PERMISSIONS" -eq 1 ]; then
                echo "ERROR: --managed and --managed-installed are mutually exclusive." >&2
                exit 64
            fi
            VERIFY_INSTALLED_MANAGED_TREE=1
            shift
            ;;
        --help|-h)
            echo "Usage: scripts/verify-model-cache.sh [--default|--all] [--managed|--managed-installed] <Models directory>"
            echo "  --managed            Verify package-staging modes; ownership may remain with the build user."
            echo "  --managed-installed  Verify the installed root:wheel system tree, safe ancestors, and absence of extended ACL entries."
            exit 0
            ;;
        --*)
            echo "ERROR: unknown option: $1" >&2
            exit 64
            ;;
        *)
            break
            ;;
    esac
done
if [ "$#" -ne 1 ]; then
    echo "Usage: scripts/verify-model-cache.sh [--default|--all] [--managed|--managed-installed] <Models directory>" >&2
    exit 64
fi

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_CACHE_ROOT="$1"
MANIFEST="$REPOSITORY_ROOT/security/model-artifacts.tsv"
INSTALLED_MANAGED_ROOT="/Library/Application Support/LockedIn Flow/Models"
ACL_LIBRARY="$REPOSITORY_ROOT/scripts/lib/macos-acl.sh"

if [ ! -r "$ACL_LIBRARY" ]; then
    echo "ERROR: managed ACL verification support is unavailable." >&2
    exit 1
fi
# shellcheck source=scripts/lib/macos-acl.sh
source "$ACL_LIBRARY"

verify_installed_managed_ancestors() {
    if [ "$MODEL_CACHE_ROOT" != "$INSTALLED_MANAGED_ROOT" ]; then
        echo "ERROR: installed managed verification is restricted to $INSTALLED_MANAGED_ROOT" >&2
        exit 1
    fi

    local system_ancestors=(
        "/"
        "/Library"
        "/Library/Application Support"
    )
    local app_owned_ancestors=(
        "/Library/Application Support/LockedIn Flow"
        "$INSTALLED_MANAGED_ROOT"
    )
    local item ownership mode numeric_mode
    local owner_id group_id
    for item in "${system_ancestors[@]}"; do
        if [ -L "$item" ] || [ ! -d "$item" ]; then
            echo "ERROR: managed model ancestor must be a real directory: $item" >&2
            exit 1
        fi
        ownership="$(stat -f '%u:%g' "$item")"
        owner_id="${ownership%%:*}"
        if [ "$owner_id" != "0" ]; then
            echo "ERROR: managed model system ancestor must be root-owned: $item" >&2
            exit 1
        fi
        mode="$(stat -f '%Lp' "$item")"
        numeric_mode=$((8#$mode))
        if [ $((numeric_mode & 0022)) -ne 0 ]; then
            echo "ERROR: managed model ancestor must not be group- or world-writable: $item" >&2
            exit 1
        fi
        lockedin_require_no_extended_acl "$item"
    done

    for item in "${app_owned_ancestors[@]}"; do
        if [ -L "$item" ] || [ ! -d "$item" ]; then
            echo "ERROR: managed model ancestor must be a real directory: $item" >&2
            exit 1
        fi
        ownership="$(stat -f '%u:%g' "$item")"
        owner_id="${ownership%%:*}"
        group_id="${ownership##*:}"
        if [ "$owner_id" != "0" ] || [ "$group_id" != "0" ]; then
            echo "ERROR: application-owned model ancestor must be owned by root:wheel: $item" >&2
            exit 1
        fi
        mode="$(stat -f '%Lp' "$item")"
        if [ "$mode" != "755" ]; then
            echo "ERROR: application-owned model ancestor must have mode 0755: $item" >&2
            exit 1
        fi
        lockedin_require_no_extended_acl "$item"
    done
}

if [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ]; then
    verify_installed_managed_ancestors
fi

if [ -L "$MODEL_CACHE_ROOT" ] || [ ! -d "$MODEL_CACHE_ROOT" ]; then
    echo "ERROR: model cache directory does not exist: $MODEL_CACHE_ROOT" >&2
    exit 1
fi
if find "$MODEL_CACHE_ROOT" -type l -print -quit | grep -q .; then
    echo "ERROR: model cache contains a symbolic link." >&2
    exit 1
fi
if find "$MODEL_CACHE_ROOT" ! -type d ! -type f ! -type l -print -quit | grep -q .; then
    echo "ERROR: model cache contains a special file." >&2
    exit 1
fi

WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/lockedin-model-verify.XXXXXX")"
cleanup() {
    rm -rf -- "$WORK_DIRECTORY"
}
trap cleanup EXIT

EXPECTED_FILES="$WORK_DIRECTORY/expected-files"
ACTUAL_FILES="$WORK_DIRECTORY/actual-files"
: > "$EXPECTED_FILES"
EXPECTED_COUNT=0

while IFS=$'\t' read -r expected_hash expected_bytes relative_path; do
    case "$relative_path" in
        ""|/*|*..*|*\\*)
            echo "ERROR: unsafe path in reviewed model manifest." >&2
            exit 1
            ;;
    esac
    if [ "$SELECTION" = "default" ]; then
        case "$relative_path" in
            parakeet-tdt-0.6b-v3/*|silero-vad/*) ;;
            *) continue ;;
        esac
    fi
    artifact="$MODEL_CACHE_ROOT/$relative_path"
    if [ ! -f "$artifact" ]; then
        echo "ERROR: missing model artifact: $relative_path" >&2
        exit 1
    fi
    actual_bytes="$(stat -f %z "$artifact")"
    if [ "$actual_bytes" != "$expected_bytes" ]; then
        echo "ERROR: size mismatch: $relative_path" >&2
        exit 1
    fi
    actual_hash="$(shasum -a 256 "$artifact" | awk '{print $1}')"
    if [ "$actual_hash" != "$expected_hash" ]; then
        echo "ERROR: SHA-256 mismatch: $relative_path" >&2
        exit 1
    fi
    printf '%s\n' "$relative_path" >> "$EXPECTED_FILES"
    EXPECTED_COUNT=$((EXPECTED_COUNT + 1))
done < "$MANIFEST"

(
    cd "$MODEL_CACHE_ROOT"
    find . -type f -print | sed 's#^\./##' | LC_ALL=C sort
) > "$ACTUAL_FILES"
LC_ALL=C sort -o "$EXPECTED_FILES" "$EXPECTED_FILES"
if ! cmp -s "$EXPECTED_FILES" "$ACTUAL_FILES"; then
    echo "ERROR: model cache contains an unexpected file." >&2
    exit 1
fi

if [ "$VERIFY_MANAGED_PERMISSIONS" -eq 1 ] || [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ]; then
    while IFS= read -r -d '' directory; do
        if [ "$(stat -f '%Lp' "$directory")" != "755" ]; then
            echo "ERROR: managed model directory must have mode 0755: $directory" >&2
            exit 1
        fi
        if [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ] \
            && [ "$(stat -f '%u:%g' "$directory")" != "0:0" ]; then
            echo "ERROR: installed managed model directory must be owned by root:wheel: $directory" >&2
            exit 1
        fi
        if [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ]; then
            lockedin_require_no_extended_acl "$directory"
        fi
    done < <(find "$MODEL_CACHE_ROOT" -type d -print0)
    while IFS= read -r -d '' artifact; do
        if [ "$(stat -f '%Lp' "$artifact")" != "644" ]; then
            echo "ERROR: managed model artifact must have mode 0644: $artifact" >&2
            exit 1
        fi
        if [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ] \
            && [ "$(stat -f '%u:%g' "$artifact")" != "0:0" ]; then
            echo "ERROR: installed managed model artifact must be owned by root:wheel: $artifact" >&2
            exit 1
        fi
        if [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ]; then
            lockedin_require_no_extended_acl "$artifact"
        fi
    done < <(find "$MODEL_CACHE_ROOT" -type f -print0)
fi

PERMISSIONS_DESCRIPTION="content only"
if [ "$VERIFY_MANAGED_PERMISSIONS" -eq 1 ]; then
    PERMISSIONS_DESCRIPTION="managed staging 0755/0644 permissions"
elif [ "$VERIFY_INSTALLED_MANAGED_TREE" -eq 1 ]; then
    PERMISSIONS_DESCRIPTION="installed root:wheel managed tree with 0755/0644 permissions and no extended ACLs"
fi
echo "Verified $EXPECTED_COUNT pinned model artifacts ($SELECTION set; $PERMISSIONS_DESCRIPTION)."
