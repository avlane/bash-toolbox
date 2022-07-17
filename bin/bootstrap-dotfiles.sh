#!/usr/bin/env bash
# bootstrap-dotfiles.sh - symlink a dotfiles repository into a home directory
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: bootstrap-dotfiles.sh [-n] [-t TARGET_DIR] [-m MANIFEST] DOTFILES_DIR

Link entries of DOTFILES_DIR into TARGET_DIR (default $HOME). An entry named
"zshrc" becomes TARGET_DIR/.zshrc. A file or directory that is already in the
way is moved to NAME.bak first.

Without -m every entry in DOTFILES_DIR is linked. A MANIFEST lists exactly what
to link, one entry per line: "NAME" for the default ".NAME" target, or
"NAME TARGET" with TARGET a path relative to TARGET_DIR, for example
"profile .config/shell/profile". Neither part may contain spaces.
Blank lines and lines starting with # are ignored.

options:
  -n          dry run: print what would happen
  -t DIR      link into DIR instead of $HOME
  -m FILE     manifest of entries to link
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

dry=0
target_dir=$HOME
manifest=
while getopts ':nt:m:h' opt; do
    case $opt in
        n) dry=1 ;;
        t) target_dir=$OPTARG ;;
        m) manifest=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 1 && -d $1 ]] || tb_usage_error "expected a DOTFILES_DIR"
src=$(cd "$1" && pwd -P)
[[ -d $target_dir ]] || tb_die "$target_dir is not a directory"

link_one() {
    local name=$1 rel=$2 from="$src/$1" to
    to="$target_dir/$rel"
    if [[ ! -e $from && ! -L $from ]]; then
        tb_warn "$name is not in $src, skipping"
        return 0
    fi
    if [[ -L $to && $(readlink "$to") == "$from" ]]; then
        echo "already linked $to"
        return 0
    fi
    if (( dry )); then
        echo "would link $to -> $from"
        return 0
    fi
    mkdir -p "$(dirname "$to")"
    if [[ -L $to && ! -e $to ]]; then
        rm "$to"    # a dangling link has nothing worth keeping
    elif [[ -e $to || -L $to ]]; then
        mv "$to" "$to.bak"
        echo "backed up $to"
    fi
    ln -s "$from" "$to"
    echo "linked $to -> $from"
}

if [[ -n $manifest ]]; then
    [[ -r $manifest ]] || tb_die "cannot read $manifest"
    while read -r name rel; do
        if [[ -z $name || $name == \#* ]]; then
            continue
        fi
        link_one "$name" "${rel:-.$name}"
    done < "$manifest"
else
    for path in "$src"/*; do
        [[ -e $path || -L $path ]] || continue
        name=$(basename "$path")
        link_one "$name" ".$name"
    done
fi
