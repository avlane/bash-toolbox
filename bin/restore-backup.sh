#!/usr/bin/env bash
# restore-backup.sh - unpack an archive made by backup.sh, carefully
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: restore-backup.sh [-f] [-l] ARCHIVE DEST_DIR

Verify ARCHIVE against ARCHIVE.sha256 (when that file exists) and extract it
into DEST_DIR. Refuses to extract if

  - the checksum does not match,
  - an entry has an absolute path or a .. component,
  - DEST_DIR already contains files (override with -f).

options:
  -l          only list the archive's contents
  -f          extract even if DEST_DIR is not empty
  -h, --help  show this help
USAGE
}

tb_handle_help usage "$@"

force=0
list_only=0
while getopts ':flh' opt; do
    case $opt in
        f) force=1 ;;
        l) list_only=1 ;;
        h) usage; exit 0 ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 2 ]] || tb_usage_error "expected ARCHIVE and DEST_DIR"
archive=$1
dest=$2
[[ -f $archive ]] || tb_die "$archive is not a file"

if [[ -f $archive.sha256 ]]; then
    tb_sha256_verify "$archive.sha256" || tb_die "checksum mismatch for $archive"
    tb_log "checksum ok"
else
    tb_warn "no $archive.sha256, skipping the checksum check"
fi

tb_readlines entries < <(tar -tzf "$archive")
for entry in ${entries[@]+"${entries[@]}"}; do
    case $entry in
        /*) tb_die "refusing to extract: absolute path in archive: $entry" ;;
    esac
    # a ".." component can climb out of DEST_DIR; "file..txt" is fine
    case /$entry/ in
        */../*) tb_die "refusing to extract: entry leaves the target directory: $entry" ;;
    esac
done

if (( list_only )); then
    printf '%s\n' ${entries[@]+"${entries[@]}"}
    exit 0
fi

if [[ -d $dest && -n $(ls -A "$dest") ]] && (( ! force )); then
    tb_die "$dest is not empty (use -f to extract anyway)"
fi
mkdir -p "$dest"
tar -xzf "$archive" -C "$dest"
echo "restored ${#entries[@]} entries to $dest"
