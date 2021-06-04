#!/usr/bin/env bash
# disk-alert.sh - warn when a filesystem is nearly full, by space or by inodes
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: disk-alert.sh [-i INODE_PERCENT] [-c FILE] [PERCENT]

Print a line for every filesystem whose space usage is at or over PERCENT
(default 90). With -i, also report filesystems whose inode usage is at or over
INODE_PERCENT; a disk can run out of inodes long before it runs out of space.

With -c, FILE holds per-mount overrides, one "MOUNTPOINT PERCENT" pair per
line (blank lines and # comments are ignored; mount points cannot contain
spaces). An override replaces PERCENT for that mount, in both checks.

Exit status: 0 nothing over a threshold, 1 something is, 2 usage error.

Set DF_CMD and DFI_CMD to replace the df commands (used by the tests).
USAGE
}

tb_handle_help usage "$@"

inode_limit= conf=
while getopts ':i:c:h' opt; do
    case $opt in
        i) inode_limit=$OPTARG ;;
        c) conf=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -le 1 ]] || tb_usage_error "too many arguments"
limit=${1:-90}
for n in "$limit" ${inode_limit:+"$inode_limit"}; do
    [[ $n =~ ^[0-9]+$ ]] || tb_usage_error "thresholds must be whole numbers"
done

# Per-mount overrides. bash 4+ gets an associative array; older shells (macOS
# /bin/bash is 3.2) scan a text copy of the file instead.
use_assoc=0
if tb_bash_at_least 4 0; then
    use_assoc=1
    declare -A overrides
fi
overrides_text=

load_overrides() {
    local file=$1 m p
    [[ -r $file ]] || tb_die "cannot read $file"
    while read -r m p; do
        if [[ -z $m || $m == \#* ]]; then
            continue
        fi
        [[ $p =~ ^[0-9]+$ ]] || tb_die "bad line in $file: $m $p"
        overrides_text="$overrides_text$m $p"$'\n'
        if (( use_assoc )); then
            overrides[$m]=$p
        fi
    done < "$file"
}

# limit_for MOUNT DEFAULT - the threshold that applies to MOUNT
limit_for() {
    local mount=$1 default=$2 m p
    if (( use_assoc )); then
        printf '%s\n' "${overrides[$mount]:-$default}"
        return 0
    fi
    while read -r m p; do
        if [[ $m == "$mount" ]]; then
            printf '%s\n' "$p"
            return 0
        fi
    done <<< "$overrides_text"
    printf '%s\n' "$default"
}

[[ -z $conf ]] || load_overrides "$conf"

# parse_df WHICH - read df -P output and print "filesystem<TAB>percent<TAB>mount".
# Plain df has one NN% column. macOS "df -i" has two (capacity and %iused) and
# GNU has one, so for inodes we take the last NN% column on the line.
parse_df() {
    awk -v which="$1" 'NR > 1 {
        idx = 0
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^[0-9]+%$/ && (which == "last" || idx == 0)) idx = i
        }
        if (idx == 0) next
        mount = $(idx + 1)
        for (j = idx + 2; j <= NF; j++) mount = mount " " $j
        printf "%s\t%s\t%s\n", $1, $idx, mount
    }'
}

status=0
while IFS=$'\t' read -r fs pct mount; do
    if (( ${pct%\%} >= $(limit_for "$mount" "$limit") )); then
        echo "WARNING: $mount is at $pct ($fs)"
        status=1
    fi
done < <(${DF_CMD:-df -P} | parse_df first)

if [[ -n $inode_limit ]]; then
    while IFS=$'\t' read -r fs pct mount; do
        if (( ${pct%\%} >= $(limit_for "$mount" "$inode_limit") )); then
            echo "WARNING: $mount has used $pct of its inodes ($fs)"
            status=1
        fi
    done < <(${DFI_CMD:-df -P -i} | parse_df last)
fi

exit $status
