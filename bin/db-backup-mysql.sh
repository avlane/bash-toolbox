#!/usr/bin/env bash
# db-backup-mysql.sh - mysqldump wrapper with retention
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: db-backup-mysql.sh [-H HOST] [-P PORT] [-u USER] [-k KEEP] [-n] DEST_DIR DATABASE...

Dump each DATABASE with mysqldump (--single-transaction, so InnoDB tables are
consistent without locking) and gzip it to
DEST_DIR/DATABASE-YYYYmmdd-HHMMSS.sql.gz.

options:
  -H HOST      server host
  -P PORT      server port
  -u USER      user name
  -k KEEP      keep only the newest KEEP dumps per database (default 7, 0 = keep all)
  -n           dry run
  -h, --help   show this help

The password is not accepted as an option, because it would be visible in the
process list. Put it in ~/.my.cnf, or export MYSQL_BACKUP_PASSWORD and the script
hands it to mysqldump through a private temporary option file.
USAGE
}

tb_handle_help usage "$@"

host= port= user=
keep=7
dry=0
while getopts ':H:P:u:k:nh' opt; do
    case $opt in
        H) host=$OPTARG ;;
        P) port=$OPTARG ;;
        u) user=$OPTARG ;;
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

cnf=
trap '[[ -z $cnf ]] || rm -f "$cnf"' EXIT
defaults=()
if [[ -n ${MYSQL_BACKUP_PASSWORD:-} ]]; then
    cnf=$(mktemp "${TMPDIR:-/tmp}/mysql-backup.XXXXXX")   # mktemp creates it mode 0600
    pw=${MYSQL_BACKUP_PASSWORD//\\/\\\\}
    pw=${pw//\"/\\\"}
    printf '[client]\npassword="%s"\n' "$pw" > "$cnf"
    defaults=(--defaults-extra-file="$cnf")   # must be the first mysqldump option
fi

conn=()
[[ -z $host ]] || conn+=(--host="$host")
[[ -z $port ]] || conn+=(--port="$port")
[[ -z $user ]] || conn+=(--user="$user")

tb_require_cmd mysqldump gzip

status=0
for db in "$@"; do
    out="$dest/$db-$(date +%Y%m%d-%H%M%S).sql.gz"
    if (( dry )); then
        echo "would dump $db to $out"
        continue
    fi
    mkdir -p "$dest"
    tmp=$(mktemp "$dest/.mysqldump.XXXXXX")
    if mysqldump ${defaults[@]+"${defaults[@]}"} ${conn[@]+"${conn[@]}"} --single-transaction --routines --triggers "$db" | gzip > "$tmp"; then
        mv "$tmp" "$out"
        echo "wrote $out"
        tb_prune_newest "$keep" "$dest" "$db" .sql.gz
    else
        rm -f "$tmp"
        tb_log "dump of $db failed"
        status=1
    fi
done
exit $status
