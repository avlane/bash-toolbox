#!/bin/bash
. "`dirname "$0"`/harness.sh"

ROOT=`cd "\`dirname "$0"\`/.." && pwd`
WORK=`mktemp -d "${TMPDIR:-/tmp}/backup-test.XXXXXX"`
trap 'rm -rf "$WORK"' EXIT

test_creates_archive() {
    mkdir -p "$WORK/src/data"
    echo one > "$WORK/src/data/one.txt"
    out=`"$ROOT/bin/backup.sh" "$WORK/src/data" "$WORK/dest"`
    archive=`echo "$out" | sed 's/^wrote //'`
    assert_file_exists "$archive" "archive exists"
    assert_eq "data/one.txt" "`tar -tzf "$archive" | grep one.txt`" "archive lists the file"
}

test_writes_a_checksum_that_verifies() {
    mkdir -p "$WORK/cs/proj"
    echo data > "$WORK/cs/proj/f"
    out=$("$ROOT/bin/backup.sh" "$WORK/cs/proj" "$WORK/csdest")
    archive=${out#wrote }
    assert_file_exists "$archive.sha256" "checksum file written"
    . "$ROOT/lib/common.sh"
    assert_status 0 "checksum verifies" tb_sha256_verify "$archive.sha256"
    echo corrupt >> "$archive"
    assert_status 1 "corruption is detected" tb_sha256_verify "$archive.sha256"
}

test_prune_removes_checksum_too() {
    mkdir -p "$WORK/pc/proj" "$WORK/pcdest"
    touch -t 201901010000 "$WORK/pcdest/proj-20190101-000000.tar.gz" "$WORK/pcdest/proj-20190101-000000.tar.gz.sha256"
    "$ROOT/bin/backup.sh" -k 1 "$WORK/pc/proj" "$WORK/pcdest" >/dev/null
    assert_eq "2" "$(ls "$WORK/pcdest" | wc -l | tr -d ' ')" "only the new archive and its checksum remain"
}

test_dot_as_source() {
    mkdir -p "$WORK/dot/proj"
    echo data > "$WORK/dot/proj/f"
    out=$(cd "$WORK/dot/proj" && "$ROOT/bin/backup.sh" . "$WORK/dotdest")
    archive=${out#wrote }
    case $(basename "$archive") in
        proj-*.tar.gz) assert_eq 1 1 "archive is named after the directory, not after '.'" ;;
        *) assert_eq "proj-*.tar.gz" "$(basename "$archive")" "archive is named after the directory, not after '.'" ;;
    esac
    assert_eq "proj/f" "$(tar -tzf "$archive" | grep -v '/$')" "contents are under the directory name"
}

test_relative_parent_as_source() {
    mkdir -p "$WORK/rel/proj" "$WORK/rel/other"
    echo data > "$WORK/rel/proj/f"
    out=$(cd "$WORK/rel/other" && "$ROOT/bin/backup.sh" ../proj "$WORK/reldest")
    case $(basename "${out#wrote }") in
        proj-*.tar.gz) assert_eq 1 1 "../proj is archived as proj" ;;
        *) assert_eq "proj-*.tar.gz" "$out" "../proj is archived as proj" ;;
    esac
}

test_missing_source_fails() {
    assert_status 1 "missing source dir" "$ROOT/bin/backup.sh" "$WORK/nope" "$WORK/dest"
}

test_usage() {
    assert_status 2 "wrong arg count" "$ROOT/bin/backup.sh" onlyone
}

test_exclude_pattern() {
    mkdir -p "$WORK/ex/proj"
    echo keep > "$WORK/ex/proj/keep.txt"
    echo skip > "$WORK/ex/proj/skip.log"
    out=$("$ROOT/bin/backup.sh" -x '*.log' "$WORK/ex/proj" "$WORK/exdest")
    archive=${out#wrote }
    assert_eq "proj/keep.txt" "$(tar -tzf "$archive" | grep -v '/$')" "only keep.txt archived"
}

test_exclude_from_file() {
    mkdir -p "$WORK/xf/proj"
    echo keep > "$WORK/xf/proj/keep.txt"
    echo a > "$WORK/xf/proj/a.log"
    echo b > "$WORK/xf/proj/b.tmp"
    printf '*.log\n*.tmp\n' > "$WORK/xf/excludes"
    out=$("$ROOT/bin/backup.sh" -X "$WORK/xf/excludes" "$WORK/xf/proj" "$WORK/xfdest")
    assert_eq "proj/keep.txt" "$(tar -tzf "${out#wrote }" | grep -v '/$')" "patterns from the file are applied"
    assert_status 1 "unreadable exclude file" "$ROOT/bin/backup.sh" -X "$WORK/nope" "$WORK/xf/proj" "$WORK/xfdest"
}

test_tar_failure_is_fatal() {
    mkdir -p "$WORK/tf/proj" "$WORK/tfbin"
    printf '#!/bin/sh\nexit 2\n' > "$WORK/tfbin/tar"
    chmod +x "$WORK/tfbin/tar"
    PATH="$WORK/tfbin:$PATH" assert_status 1 "failing tar fails the backup" "$ROOT/bin/backup.sh" "$WORK/tf/proj" "$WORK/tfdest"
    assert_eq "0" "$(ls -A "$WORK/tfdest" | wc -l | tr -d ' ')" "no partial archive left"
}

test_dry_run_writes_nothing() {
    mkdir -p "$WORK/dr/proj"
    out=$("$ROOT/bin/backup.sh" -n "$WORK/dr/proj" "$WORK/drdest")
    assert_eq "no" "$([ -e "$WORK/drdest" ] && echo yes || echo no)" "dest not created"
    assert_eq "would write" "${out%% $WORK*}" "reports what it would do"
}

test_help() {
    assert_status 0 "--help exits 0" "$ROOT/bin/backup.sh" --help
}

test_keep_prunes_old_archives() {
    mkdir -p "$WORK/kp/proj" "$WORK/kpdest"
    for d in 201901010000 201902010000 201903010000; do
        touch -t "$d" "$WORK/kpdest/proj-$d.tar.gz"
    done
    "$ROOT/bin/backup.sh" -k 2 "$WORK/kp/proj" "$WORK/kpdest" >/dev/null
    assert_eq "2" "$(ls "$WORK/kpdest" | grep -c 'tar.gz$')" "two archives remain"
    assert_eq "no" "$([ -e "$WORK/kpdest/proj-201901010000.tar.gz" ] && echo yes || echo no)" "oldest removed"
}

test_keep_must_be_numeric() {
    assert_status 2 "-k abc is a usage error" "$ROOT/bin/backup.sh" -k abc "$WORK" "$WORK/x"
}

run_tests
