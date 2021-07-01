#!/usr/bin/env bash
# db-backup-postgres.sh - pg_dump wrapper with retention
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: db-backup-postgres.sh [-H HOST] [-p PORT] [-U USER] [-k KEEP] [-V] [-n] DEST_DIR DATABASE...

Dump each DATABASE with pg_dump in custom format (restore with pg_restore) to
DEST_DIR/DATABASE-YYYYmmdd-HHMMSS.dump. A dump is written to a temporary file
and renamed, so a failed dump never replaces a good file.

options:
  -H HOST     server host (default: libpq default)
  -p PORT     server port
  -U USER     role to connect as
  -k KEEP     keep only the newest KEEP dumps per database (default 7, 0 = keep all)
  -V          verify each dump by listing it with pg_restore --list
  -n          dry run
  -h, --help  show this help

The password is never taken on the command line: use ~/.pgpass or PGPASSWORD.
USAGE
}

tb_handle_help usage "$@"

host= port= user=
verify=0
keep=7
dry=0
while getopts ':H:p:U:k:Vnh' opt; do
    case $opt in
        H) host=$OPTARG ;;
        p) port=$OPTARG ;;
        U) user=$OPTARG ;;
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

prune() {
    local db=$1 n=0 old
    (( keep > 0 )) || return 0
    while IFS= read -r old; do
        n=$((n + 1))
        if (( n > keep )); then
            rm -f -- "$old"
            echo "removed $old"
        fi
    done < <(ls -1t "$dest/$db"-*.dump 2>/dev/null || true)
}

status=0
for db in "$@"; do
    out="$dest/$db-$(date +%Y%m%d-%H%M%S).dump"
    if (( dry )); then
        echo "would dump $db to $out"
        continue
    fi
    mkdir -p "$dest"
    tmp=$(mktemp "$dest/.pgdump.XXXXXX")
    if pg_dump ${conn[@]+"${conn[@]}"} -Fc -f "$tmp" "$db" &&
        { (( ! verify )) || pg_restore --list "$tmp" >/dev/null; }; then
        mv "$tmp" "$out"
        echo "wrote $out"
        prune "$db"
    else
        rm -f "$tmp"
        tb_log "dump of $db failed (or did not verify)"
        status=1
    fi
done
exit $status
