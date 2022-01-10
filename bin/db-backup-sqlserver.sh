#!/usr/bin/env bash
# db-backup-sqlserver.sh - full database backups through sqlcmd
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: db-backup-sqlserver.sh [-S SERVER] [-U USER] [-k KEEP] [-n] DEST_DIR DATABASE...

Run BACKUP DATABASE ... WITH COMPRESSION, CHECKSUM for each DATABASE through
sqlcmd, writing DEST_DIR/DATABASE-YYYYmmdd-HHMMSS.bak.

IMPORTANT: the backup is written by the SQL Server service, so DEST_DIR is a
path on the server (and the service account needs write access to it), not a
path on the machine running this script.

options:
  -S SERVER   server or server,port (default: sqlcmd default, usually localhost)
  -U USER     SQL login. Without -U, integrated authentication (-E) is used.
  -k KEEP     afterwards keep only the newest KEEP backups per database. This
              only works when DEST_DIR is also visible from this machine
              (default 0 = keep everything)
  -n          dry run: print the T-SQL, do not connect
  -h, --help  show this help

The SQL login's password is read from the SQLCMDPASSWORD environment variable
(sqlcmd does this itself); it is never put on the command line.
USAGE
}

tb_handle_help usage "$@"

server= user=
keep=0
dry=0
while getopts ':S:U:k:nh' opt; do
    case $opt in
        S) server=$OPTARG ;;
        U) user=$OPTARG ;;
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
dest=${1%/}
shift

conn=(-b)
[[ -z $server ]] || conn+=(-S "$server")
if [[ -n $user ]]; then
    [[ -n ${SQLCMDPASSWORD:-} ]] || tb_die "-U needs the password in SQLCMDPASSWORD"
    conn+=(-U "$user")
else
    conn+=(-E)
fi

(( dry )) || tb_require_cmd sqlcmd

# sql_ident NAME - bracket-quote an identifier (] is doubled)
sql_ident() {
    printf '[%s]' "${1//]/]]}"
}

# sql_string TEXT - N'...' literal (' is doubled)
sql_string() {
    local q="'"
    printf "N'%s'" "${1//$q/$q$q}"
}

prune() {
    local db=$1 n=0 old
    (( keep > 0 )) || return 0
    if [[ ! -d $dest ]]; then
        tb_warn "$dest is not visible from here, not pruning old backups"
        return 0
    fi
    while IFS= read -r old; do
        n=$((n + 1))
        if (( n > keep )); then
            rm -f -- "$old"
            echo "removed $old"
        fi
    done < <(ls -1t "$dest/$db"-*.bak 2>/dev/null || true)
}

status=0
for db in "$@"; do
    file="$dest/$db-$(date +%Y%m%d-%H%M%S).bak"
    query="BACKUP DATABASE $(sql_ident "$db") TO DISK = $(sql_string "$file") WITH COMPRESSION, CHECKSUM, INIT, NAME = $(sql_string "$db full backup");"
    if (( dry )); then
        echo "$query"
        continue
    fi
    if sqlcmd "${conn[@]}" -Q "$query"; then
        echo "wrote $file"
        prune "$db"
    else
        tb_log "backup of $db failed"
        status=1
    fi
done
exit $status
