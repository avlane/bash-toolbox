#!/usr/bin/env bash
# backup.sh - tar up a directory into a dated archive
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: backup.sh [-n] [-z gzip|zstd] [-k COUNT] [-x PATTERN]... [-X FILE] SOURCE_DIR DEST_DIR

Create DEST_DIR/NAME-YYYYmmdd-HHMMSS.tar.gz (or .tar.zst with -z zstd) from
SOURCE_DIR, plus a NAME-...tar.gz.sha256 file with its SHA-256 checksum (verify with
restore-backup.sh, or sha256sum -c / shasum -a 256 -c). The archive is written
to a temporary file first and renamed, so a failed run never leaves a
half-written archive behind.

options:
  -z TOOL     compression: gzip (default) or zstd (smaller and faster, but needs
              the zstd program; restore-backup.sh reads both)
  -k COUNT    afterwards keep only the newest COUNT archives for this source
  -x PATTERN  exclude paths matching PATTERN (repeatable, passed to tar)
  -X FILE     read exclude patterns from FILE, one per line
  -n          dry run: say what would be written, change nothing
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

dry=0
keep=0
compress=gzip
excludes=()
while getopts ':x:X:k:z:nh' opt; do
    case $opt in
        k) keep=$OPTARG ;;
        z) compress=$OPTARG ;;
        x) excludes+=(--exclude "$OPTARG") ;;
        X) [[ -r $OPTARG ]] || tb_die "cannot read exclude file $OPTARG"
           excludes+=(--exclude-from "$OPTARG") ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

case $compress in
    gzip) ext=.tar.gz ;;
    zstd) ext=.tar.zst; tb_require_cmd zstd ;;
    *) tb_usage_error "-z must be gzip or zstd" ;;
esac
[[ $keep =~ ^[0-9]+$ ]] || tb_usage_error "-k needs a number"
[[ $# -eq 2 ]] || tb_usage_error "expected SOURCE_DIR and DEST_DIR"

src=${1%/}
dest=$2
[[ -d $src ]] || tb_die "$src is not a directory"
# resolve '.', '..' and relative paths so the archive is named after the real directory
src=$(cd "$src" && pwd -P)
[[ $src != / ]] || tb_die "refusing to back up the root directory"

name=$(basename "$src")
archive="$dest/$name-$(date +%Y%m%d-%H%M%S)$ext"

if (( dry )); then
    echo "would write $archive"
    exit 0
fi

mkdir -p "$dest"
tmp=$(mktemp "$dest/.backup.XXXXXX")
trap 'rm -f "$tmp"' EXIT

# GNU tar exits 1 for "file changed as we read it" - the archive is still
# complete enough to keep, so that case is a warning there. bsdtar uses 1 for
# real errors, so it is never excused.
rc=0
if [[ $compress == zstd ]]; then
    # tar's own exit status is the first element of PIPESTATUS, zstd's the second
    set +e
    tar -cf - ${excludes[@]+"${excludes[@]}"} -C "$(dirname "$src")" "$name" | zstd -q -f -o "$tmp"
    statuses=("${PIPESTATUS[@]}")
    set -e
    rc=${statuses[0]}
    (( statuses[1] == 0 )) || tb_die "zstd failed with status ${statuses[1]}"
else
    tar -czf "$tmp" ${excludes[@]+"${excludes[@]}"} -C "$(dirname "$src")" "$name" || rc=$?
fi
if (( rc == 1 )) && tar --version 2>&1 | grep -q 'GNU tar'; then
    tb_warn "some files changed while they were being archived"
elif (( rc != 0 )); then
    tb_die "tar failed with status $rc"
fi

# read the whole archive back before trusting it: this catches a truncated or
# corrupt compressed stream (a full disk, for example) while the source still exists
if [[ $compress == zstd ]]; then
    zstd -dc "$tmp" 2>/dev/null | tar -tf - >/dev/null 2>&1 || tb_die "the new archive cannot be read back, not keeping it"
else
    tar -tzf "$tmp" >/dev/null 2>&1 || tb_die "the new archive cannot be read back, not keeping it"
fi
mv "$tmp" "$archive"
tb_sha256 "$archive" > "$archive.sha256"
echo "wrote $archive"

tb_prune_newest "$keep" "$dest" "$name" "$ext"
