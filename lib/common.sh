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
