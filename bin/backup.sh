#!/bin/bash
# backup.sh - tar up a directory into a dated archive
# usage: backup.sh SOURCE_DIR DEST_DIR

set -eu

usage() {
    echo "usage: backup.sh SOURCE_DIR DEST_DIR"
}

if [[ $# -ne 2 ]]; then
    usage
    exit 2
fi

SRC=${1%/}
DEST=$2

if [[ ! -d "$SRC" ]]; then
    echo "backup.sh: $SRC is not a directory" >&2
    exit 1
fi

DATE=$(date +%Y%m%d-%H%M%S)
NAME=$(basename "$SRC")
ARCHIVE="$DEST/$NAME-$DATE.tar.gz"

mkdir -p "$DEST"
tar -czf "$ARCHIVE" -C "$(dirname "$SRC")" "$NAME"
echo "wrote $ARCHIVE"
