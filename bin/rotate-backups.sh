#!/usr/bin/env bash
# rotate-backups.sh - delete old backup files from a directory
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: rotate-backups.sh [-n] [-p PATTERN] DIR DAYS
       rotate-backups.sh [-n] [-p PATTERN] -g DAILY,WEEKLY,MONTHLY DIR

Delete files in DIR (not in sub-directories) that match PATTERN and are older
than DAYS days. PATTERN is a shell glob, default '*.tar.gz'. At least one file
that matches is always kept, even if it is old, so a stalled backup job cannot
silently empty the directory.

With -g the files are thinned out instead of cut off at an age: the newest file
of each of the last DAILY days, WEEKLY weeks (starting Monday) and MONTHLY months
is kept, and the rest is deleted. The date comes from the YYYYmmdd-HHMMSS in the
file name (as written by backup.sh), in UTC; files without one are left alone.
File names must not contain newlines in this mode.

options:
  -g D,W,M    keep-N-per-day/week/month retention, see above
  -p PATTERN  file name glob to rotate (quote it so your shell does not expand it)
  -n          dry run: list what would be deleted
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

pattern='*.tar.gz'
dry=0
gfs=
while getopts ':p:g:nh' opt; do
    case $opt in
        p) pattern=$OPTARG ;;
        g) gfs=$OPTARG ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

gfs_re='^([0-9]+),([0-9]+),([0-9]+)$'
if [[ -n $gfs ]]; then
    [[ $gfs =~ $gfs_re ]] || tb_usage_error "-g needs DAILY,WEEKLY,MONTHLY as whole numbers"
    keep_days=${BASH_REMATCH[1]} keep_weeks=${BASH_REMATCH[2]} keep_months=${BASH_REMATCH[3]}
    [[ $# -eq 1 ]] || tb_usage_error "with -g give just DIR"
    dir=$1
    [[ -d $dir ]] || tb_die "$dir is not a directory"
else
    [[ $# -eq 2 ]] || tb_usage_error "expected DIR and DAYS"
    dir=$1
    days=$2
    [[ -d $dir ]] || tb_die "$dir is not a directory"
    [[ $days =~ ^[0-9]+$ ]] || tb_usage_error "DAYS must be a whole number"
fi

delete_file() {
    if (( dry )); then
        echo "would remove $1"
    else
        rm -f -- "$1" "$1.sha256"
        echo "removed $1"
    fi
}

gfs_rotate() {
    local today today_week today_month name y m d day week month
    local seen_day=" " seen_week=" " seen_month=" " keep f
    local name_re='([0-9]{4})([0-9]{2})([0-9]{2})-[0-9]{6}'
    today=$(( $(tb_now) / 86400 ))
    today_week=$(( (today + 3) / 7 ))      # 1970-01-01 was a Thursday
    read -r y m d < <(tb_civil_from_days "$today")
    today_month=$(( y * 12 + m - 1 ))
    tb_readlines files < <(find "$dir" -maxdepth 1 -type f -name "$pattern" | sort -r)
    for f in ${files[@]+"${files[@]}"}; do
        name=$(basename "$f")
        if ! [[ $name =~ $name_re ]]; then
            tb_warn "no date in $name, leaving it alone"
            continue
        fi
        y=${BASH_REMATCH[1]} m=${BASH_REMATCH[2]} d=${BASH_REMATCH[3]}
        day=$(tb_days_from_civil "$y" "$m" "$d")
        week=$(( (day + 3) / 7 ))
        month=$(( y * 12 + 10#$m - 1 ))
        keep=0
        if (( today - day < keep_days )) && [[ $seen_day != *" $day "* ]]; then
            seen_day="$seen_day$day "; keep=1
        fi
        if (( today_week - week < keep_weeks )) && [[ $seen_week != *" $week "* ]]; then
            seen_week="$seen_week$week "; keep=1
        fi
        if (( today_month - month < keep_months )) && [[ $seen_month != *" $month "* ]]; then
            seen_month="$seen_month$month "; keep=1
        fi
        (( keep )) || delete_file "$f"
    done
}

if [[ -n $gfs ]]; then
    gfs_rotate
    exit 0
fi

total=$(find "$dir" -maxdepth 1 -type f -name "$pattern" | wc -l | tr -d ' ')

removed=0
# -print0 and read -d '' keep odd file names intact
while IFS= read -r -d '' f; do
    if (( total - removed <= 1 )); then
        tb_warn "keeping $f, it is the last matching file"
        break
    fi
    delete_file "$f"
    removed=$((removed + 1))
done < <(find "$dir" -maxdepth 1 -type f -name "$pattern" -mtime "+$days" -print0)
