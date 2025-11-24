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
    assert_contains "$out" "no passphrase" "reports missing passphrase"
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
    assert_contains "$out" "duplicate keys (1 distinct)" "finds the duplicate"
}

test_flags_unhashed_known_hosts() {
    d="$WORK/kh"
    mkdir -p "$d" && chmod 700 "$d"
    echo 'example.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyATestKeyOne' > "$d/known_hosts"
    assert_status 1 "plain host name is reported" "$ROOT/bin/ssh-audit.sh" -d "$d"
    echo '|1|c2FsdA==|aGFzaA== ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyATestKeyOne' > "$d/known_hosts"
    assert_status 0 "hashed host name is fine" "$ROOT/bin/ssh-audit.sh" -d "$d"
}

test_hosts_file_against_known_hosts() {
    d="$WORK/hosts"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t ed25519 -N '' -f "$WORK/hostkey"
    printf 'seen.example.org %s\n' "$(cut -d' ' -f1,2 "$WORK/hostkey.pub")" > "$d/known_hosts"
    ssh-keygen -q -H -f "$d/known_hosts" >/dev/null 2>&1; rm -f "$d/known_hosts.old"
    printf '# expected\nseen.example.org\nnew.example.org\n' > "$WORK/hostlist"
    out=$("$ROOT/bin/ssh-audit.sh" -d "$d" -H "$WORK/hostlist" || true)
    assert_eq "new.example.org: not found in $d/known_hosts" "$out" "only the unseen host is reported"
}

test_hosts_file_with_windows_line_endings() {
    d="$WORK/hostscrlf"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t ed25519 -N '' -f "$WORK/hostkey2"
    printf 'seen.example.org %s\n' "$(cut -d' ' -f1,2 "$WORK/hostkey2.pub")" > "$d/known_hosts"
    ssh-keygen -q -H -f "$d/known_hosts" >/dev/null 2>&1; rm -f "$d/known_hosts.old"
    printf 'seen.example.org\r\n' > "$WORK/hostlist2"
    assert_status 0 "host name without a trailing CR is found" "$ROOT/bin/ssh-audit.sh" -d "$d" -H "$WORK/hostlist2"
}

test_flags_writable_config_files() {
    d="$WORK/writable"
    mkdir -p "$d" && chmod 700 "$d"
    echo "Host *" > "$d/config"
    echo "# nothing" > "$d/authorized_keys"
    chmod 644 "$d/config" "$d/authorized_keys"
    assert_status 0 "644 is fine" "$ROOT/bin/ssh-audit.sh" -d "$d"
    chmod 664 "$d/config"
    chmod 666 "$d/authorized_keys"
    out=$("$ROOT/bin/ssh-audit.sh" -d "$d" || true)
    assert_contains "$out" "$d/config: is writable" "group-writable config"
    assert_contains "$out" "$d/authorized_keys: is writable" "world-writable authorized_keys"
}

test_verbose_lists_fingerprints() {
    d="$WORK/verbose"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t ed25519 -N 'pass phrase' -f "$d/id_ed25519"
    out=$("$ROOT/bin/ssh-audit.sh" -v -d "$d")
    case $out in
        "$d/id_ed25519: ED25519 256 SHA256:"*) assert_eq 1 1 "inventory line" ;;
        *) assert_eq "ED25519 256 SHA256:..." "$out" "inventory line" ;;
    esac
}

test_strict_flags_rsa_2048() {
    d="$WORK/strict"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t rsa -b 2048 -N 'pass phrase' -f "$d/id_rsa"
    assert_status 0 "2048-bit RSA passes by default" "$ROOT/bin/ssh-audit.sh" -d "$d"
    assert_status 1 "2048-bit RSA fails with -s" "$ROOT/bin/ssh-audit.sh" -s -d "$d"
}

test_json_output() {
    d="$WORK/json"
    mkdir -p "$d" && chmod 700 "$d"
    ssh-keygen -q -t ed25519 -N '' -f "$d/id_ed25519"
    out=$("$ROOT/bin/ssh-audit.sh" -j -v -d "$d" || true)
    case $out in
        '{"directory":"'"$d"'","findings":[{"path":"'"$d"'/id_ed25519","message":"private key has no passphrase"}],"keys":[{"path":"'"$d"'/id_ed25519","type":"ED25519","bits":256,"fingerprint":"SHA256:'*'"}]}')
            assert_eq 1 1 "findings and keys in one document" ;;
        *) assert_eq "one JSON document" "$out" "findings and keys in one document" ;;
    esac
    assert_status 1 "exit status still reflects the findings" "$ROOT/bin/ssh-audit.sh" -j -d "$d"
    ssh-keygen -q -p -N 'new pass phrase' -f "$d/id_ed25519" >/dev/null
    out=$("$ROOT/bin/ssh-audit.sh" -j -d "$d")
    assert_eq '{"directory":"'"$d"'","findings":[],"keys":[]}' "$out" "clean directory gives empty arrays"
}

run_tests
