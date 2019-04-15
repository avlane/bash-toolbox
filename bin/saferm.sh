#!/bin/bash
# saferm.sh - move files to a trash directory instead of deleting them
# usage: saferm.sh FILE...
# The trash directory is $SAFERM_TRASH (default ~/.saferm-trash).

TRASH=${SAFERM_TRASH:-$HOME/.saferm-trash}

if [ $# -eq 0 ]; then
    echo "usage: saferm.sh FILE..."
    exit 2
fi

mkdir -p $TRASH

for f in $@; do
    if [ ! -e $f ]; then
        echo "saferm.sh: $f: no such file"
        continue
    fi
    mv $f $TRASH/`basename $f`.`date +%s`
    echo "moved $f to trash"
done
