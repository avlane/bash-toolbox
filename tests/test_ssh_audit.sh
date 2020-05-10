#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ssh-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

command -v ssh-keygen >/dev/null || { echo "ssh-keygen not found, skipping"; exit 0; }

test_clean_directory_passes() {
    d="$WORK/clean"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t ed25519 -N 'a passphrase' -f "$d/id_ed25519"
    assert_status 0 "protected key with passphrase is clean" "$ROOT/bin/ssh-audit.sh" -d "$d"
}

test_flags_missing_passphrase() {
    d="$WORK/nopass"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t ed25519 -N '' -f "$d/id_ed25519"
    out=$("$ROOT/bin/ssh-audit.sh" -d "$d" || true)
    case $out in
        *"no passphrase"*) assert_eq 1 1 "reports missing passphrase" ;;
        *) assert_eq "a finding" "$out" "reports missing passphrase" ;;
    esac
}

test_flags_loose_permissions() {
    d="$WORK/loose"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t ed25519 -N 'x y z' -f "$d/id_ed25519"
    chmod 644 "$d/id_ed25519"
    assert_status 1 "world-readable key fails the audit" "$ROOT/bin/ssh-audit.sh" -d "$d"
}

test_missing_directory() {
    assert_status 1 "missing directory" "$ROOT/bin/ssh-audit.sh" -d "$WORK/nope"
}

test_flags_duplicate_authorized_keys() {
    d="$WORK/dups"
    mkdir -p "$d" && chmod 700 "$d"
    printf '%s\n' \
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyATestKeyOne user@a' \
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyATestKeyOne user@b' \
        'from="10.0.0.0/8" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherKey other@c' > "$d/authorized_keys"
    out=$("$ROOT/bin/ssh-audit.sh" -d "$d" || true)
    case $out in
        *"duplicate keys (1 distinct)"*) assert_eq 1 1 "finds the duplicate" ;;
        *) assert_eq "duplicate keys (1 distinct)" "$out" "finds the duplicate" ;;
    esac
}

test_flags_unhashed_known_hosts() {
    d="$WORK/kh"
    mkdir -p "$d" && chmod 700 "$d"
    echo 'example.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyATestKeyOne' > "$d/known_hosts"
    assert_status 1 "plain host name is reported" "$ROOT/bin/ssh-audit.sh" -d "$d"
    echo '|1|c2FsdA==|aGFzaA== ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyATestKeyOne' > "$d/known_hosts"
    assert_status 0 "hashed host name is fine" "$ROOT/bin/ssh-audit.sh" -d "$d"
}

run_tests
