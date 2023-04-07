#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rotbak-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

RB="$ROOT/bin/rotate-backups.sh"

make_files() {   # make_files DIR : two old files, one new, one other type
    mkdir -p "$1"
    touch -t 201901010000 "$1/old one.tar.gz" "$1/old-two.tar.gz" "$1/old.sql"
    touch "$1/new.tar.gz"
}

test_removes_old_matching_files_only() {
    make_files "$WORK/a"
    "$RB" "$WORK/a" 30 >/dev/null
    assert_eq "new.tar.gz
old.sql" "$(ls "$WORK/a")" "old archives gone, new archive and other types kept"
}

test_pattern_option() {
    make_files "$WORK/b"
    touch -t 201901010000 "$WORK/b/older.sql"
    touch "$WORK/b/new.sql"
    "$RB" -p '*.sql' "$WORK/b" 30 >/dev/null 2>&1
    assert_eq "new.sql" "$(ls "$WORK/b" | grep '\.sql$')" "old .sql files rotated, archives untouched"
    assert_eq "3" "$(ls "$WORK/b" | grep -c 'tar.gz')" "all archives kept"
}

test_dry_run() {
    make_files "$WORK/c"
    out=$("$RB" -n "$WORK/c" 30)
    assert_eq "4" "$(ls "$WORK/c" | wc -l | tr -d ' ')" "nothing deleted"
    assert_eq "2" "$(echo "$out" | grep -c '^would remove ')" "two reported"
}

test_never_removes_the_last_match() {
    mkdir -p "$WORK/d"
    touch -t 201901010000 "$WORK/d/only.tar.gz"
    "$RB" "$WORK/d" 1 >/dev/null 2>&1
    assert_file_exists "$WORK/d/only.tar.gz" "the only archive is kept"
}

test_usage_errors() {
    assert_status 2 "missing args" "$RB" "$WORK"
    assert_status 2 "non numeric days" "$RB" "$WORK" soon
    assert_status 1 "not a directory" "$RB" "$WORK/nope" 3
}

# --- -g DAILY,WEEKLY,MONTHLY ---------------------------------------------------

. "$ROOT/lib/common.sh"
# the clock is pinned to 2023-03-15 12:00 UTC (a Wednesday)
NOW=$(( $(tb_days_from_civil 2023 03 15) * 86400 + 43200 ))

test_gfs_keeps_newest_per_bucket() {
    d="$WORK/gfs"; mkdir -p "$d"
    for stamp in 20230315-100000 20230315-020000 20230314-020000 20230313-020000 \
                 20230312-020000 20230311-020000 20230228-020000 20230227-020000 \
                 20230115-020000 20221231-020000; do
        touch "$d/proj-$stamp.tar.gz"
        echo sum > "$d/proj-$stamp.tar.gz.sha256"
    done
    TB_NOW=$NOW "$RB" -g 3,2,2 "$d" >/dev/null
    assert_eq "proj-20230228-020000.tar.gz
proj-20230312-020000.tar.gz
proj-20230313-020000.tar.gz
proj-20230314-020000.tar.gz
proj-20230315-100000.tar.gz" "$(ls "$d" | grep 'tar.gz$')" "daily, weekly and monthly representatives remain"
    assert_eq "5" "$(ls "$d" | grep -c 'sha256$')" "checksums of deleted archives are removed too"
}

test_gfs_leaves_undated_files_alone() {
    d="$WORK/gfs2"; mkdir -p "$d"
    touch "$d/manual.tar.gz" "$d/proj-20200101-000000.tar.gz"
    TB_NOW=$NOW "$RB" -g 1,1,1 "$d" >/dev/null 2>&1
    assert_eq "manual.tar.gz" "$(ls "$d")" "file without a date kept, old dated file removed"
}

test_gfs_dry_run() {
    d="$WORK/gfs3"; mkdir -p "$d"
    touch "$d/proj-20200101-000000.tar.gz"
    TB_NOW=$NOW "$RB" -n -g 1,1,1 "$d" >/dev/null
    assert_eq "1" "$(ls "$d" | wc -l | tr -d ' ')" "dry run deletes nothing"
}

test_gfs_usage_errors() {
    assert_status 2 "malformed -g" "$RB" -g 7,4 "$WORK"
    assert_status 2 "-g with DAYS" "$RB" -g 7,4,6 "$WORK" 30
}

run_tests
