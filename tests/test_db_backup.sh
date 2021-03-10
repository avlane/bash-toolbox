#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dbbackup-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# stub client programs go first on PATH and record how they were called
mkdir -p "$WORK/bin"
cat > "$WORK/bin/pg_dump" <<'STUB'
#!/bin/bash
echo "$@" >> "$STUB_LOG"
out=
db=
while [ $# -gt 0 ]; do
    if [ "$1" = "-f" ]; then out=$2; shift; fi
    db=$1
    shift
done
if [ -n "${STUB_FAIL:-}" ] && [ "$STUB_FAIL" = "$db" ]; then exit 1; fi
echo "dump of $db" > "$out"
STUB
chmod +x "$WORK/bin/pg_dump"
export PATH="$WORK/bin:$PATH"
export STUB_LOG="$WORK/calls"

test_pg_writes_dump_per_database() {
    : > "$STUB_LOG"
    "$ROOT/bin/db-backup-postgres.sh" "$WORK/pg" app reports >/dev/null
    assert_eq "2" "$(ls "$WORK/pg" | wc -l | tr -d ' ')" "one dump per database"
    assert_eq "1" "$(ls "$WORK/pg" | grep -c '^app-.*\.dump$')" "app dump exists"
}

test_pg_connection_options_passed() {
    : > "$STUB_LOG"
    "$ROOT/bin/db-backup-postgres.sh" -H db01 -p 5433 -U backup "$WORK/pg2" app >/dev/null
    case $(cat "$STUB_LOG") in
        "-h db01 -p 5433 -U backup -Fc -f "*" app") assert_eq 1 1 "options reach pg_dump" ;;
        *) assert_eq "-h db01 -p 5433 -U backup -Fc -f TMP app" "$(cat "$STUB_LOG")" "options reach pg_dump" ;;
    esac
}

test_pg_failed_dump_leaves_nothing_and_fails() {
    export STUB_FAIL=bad
    assert_status 1 "failed dump gives exit 1" "$ROOT/bin/db-backup-postgres.sh" "$WORK/pg3" bad
    unset STUB_FAIL
    assert_eq "0" "$(ls -A "$WORK/pg3" | wc -l | tr -d ' ')" "no partial file left"
}

test_pg_retention() {
    mkdir -p "$WORK/pg4"
    for d in 201901010000 201902010000 201903010000; do
        touch -t "$d" "$WORK/pg4/app-$d.dump"
    done
    "$ROOT/bin/db-backup-postgres.sh" -k 2 "$WORK/pg4" app >/dev/null
    assert_eq "2" "$(ls "$WORK/pg4" | wc -l | tr -d ' ')" "newest two remain"
}

test_pg_dry_run() {
    "$ROOT/bin/db-backup-postgres.sh" -n "$WORK/pg5" app >/dev/null
    assert_eq "no" "$([ -e "$WORK/pg5" ] && echo yes || echo no)" "dry run creates nothing"
}

run_tests
