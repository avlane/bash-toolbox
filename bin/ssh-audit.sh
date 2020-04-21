#!/usr/bin/env bash
# ssh-audit.sh - look over an ssh directory for the usual problems
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: ssh-audit.sh [-d SSH_DIR]

Checks, in SSH_DIR (default ~/.ssh):
  - the directory is not accessible by group or others
  - private keys are not accessible by group or others
  - private keys without a passphrase (reported as a warning)
  - weak keys: DSA, or RSA smaller than 2048 bits

Prints one line per finding. Exit status is 1 if anything was found, else 0.

options:
  -d DIR      directory to audit
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

dir=$HOME/.ssh
while getopts ':d:h' opt; do
    case $opt in
        d) dir=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ -d $dir ]] || tb_die "$dir is not a directory"
tb_require_cmd ssh-keygen

findings=0
finding() {
    echo "$1: $2"
    findings=$((findings + 1))
}

# open_to_others PATH - true if group or other have any permission bit
open_to_others() {
    local mode
    mode=$(ls -ld "$1" | cut -c1-10)
    [[ ${mode:4:6} != ------ ]]
}

if open_to_others "$dir"; then
    finding "$dir" "directory is accessible by group or others (want chmod 700)"
fi

# a private key starts with a BEGIN ... PRIVATE KEY line
is_private_key() {
    head -n 1 "$1" 2>/dev/null | grep -q -- '-----BEGIN .*PRIVATE KEY-----'
}

for key in "$dir"/*; do
    [[ -f $key ]] || continue
    is_private_key "$key" || continue

    if open_to_others "$key"; then
        finding "$key" "private key is accessible by group or others (want chmod 600)"
    fi

    # ssh-keygen -y with an empty passphrase only succeeds if there is none
    if ssh-keygen -y -P '' -f "$key" >/dev/null 2>&1; then
        finding "$key" "private key has no passphrase"
    fi

    # "3072 SHA256:... comment (RSA)"
    if info=$(ssh-keygen -l -f "$key" 2>/dev/null); then
        bits=${info%% *}
        type=${info##*(}
        type=${type%)}
        case $type in
            DSA) finding "$key" "DSA keys are weak, replace with ed25519" ;;
            RSA) if (( bits < 2048 )); then
                     finding "$key" "RSA key is only $bits bits"
                 fi ;;
        esac
    fi
done

(( findings == 0 )) || exit 1
echo "no findings in $dir"
