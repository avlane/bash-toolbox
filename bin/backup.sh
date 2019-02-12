#!/bin/bash
# backup.sh - tar up a directory into a dated archive
# usage: backup.sh SOURCE_DIR DEST_DIR

SRC=$1
DEST=$2

DATE=`date +%Y%m%d-%H%M%S`
NAME=`basename $SRC`

mkdir -p $DEST
tar -czf $DEST/$NAME-$DATE.tar.gz -C `dirname $SRC` $NAME
echo "wrote $DEST/$NAME-$DATE.tar.gz"
