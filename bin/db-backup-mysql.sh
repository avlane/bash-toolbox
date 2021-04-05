#!/usr/bin/env bash
# db-backup-mysql.sh - mysqldump wrapper with retention
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: db-backup-mysql.sh [-H HOST] [-P PORT] [-u USER] [-p PASSWORD] [-k KEEP] [-n] DEST_DIR DATABASE...

Dump each DATABASE with mysqldump (--single-transaction, so InnoDB tables are
consistent without locking) and gzip it to
DEST_DIR/DATABASE-YYYYmmdd-HHMMSS.sql.gz.

options:
  -H HOST      server host
  -P PORT      server port
  -u USER      user name
  -p PASSWORD  password
  -k KEEP      keep only the newest KEEP dumps per database (default 7, 0 = keep all)
  -n           dry run
  -h, --help   show this help
USAGE
}

tb_handle_help usage "$@"

host= port= user= password=
keep=7
dry=0
while getopts ':H:P:u:p:k:nh' opt; do
    case $opt in
        H) host=$OPTARG ;;
        P) port=$OPTARG ;;
        u) user=$OPTARG ;;
        p) password=$OPTARG ;;
        k) keep=$OPTARG ;;
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
[[ -z $host ]] || conn+=(--host="$host")
[[ -z $port ]] || conn+=(--port="$port")
[[ -z $user ]] || conn+=(--user="$user")
[[ -z $password ]] || conn+=(--password="$password")

tb_require_cmd mysqldump gzip

prune() {
    local db=$1 n=0 old
    (( keep > 0 )) || return 0
    while IFS= read -r old; do
        n=$((n + 1))
        if (( n > keep )); then
            rm -f -- "$old"
            echo "removed $old"
        fi
    done < <(ls -1t "$dest/$db"-*.sql.gz 2>/dev/null || true)
}

status=0
for db in "$@"; do
    out="$dest/$db-$(date +%Y%m%d-%H%M%S).sql.gz"
    if (( dry )); then
        echo "would dump $db to $out"
        continue
    fi
    mkdir -p "$dest"
    tmp=$(mktemp "$dest/.mysqldump.XXXXXX")
    if mysqldump ${conn[@]+"${conn[@]}"} --single-transaction --routines --triggers "$db" | gzip > "$tmp"; then
        mv "$tmp" "$out"
        echo "wrote $out"
        prune "$db"
    else
        rm -f "$tmp"
        tb_log "dump of $db failed"
        status=1
    fi
done
exit $status
