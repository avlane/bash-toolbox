#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sqlbackup-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# stub sqlcmd: log every argument on its own line, fail when the query matches STUB_FAIL_ON
mkdir -p "$WORK/bin"
cat > "$WORK/bin/sqlcmd" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >> "$STUB_LOG"
echo "--" >> "$STUB_LOG"
if [ -n "${STUB_FAIL_ON:-}" ]; then
    case "$*" in *"$STUB_FAIL_ON"*) exit 1 ;; esac
fi
STUB
chmod +x "$WORK/bin/sqlcmd"
export PATH="$WORK/bin:$PATH"
export STUB_LOG="$WORK/calls"
unset SQLCMDPASSWORD

BK="$ROOT/bin/db-backup-sqlserver.sh"

test_dry_run_prints_tsql_and_does_not_connect() {
    : > "$STUB_LOG"
    out=$("$BK" -n /srv/backup Sales)
    case $out in
        "BACKUP DATABASE [Sales] TO DISK = N'/srv/backup/Sales-"*".bak' WITH COMPRESSION, CHECKSUM, INIT, NAME = N'Sales full backup';")
            assert_eq 1 1 "T-SQL looks right" ;;
        *) assert_eq "BACKUP DATABASE [Sales] ..." "$out" "T-SQL looks right" ;;
    esac
    assert_eq "0" "$(wc -c < "$STUB_LOG" | tr -d ' ')" "sqlcmd was not called"
}

test_integrated_auth_by_default() {
    : > "$STUB_LOG"
    "$BK" -S sqlprod01 /srv/backup Sales >/dev/null
    assert_eq "-b
-S
sqlprod01
-E" "$(sed -n 1,4p "$STUB_LOG")" "uses -b, -S and -E"
}

test_sql_login_needs_password_variable() {
    assert_status 1 "-U without SQLCMDPASSWORD" "$BK" -U backup /srv/backup Sales
    : > "$STUB_LOG"
    SQLCMDPASSWORD=secret "$BK" -U backup /srv/backup Sales >/dev/null
    case $(cat "$STUB_LOG") in
        *secret*) assert_eq "no secret in args" "leaked" "password stays out of the arguments" ;;
        *) assert_eq 1 1 "password stays out of the arguments" ;;
    esac
}

test_trust_certificate_flag() {
    : > "$STUB_LOG"
    "$BK" -C /srv/backup Sales >/dev/null
    assert_eq "1" "$(grep -c '^-C$' "$STUB_LOG")" "-C is passed to sqlcmd"
}

test_verify_runs_second_statement() {
    : > "$STUB_LOG"
    "$BK" -V /srv/backup Sales >/dev/null
    assert_eq "1" "$(grep -c '^BACKUP DATABASE' "$STUB_LOG")" "one backup"
    assert_eq "1" "$(grep -c '^RESTORE VERIFYONLY' "$STUB_LOG")" "one verify"
}

test_failed_verify_fails_the_run() {
    export STUB_FAIL_ON="RESTORE VERIFYONLY"
    assert_status 1 "verify failure gives exit 1" "$BK" -V /srv/backup Sales
    unset STUB_FAIL_ON
}

test_names_are_quoted() {
    out=$("$BK" -n /srv/backup "a]b")
    case $out in
        "BACKUP DATABASE [a]]b] TO"*) assert_eq 1 1 "] is doubled" ;;
        *) assert_eq "[a]]b]" "$out" "] is doubled" ;;
    esac
}

test_retention_on_visible_directory() {
    mkdir -p "$WORK/bak"
    for d in 201901010000 201902010000 201903010000; do
        touch -t "$d" "$WORK/bak/Sales-$d.bak"
    done
    "$BK" -k 2 "$WORK/bak" Sales >/dev/null
    # the stub does not create the new backup, so two old ones remain
    assert_eq "2" "$(ls "$WORK/bak" | wc -l | tr -d ' ')" "oldest backup pruned"
}

run_tests
