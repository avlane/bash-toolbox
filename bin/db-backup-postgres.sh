#!/usr/bin/env bash
# db-backup-postgres.sh - pg_dump wrapper with retention
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: db-backup-postgres.sh [-H HOST] [-p PORT] [-U USER] [-F FORMAT] [-j JOBS] [-k KEEP] [-V] [-n] DEST_DIR DATABASE...

Dump each DATABASE with pg_dump to DEST_DIR/DATABASE-YYYYmmdd-HHMMSS.EXT, where
EXT depends on -F: custom (default, .dump, restore with pg_restore), plain (.sql,
restore with psql) or directory (.dumpdir, restorable in parallel). A dump is written to a temporary file
and renamed, so a failed dump never replaces a good file.

options:
  -H HOST     server host (default: libpq default)
  -p PORT     server port
  -U USER     role to connect as
  -F FORMAT   custom, plain or directory (default custom)
  -j JOBS     parallel jobs for the directory format
  -k KEEP     keep only the newest KEEP dumps per database (default 7, 0 = keep all)
  -V          verify each dump by listing it with pg_restore --list
  -n          dry run
  -h, --help  show this help

The password is never taken on the command line: use ~/.pgpass or PGPASSWORD.
USAGE
}

tb_handle_help usage "$@"

host= port= user=
format=custom
jobs=
verify=0
keep=7
dry=0
while getopts ':H:p:U:F:j:k:Vnh' opt; do
    case $opt in
        H) host=$OPTARG ;;
        p) port=$OPTARG ;;
        U) user=$OPTARG ;;
        F) format=$OPTARG ;;
        j) jobs=$OPTARG ;;
        k) keep=$OPTARG ;;
        V) verify=1 ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $keep =~ ^[0-9]+$ ]] || tb_usage_error "-k needs a number"
[[ -z $jobs || $jobs =~ ^[1-9][0-9]*$ ]] || tb_usage_error "-j needs a positive number"
case $format in
    custom) ext=.dump; fmt_flag=-Fc ;;
    plain) ext=.sql; fmt_flag=-Fp ;;
    directory) ext=.dumpdir; fmt_flag=-Fd ;;
    *) tb_usage_error "-F must be custom, plain or directory" ;;
esac
[[ -z $jobs || $format == directory ]] || tb_usage_error "-j only works with -F directory"
(( ! verify )) || [[ $format != plain ]] || tb_usage_error "-V cannot verify plain dumps (pg_restore does not read them)"
[[ $# -ge 2 ]] || tb_usage_error "expected DEST_DIR and at least one DATABASE"
dest=$1
shift

conn=()
[[ -z $host ]] || conn+=(-h "$host")
[[ -z $port ]] || conn+=(-p "$port")
[[ -z $user ]] || conn+=(-U "$user")

tb_require_cmd pg_dump
if (( verify )); then
    tb_require_cmd pg_restore
fi

status=0
for db in "$@"; do
    out="$dest/$db-$(date +%Y%m%d-%H%M%S)$ext"
    if (( dry )); then
        echo "would dump $db to $out"
        continue
    fi
    mkdir -p "$dest"
    # work in a private temporary directory, move the result into place at the end
    work=$(mktemp -d "$dest/.pgdump.XXXXXX")
    if pg_dump ${conn[@]+"${conn[@]}"} "$fmt_flag" ${jobs:+-j "$jobs"} -f "$work/dump" "$db" &&
        { (( ! verify )) || pg_restore --list "$work/dump" >/dev/null; }; then
        mv "$work/dump" "$out"
        rmdir "$work"
        echo "wrote $out"
        tb_prune_newest "$keep" "$dest" "$db" "$ext"
    else
        rm -rf "$work"
        tb_log "dump of $db failed (or did not verify)"
        status=1
    fi
done
exit $status
