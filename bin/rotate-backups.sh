#!/bin/bash
# rotate-backups.sh - delete old archives from a backup directory
# usage: rotate-backups.sh DIR DAYS
# Deletes *.tar.gz files in DIR that are older than DAYS days.

if [ $# -ne 2 ]; then
    echo "usage: rotate-backups.sh DIR DAYS"
    exit 2
fi

DIR=$1
DAYS=$2

for f in `find "$DIR" -maxdepth 1 -name '*.tar.gz' -mtime +$DAYS`; do
    echo "removing $f"
    rm "$f"
done
