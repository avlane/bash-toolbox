#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/restore-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

RS="$ROOT/bin/restore-backup.sh"

# a real archive from backup.sh
mkdir -p "$WORK/src/proj/sub"
echo hello > "$WORK/src/proj/sub/file.txt"
archive=$("$ROOT/bin/backup.sh" "$WORK/src/proj" "$WORK/bk" | sed 's/^wrote //')

test_restores_files() {
    "$RS" "$archive" "$WORK/out1" >/dev/null 2>&1
    assert_eq "hello" "$(cat "$WORK/out1/proj/sub/file.txt")" "file content restored"
}

test_list_only() {
    out=$("$RS" -l "$archive" "$WORK/out2" 2>/dev/null)
    case $out in *proj/sub/file.txt*) assert_eq 1 1 "listing mentions the file" ;; *) assert_eq "proj/sub/file.txt" "$out" "listing mentions the file" ;; esac
    assert_eq "no" "$([ -e "$WORK/out2" ] && echo yes || echo no)" "nothing extracted"
}

test_corrupt_archive_is_refused() {
    cp "$archive" "$WORK/bad.tar.gz"
    cp "$archive.sha256" "$WORK/bad.tar.gz.sha256"
    sed -i.bak "s/  .*/  bad.tar.gz/" "$WORK/bad.tar.gz.sha256"
    echo junk >> "$WORK/bad.tar.gz"
    assert_status 1 "checksum mismatch" "$RS" "$WORK/bad.tar.gz" "$WORK/out3"
}

test_non_empty_destination() {
    mkdir -p "$WORK/out4"; echo x > "$WORK/out4/existing"
    assert_status 1 "refuses a non-empty directory" "$RS" "$archive" "$WORK/out4"
    assert_status 0 "-f overrides" "$RS" -f "$archive" "$WORK/out4"
}

test_absolute_paths_are_refused() {
    echo evil > "$WORK/abs.txt"
    tar -czPf "$WORK/abs.tar.gz" "$WORK/abs.txt" 2>/dev/null
    assert_status 1 "absolute entry" "$RS" "$WORK/abs.tar.gz" "$WORK/out5"
    assert_eq "no" "$([ -e "$WORK/out5" ] && echo yes || echo no)" "nothing extracted"
}

test_parent_directory_entries_are_refused() {
    mkdir -p "$WORK/trav/inner"
    echo evil > "$WORK/trav/outside.txt"
    (cd "$WORK/trav/inner" && tar -czPf "$WORK/trav.tar.gz" ../outside.txt)
    assert_status 1 "entry that climbs out of the target" "$RS" "$WORK/trav.tar.gz" "$WORK/out6"
    assert_eq "no" "$([ -e "$WORK/out6" ] && echo yes || echo no)" "nothing extracted"
}

test_dotdot_inside_a_name_is_fine() {
    mkdir -p "$WORK/dd/proj"
    echo ok > "$WORK/dd/proj/file..txt"
    (cd "$WORK/dd" && tar -czf "$WORK/dd.tar.gz" proj)
    assert_status 0 "file..txt is not a traversal" "$RS" "$WORK/dd.tar.gz" "$WORK/out7"
}

test_restores_zstd_archive() {
    command -v zstd >/dev/null || { skip "zstd is not installed"; return 0; }
    zarchive=$("$ROOT/bin/backup.sh" -z zstd "$WORK/src/proj" "$WORK/zbk" | sed 's/^wrote //')
    "$RS" "$zarchive" "$WORK/zout" >/dev/null 2>&1
    assert_eq "hello" "$(cat "$WORK/zout/proj/sub/file.txt")" "zstd archive restored"
}

test_unknown_extension() {
    echo x > "$WORK/odd.zip"
    assert_status 1 "unknown archive type" "$RS" "$WORK/odd.zip" "$WORK/out8"
}

run_tests
