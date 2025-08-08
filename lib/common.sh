# shellcheck shell=bash
# common.sh - helpers shared by the scripts in bin/. Source it, do not run it.
#
# Everything here is prefixed tb_ so it cannot clash with a caller's names.
# Written to work with bash 3.2 (macOS) as well as newer versions.

tb_prog=${tb_prog:-$(basename "$0")}

# Colour is used for warnings and errors only when standard error is a terminal,
# TERM is not "dumb" and NO_COLOR is not set (https://no-color.org). TB_FORCE_COLOR=1
# turns it on regardless, which the tests use.
tb_use_color() {
    [[ -z ${NO_COLOR:-} ]] || return 1
    [[ -n ${TB_FORCE_COLOR:-} ]] && return 0
    [[ -t 2 && ${TERM:-dumb} != dumb ]]
}

# tb_log_level COLOR_CODE LEVEL MESSAGE... - the common part of tb_log/tb_warn/tb_die
tb_log_level() {
    local code=$1 level=$2 stamp
    shift 2
    stamp=$(date '+%Y-%m-%dT%H:%M:%S')
    if [[ -n $level ]] && tb_use_color; then
        printf '%s %s: \033[%sm%s: %s\033[0m\n' "$stamp" "$tb_prog" "$code" "$level" "$*" >&2
    elif [[ -n $level ]]; then
        printf '%s %s: %s: %s\n' "$stamp" "$tb_prog" "$level" "$*" >&2
    else
        printf '%s %s: %s\n' "$stamp" "$tb_prog" "$*" >&2
    fi
}

tb_log() {
    tb_log_level 0 '' "$*"
}

tb_warn() {
    tb_log_level 33 WARNING "$*"
}

tb_die() {
    tb_log_level 31 ERROR "$*"
    exit 1
}

# tb_usage_error MESSAGE - print the message and the usage text, exit 2
tb_usage_error() {
    printf '%s: %s\n' "$tb_prog" "$*" >&2
    if declare -F usage >/dev/null; then
        usage >&2
    fi
    exit "${tb_usage_status:-2}"
}

# tb_handle_help USAGE_FUNCTION ARGS... - handle --help (getopts has no long options)
tb_handle_help() {
    local fn=$1 arg
    shift
    for arg in "$@"; do
        case $arg in
            --help) "$fn"; exit 0 ;;
            --) break ;;
        esac
    done
}

tb_require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || tb_die "required command not found: $cmd"
    done
}

# tb_bash_at_least MAJOR MINOR - true if running under at least that bash
tb_bash_at_least() {
    (( BASH_VERSINFO[0] > $1 || (BASH_VERSINFO[0] == $1 && BASH_VERSINFO[1] >= $2) ))
}

# tb_now - seconds since the epoch. bash 5 provides EPOCHSECONDS, which saves a
# fork of date; older shells (including macOS /bin/bash 3.2) fall back to date.
tb_now() {
    if [[ -n ${TB_NOW:-} ]]; then     # tests pin the clock with TB_NOW
        printf '%s\n' "$TB_NOW"
    elif [[ -n ${EPOCHSECONDS:-} ]]; then
        printf '%s\n' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# tb_now_ms - milliseconds since the epoch. bash 5 has EPOCHREALTIME
# ("seconds.microseconds", and the separator follows the locale, so both . and ,
# are accepted). Older shells only have whole seconds, so there the result is
# NNN000 and short durations measure as 0.
tb_now_ms() {
    local t
    if [[ -n ${TB_NOW_MS:-} ]]; then
        printf '%s\n' "$TB_NOW_MS"
    elif [[ -n ${EPOCHREALTIME:-} ]]; then
        t=${EPOCHREALTIME/[.,]/}
        printf '%s\n' "${t%???}"
    else
        printf '%s000\n' "$(tb_now)"
    fi
}

# tb_readlines ARRAY_NAME - read standard input into the named array, one line
# per element. bash 4+ has mapfile; the macOS shell (3.2) does not, so there it
# is a read loop. Usage: tb_readlines files < <(find . -name '*.log')
tb_readlines() {
    local __name=$1 __line
    [[ $__name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || tb_die "tb_readlines: bad array name: $__name"
    if tb_bash_at_least 4 0; then
        mapfile -t "$__name"
    else
        eval "$__name=()"
        while IFS= read -r __line || [[ -n $__line ]]; do
            eval "$__name+=(\"\$__line\")"
        done
    fi
}

# tb_quote TEXT - shell-quote TEXT so it can be pasted back into a shell.
# bash 4.4 added ${var@Q}; before that printf %q does the job (its output looks
# different, for example a\ b instead of 'a b', but means the same).
tb_quote() {
    if tb_bash_at_least 4 4; then
        printf '%s' "${1@Q}"
    else
        printf '%q' "$1"
    fi
}

# tb_quote_args ARG... - the arguments quoted and joined with spaces
tb_quote_args() {
    local arg out=
    for arg in "$@"; do
        out="$out $(tb_quote "$arg")"
    done
    printf '%s' "${out# }"
}

# tb_sha256 FILE - print "HASH  NAME" (the sha256sum format) for FILE.
# Linux has sha256sum, macOS has shasum; either way the output is identical.
tb_sha256() {
    local dir name
    dir=$(dirname "$1")
    name=$(basename "$1")
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$dir" && sha256sum "$name")
    elif command -v shasum >/dev/null 2>&1; then
        (cd "$dir" && shasum -a 256 "$name")
    else
        tb_die "need sha256sum or shasum to compute checksums"
    fi
}

# tb_sha256_verify SUMFILE - check the files named in SUMFILE, relative to its directory
tb_sha256_verify() {
    local dir name
    dir=$(dirname "$1")
    name=$(basename "$1")
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$dir" && sha256sum -c "$name" >/dev/null 2>&1)
    elif command -v shasum >/dev/null 2>&1; then
        (cd "$dir" && shasum -a 256 -c "$name" >/dev/null 2>&1)
    else
        tb_die "need sha256sum or shasum to verify checksums"
    fi
}

# tb_days_from_civil YEAR MONTH DAY - days since 1970-01-01 (proleptic Gregorian).
# Plain integer arithmetic, so it behaves the same with BSD and GNU userlands,
# unlike date -d / date -j.
tb_days_from_civil() {
    local y=$1 m=$((10#$2)) d=$((10#$3)) era yoe doy doe
    if (( m <= 2 )); then
        y=$((y - 1))
    fi
    era=$(( (y >= 0 ? y : y - 399) / 400 ))
    yoe=$(( y - era * 400 ))
    doy=$(( (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1 ))
    doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
    printf '%s\n' $(( era * 146097 + doe - 719468 ))
}

# tb_civil_from_days DAYS - the inverse: prints "YEAR MONTH DAY" for days since 1970-01-01
tb_civil_from_days() {
    local z=$(( $1 + 719468 )) era doe yoe y doy mp d m
    era=$(( (z >= 0 ? z : z - 146096) / 146097 ))
    doe=$(( z - era * 146097 ))
    yoe=$(( (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 ))
    y=$(( yoe + era * 400 ))
    doy=$(( doe - (365 * yoe + yoe / 4 - yoe / 100) ))
    mp=$(( (5 * doy + 2) / 153 ))
    d=$(( doy - (153 * mp + 2) / 5 + 1 ))
    m=$(( mp < 10 ? mp + 3 : mp - 9 ))
    if (( m <= 2 )); then
        y=$((y + 1))
    fi
    printf '%s %s %s\n' "$y" "$m" "$d"
}

# tb_json_escape TEXT - escape TEXT for use inside a JSON string (backslash,
# double quote and the control characters that can appear in one-line text)
tb_json_escape() {
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

# tb_prune_newest KEEP DIR PREFIX SUFFIX - in DIR, keep the newest KEEP files
# named PREFIX-*SUFFIX and delete the rest (with any .sha256 next to them).
# KEEP of 0 keeps everything. Used by the backup scripts, whose file names are
# generated by them, so ls output is safe to parse here.
tb_prune_newest() {
    local keep=$1 dir=$2 prefix=$3 suffix=$4 n=0 old
    (( keep > 0 )) || return 0
    while IFS= read -r old; do
        n=$((n + 1))
        if (( n > keep )); then
            if [[ -d $old ]]; then
                rm -rf -- "$old"       # directory-format dumps
            else
                rm -f -- "$old" "$old.sha256"
            fi
            echo "removed $old"
        fi
    done < <(ls -1td "$dir/$prefix"-*"$suffix" 2>/dev/null || true)
}

# tb_run_timeout SECONDS COMMAND... - run COMMAND, kill it after SECONDS and return
# 124 in that case (the same convention as GNU timeout, which macOS does not
# ship). Redirections on the call apply to COMMAND. The watchdog wakes every
# second so it never outlives the command by more than that.
tb_run_timeout() {
    local secs=$1 pid dog flag rc=0
    shift
    flag=$(mktemp "${TMPDIR:-/tmp}/tb-timeout.XXXXXX")
    rm -f "$flag"       # it exists only if the watchdog fires
    "$@" &
    pid=$!
    (
        i=0
        while (( i < secs )); do
            sleep 1
            kill -0 "$pid" 2>/dev/null || exit 0
            i=$((i + 1))
        done
        : > "$flag"
        kill -TERM "$pid" 2>/dev/null
    ) &
    dog=$!
    wait "$pid" 2>/dev/null || rc=$?
    kill "$dog" 2>/dev/null || true
    wait "$dog" 2>/dev/null || true
    if [[ -e $flag ]]; then
        rm -f "$flag"
        return 124
    fi
    return "$rc"
}

# tb_cat_unix FILE - print FILE without carriage returns. List and config files
# edited on Windows end their lines in CR LF, and read would keep the CR as part
# of the last field. Use as: while read ...; do ...; done < <(tb_cat_unix "$file")
tb_cat_unix() {
    tr -d '\r' < "$1"
}
