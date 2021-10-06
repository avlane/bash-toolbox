# shellcheck shell=bash
# common.sh - helpers shared by the scripts in bin/. Source it, do not run it.
#
# Everything here is prefixed tb_ so it cannot clash with a caller's names.
# Written to work with bash 3.2 (macOS) as well as newer versions.

tb_prog=${tb_prog:-$(basename "$0")}

tb_log() {
    printf '%s %s: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$tb_prog" "$*" >&2
}

tb_warn() {
    tb_log "WARNING: $*"
}

tb_die() {
    tb_log "ERROR: $*"
    exit 1
}

# tb_usage_error MESSAGE - print the message and the usage text, exit 2
tb_usage_error() {
    printf '%s: %s\n' "$tb_prog" "$*" >&2
    if declare -F usage >/dev/null; then
        usage >&2
    fi
    exit 2
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
    if [[ -n ${EPOCHSECONDS:-} ]]; then
        printf '%s\n' "$EPOCHSECONDS"
    else
        date +%s
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
