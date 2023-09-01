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
all=" $* "
out=
db=
while [ $# -gt 0 ]; do
    if [ "$1" = "-f" ]; then out=$2; shift; fi
    db=$1
    shift
done
if [ -n "${STUB_FAIL:-}" ] && [ "$STUB_FAIL" = "$db" ]; then exit 1; fi
case $all in
    *" -Fd "*) mkdir -p "$out"; echo "dump of $db" > "$out/toc.dat" ;;
    *) echo "dump of $db" > "$out" ;;
esac
STUB
chmod +x "$WORK/bin/pg_dump"
cat > "$WORK/bin/pg_restore" <<'STUB'
#!/bin/bash
echo "pg_restore $*" >> "$STUB_LOG"
[ -z "${STUB_RESTORE_FAIL:-}" ]
STUB
chmod +x "$WORK/bin/pg_restore"
cat > "$WORK/bin/mysqldump" <<'STUB'
#!/bin/bash
case $1 in
    --defaults-extra-file=*) cat "${1#*=}" > "$STUB_LOG.cnf"; shift; echo "defaults-file" >> "$STUB_LOG" ;;
esac
echo "$@" >> "$STUB_LOG"
db=
for a in "$@"; do db=$a; done
if [ -n "${STUB_FAIL:-}" ] && [ "$STUB_FAIL" = "$db" ]; then exit 1; fi
echo "-- dump of $db"
STUB
chmod +x "$WORK/bin/mysqldump"
cat > "$WORK/bin/mysql" <<'STUB'
#!/bin/bash
printf 'information_schema\nmysql\nshop\nperformance_schema\nsys\nblog\n'
STUB
chmod +x "$WORK/bin/mysql"
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

test_pg_verify() {
    : > "$STUB_LOG"
    assert_status 0 "verified dump succeeds" "$ROOT/bin/db-backup-postgres.sh" -V "$WORK/pg6" app
    case $(cat "$STUB_LOG") in
        *"pg_restore --list "*) assert_eq 1 1 "pg_restore --list was run" ;;
        *) assert_eq "pg_restore --list" "$(cat "$STUB_LOG")" "pg_restore --list was run" ;;
    esac
    export STUB_RESTORE_FAIL=1
    assert_status 1 "unreadable dump fails" "$ROOT/bin/db-backup-postgres.sh" -V "$WORK/pg7" app
    unset STUB_RESTORE_FAIL
    assert_eq "0" "$(ls -A "$WORK/pg7" | wc -l | tr -d ' ')" "unverified dump is not kept"
}

test_pg_plain_and_directory_formats() {
    "$ROOT/bin/db-backup-postgres.sh" -F plain "$WORK/pg8" app >/dev/null
    assert_eq "1" "$(ls "$WORK/pg8" | grep -c '^app-.*\.sql$')" "plain dump has .sql"
    : > "$STUB_LOG"
    "$ROOT/bin/db-backup-postgres.sh" -F directory -j 4 "$WORK/pg9" app >/dev/null
    assert_eq "1" "$(ls -d "$WORK/pg9"/app-*.dumpdir | wc -l | tr -d ' ')" "directory dump has .dumpdir"
    assert_eq "1" "$(ls "$WORK/pg9"/app-*.dumpdir | grep -c toc.dat)" "directory dump contains its files"
    case $(cat "$STUB_LOG") in
        *"-Fd -j 4 -f "*) assert_eq 1 1 "format and jobs passed" ;;
        *) assert_eq "-Fd -j 4 -f ..." "$(cat "$STUB_LOG")" "format and jobs passed" ;;
    esac
}

test_pg_directory_retention_removes_directories() {
    mkdir -p "$WORK/pg10/app-20190101-000000.dumpdir" "$WORK/pg10/app-20190201-000000.dumpdir"
    touch -t 201901010000 "$WORK/pg10/app-20190101-000000.dumpdir"
    touch -t 201902010000 "$WORK/pg10/app-20190201-000000.dumpdir"
    "$ROOT/bin/db-backup-postgres.sh" -F directory -k 2 "$WORK/pg10" app >/dev/null
    assert_eq "2" "$(ls "$WORK/pg10" | wc -l | tr -d ' ')" "oldest directory removed"
}

test_pg_option_checks() {
    assert_status 2 "bad format" "$ROOT/bin/db-backup-postgres.sh" -F zip "$WORK/x" app
    assert_status 2 "-j without directory format" "$ROOT/bin/db-backup-postgres.sh" -j 2 "$WORK/x" app
    assert_status 2 "verify plain" "$ROOT/bin/db-backup-postgres.sh" -F plain -V "$WORK/x" app
}

test_pg_dry_run() {
    "$ROOT/bin/db-backup-postgres.sh" -n "$WORK/pg5" app >/dev/null
    assert_eq "no" "$([ -e "$WORK/pg5" ] && echo yes || echo no)" "dry run creates nothing"
}

test_mysql_writes_gzip_dump() {
    : > "$STUB_LOG"
    "$ROOT/bin/db-backup-mysql.sh" -u backup "$WORK/my" shop >/dev/null
    f=$(ls "$WORK/my"/shop-*.sql.gz)
    assert_eq "-- dump of shop" "$(gzip -dc "$f")" "dump content is gzipped"
    assert_eq "--user=backup --single-transaction --routines --triggers shop" "$(cat "$STUB_LOG")" "mysqldump flags"
}

test_mysql_password_goes_through_option_file() {
    : > "$STUB_LOG"
    MYSQL_BACKUP_PASSWORD='p"w\d' "$ROOT/bin/db-backup-mysql.sh" "$WORK/my3" shop >/dev/null
    assert_eq "defaults-file" "$(head -n 1 "$STUB_LOG")" "option file is the first argument"
    assert_eq 'password="p\"w\\d"' "$(sed -n 2p "$STUB_LOG.cnf")" "password is escaped"
    case $(cat "$STUB_LOG") in
        *'p"w'*) assert_eq "no password in arguments" "leaked" "password is not on the command line" ;;
        *) assert_eq 1 1 "password is not on the command line" ;;
    esac
}

test_mysql_all_databases_skips_system_schemas() {
    : > "$STUB_LOG"
    "$ROOT/bin/db-backup-mysql.sh" -A "$WORK/my4" >/dev/null
    assert_eq "blog
shop" "$(ls "$WORK/my4" | sed 's/-[0-9]*-[0-9]*\.sql\.gz$//' | sort)" "only user databases dumped"
    assert_status 2 "-A with database names" "$ROOT/bin/db-backup-mysql.sh" -A "$WORK/my5" shop
}

test_mysql_failed_dump() {
    export STUB_FAIL=bad
    assert_status 1 "failed dump gives exit 1" "$ROOT/bin/db-backup-mysql.sh" "$WORK/my2" bad
    unset STUB_FAIL
    assert_eq "0" "$(ls -A "$WORK/my2" | wc -l | tr -d ' ')" "no partial file left"
}

run_tests
