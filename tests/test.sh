#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "$expected" = "$actual" ] || fail "$label: expected '$expected', got '$actual'"
}

bash -n "$ROOT_DIR/vmutex"
bash -n "$ROOT_DIR/install.sh"

# The path is computed so the test also works outside a Git checkout.
# shellcheck disable=SC1091
source "$ROOT_DIR/vmutex"

assert_eq "1.0.0" "$VMUTEX_VERSION" "script version"
valid_release_tag "v1.2.3" || fail "valid release tag rejected"
if valid_release_tag "1.2.3"; then fail "tag without v accepted"; fi
if valid_release_tag "v1.2"; then fail "short tag accepted"; fi
version_is_newer "1.0.0" "1.0.1" || fail "new patch version not detected"
if version_is_newer "1.2.0" "1.1.9"; then fail "older version detected as newer"; fi
if version_is_newer "1.0.0" "1.0.0"; then fail "equal version detected as newer"; fi
valid_domain_suffix "example.com" || fail "valid domain rejected"
if valid_domain_suffix "5202323"; then fail "single-label domain accepted"; fi
if grep -q '5202323\.xyz' "$ROOT_DIR/vmutex" "$ROOT_DIR/install.sh"; then
    fail "private default domain remains in release scripts"
fi

assert_eq "1.0.0" "$(script_version "$ROOT_DIR/vmutex")" "version parser"
assert_eq "EchoLunar/vmutex" "$(repository_name)" "repository binding"

TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
# These variables are consumed by functions imported from vmutex above.
# shellcheck disable=SC2034
CONFIG_DIR="$TEST_TMP/etc-vmutex"
# shellcheck disable=SC2034
CONFIG_FILE="$CONFIG_DIR/config"
# shellcheck disable=SC2034
REPOSITORY_FILE="$CONFIG_DIR/repository"
# shellcheck disable=SC2034
INSTALL_PATH="$TEST_TMP/bin/vmutex"
# shellcheck disable=SC2034
BACKUP_DIR="$TEST_TMP/backups"
# shellcheck disable=SC2034
VMUTEX_TEST_MODE=1
mkdir -p "$(dirname "$INSTALL_PATH")" "$CONFIG_DIR"
cp "$ROOT_DIR/vmutex" "$INSTALL_PATH"
sed 's/readonly VMUTEX_VERSION="1.0.0"/readonly VMUTEX_VERSION="1.0.1"/' \
    "$ROOT_DIR/vmutex" > "$TEST_TMP/candidate"
(cd "$TEST_TMP" && sha256sum candidate | sed 's/  candidate$/  vmutex/' > vmutex.sha256)

CURL_SCENARIO=success
curl() {
    local output="" url="" argument
    while [ "$#" -gt 0 ]; do
        argument="$1"
        shift
        if [ "$argument" = "-o" ]; then
            output="$1"
            shift
        elif [[ "$argument" == https://* ]]; then
            url="$argument"
        fi
    done

    if [ "$CURL_SCENARIO" = "network" ]; then
        return 22
    fi
    case "$url" in
        */releases/latest)
            if [ "$CURL_SCENARIO" = "invalid-release" ]; then
                printf '{"tag_name":"latest"}\n' > "$output"
            elif [ "$CURL_SCENARIO" = "no-update" ]; then
                printf '{"tag_name":"v1.0.0"}\n' > "$output"
            else
                printf '{"tag_name":"v1.0.1"}\n' > "$output"
            fi
            ;;
        */vmutex.sha256)
            if [ "$CURL_SCENARIO" = "bad-checksum" ]; then
                printf '%064d  vmutex\n' 0 > "$output"
            else
                cp "$TEST_TMP/vmutex.sha256" "$output"
            fi
            ;;
        */vmutex) cp "$TEST_TMP/candidate" "$output" ;;
        *) return 22 ;;
    esac
}

original_hash=$(sha256sum "$INSTALL_PATH" | cut -d' ' -f1)
CURL_SCENARIO=network
if update_vmutex true >/dev/null 2>&1; then fail "network failure reported success"; fi
assert_eq "$original_hash" "$(sha256sum "$INSTALL_PATH" | cut -d' ' -f1)" "network failure preservation"

CURL_SCENARIO=invalid-release
if update_vmutex true >/dev/null 2>&1; then fail "invalid release reported success"; fi
assert_eq "$original_hash" "$(sha256sum "$INSTALL_PATH" | cut -d' ' -f1)" "invalid release preservation"

CURL_SCENARIO=bad-checksum
if update_vmutex true >/dev/null 2>&1; then fail "bad checksum reported success"; fi
assert_eq "$original_hash" "$(sha256sum "$INSTALL_PATH" | cut -d' ' -f1)" "checksum failure preservation"

CURL_SCENARIO=no-update
update_vmutex true >/dev/null
assert_eq "$original_hash" "$(sha256sum "$INSTALL_PATH" | cut -d' ' -f1)" "no-update preservation"

CURL_SCENARIO=success
update_vmutex true >/dev/null
assert_eq "1.0.1" "$(script_version "$INSTALL_PATH")" "successful update"
test -n "$(find "$BACKUP_DIR" -maxdepth 1 -type f -print -quit)" || fail "update backup missing"

echo "All VMUTEX tests passed."
