#!/bin/bash
# bootstrap-dotfiles.sh - symlink dotfiles from a repo into $HOME
# usage: bootstrap-dotfiles.sh DOTFILES_DIR
# Every file in DOTFILES_DIR named "foo" is linked as ~/.foo. An existing
# file is moved to ~/.foo.bak first.

set -eu

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "usage: bootstrap-dotfiles.sh DOTFILES_DIR" >&2
    exit 2
fi

SRC=$(cd "$1" && pwd)

for path in "$SRC"/*; do
    name=$(basename "$path")
    target="$HOME/.$name"
    if [[ -e "$target" || -L "$target" ]]; then
        mv "$target" "$target.bak"
        echo "backed up $target"
    fi
    ln -s "$path" "$target"
    echo "linked $target -> $path"
done
