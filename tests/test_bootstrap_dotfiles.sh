#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")" && pwd -P)   # resolve /var -> /private/var on macOS
trap 'rm -rf "$WORK"' EXIT

BS="$ROOT/bin/bootstrap-dotfiles.sh"

fresh() {   # fresh NAME - new repo + home under $WORK/NAME
    mkdir -p "$WORK/$1/repo" "$WORK/$1/home"
    echo "export A=1" > "$WORK/$1/repo/profile"
    echo "set number" > "$WORK/$1/repo/vimrc"
}

test_links_every_entry() {
    fresh all
    "$BS" -t "$WORK/all/home" "$WORK/all/repo" >/dev/null
    assert_eq "$WORK/all/repo/profile" "$(readlink "$WORK/all/home/.profile")" ".profile is linked"
    assert_eq "$WORK/all/repo/vimrc" "$(readlink "$WORK/all/home/.vimrc")" ".vimrc is linked"
}

test_existing_file_is_backed_up() {
    fresh bak
    echo "old" > "$WORK/bak/home/.vimrc"
    "$BS" -t "$WORK/bak/home" "$WORK/bak/repo" >/dev/null
    assert_eq "old" "$(cat "$WORK/bak/home/.vimrc.bak")" "previous file kept as .bak"
}

test_dry_run_changes_nothing() {
    fresh dry
    "$BS" -n -t "$WORK/dry/home" "$WORK/dry/repo" >/dev/null
    assert_eq "0" "$(ls -A "$WORK/dry/home" | wc -l | tr -d ' ')" "nothing created"
}

test_manifest_selects_and_renames() {
    fresh man
    printf '# only these\nvimrc\nprofile .config/shell/profile\nmissing\n' > "$WORK/man/manifest"
    "$BS" -t "$WORK/man/home" -m "$WORK/man/manifest" "$WORK/man/repo" >/dev/null 2>&1
    assert_eq "$WORK/man/repo/profile" "$(readlink "$WORK/man/home/.config/shell/profile")" "custom target, parent created"
    assert_eq "no" "$([ -e "$WORK/man/home/.profile" ] && echo yes || echo no)" "unlisted default target not made"
}

test_second_run_changes_nothing() {
    fresh again
    "$BS" -t "$WORK/again/home" "$WORK/again/repo" >/dev/null
    out=$("$BS" -t "$WORK/again/home" "$WORK/again/repo")
    assert_eq "0" "$(ls -A "$WORK/again/home" | grep -c '\.bak$')" "no .bak files after a second run"
    case $out in
        *"already linked"*"already linked"*) assert_eq 1 1 "reports already linked" ;;
        *) assert_eq "already linked x2" "$out" "reports already linked" ;;
    esac
}

test_wrong_symlink_is_replaced_without_backup() {
    fresh stale
    ln -s /nonexistent "$WORK/stale/home/.vimrc"
    "$BS" -t "$WORK/stale/home" "$WORK/stale/repo" >/dev/null
    assert_eq "$WORK/stale/repo/vimrc" "$(readlink "$WORK/stale/home/.vimrc")" "link now points at the repo"
    assert_eq "0" "$(ls -A "$WORK/stale/home" | grep -c '\.bak$')" "a dangling link is not worth a .bak"
}

test_host_overlay_wins() {
    fresh host
    mkdir -p "$WORK/host/repo/hosts/laptop" "$WORK/host/repo/hosts/server"
    echo "laptop vimrc" > "$WORK/host/repo/hosts/laptop/vimrc"
    echo "server only" > "$WORK/host/repo/hosts/server/tmux.conf"
    "$BS" -H laptop -t "$WORK/host/home" "$WORK/host/repo" >/dev/null
    assert_eq "laptop vimrc" "$(cat "$WORK/host/home/.vimrc")" "overlay file is linked"
    assert_eq "export A=1" "$(cat "$WORK/host/home/.profile")" "files without overlay come from the top level"
    assert_eq "no" "$([ -e "$WORK/host/home/.hosts" ] && echo yes || echo no)" "hosts directory is not linked"
    assert_eq "no" "$([ -e "$WORK/host/home/.tmux.conf" ] && echo yes || echo no)" "other hosts' files are ignored"
}

test_uninstall_removes_links_and_restores_backups() {
    fresh un
    echo "my old vimrc" > "$WORK/un/home/.vimrc"
    "$BS" -t "$WORK/un/home" "$WORK/un/repo" >/dev/null
    assert_eq "my old vimrc" "$(cat "$WORK/un/home/.vimrc.bak")" "install kept the old file"
    "$BS" -u -t "$WORK/un/home" "$WORK/un/repo" >/dev/null
    assert_eq "my old vimrc" "$(cat "$WORK/un/home/.vimrc")" "backup put back"
    assert_file_missing "$WORK/un/home/.vimrc.bak" "backup consumed"
    assert_file_missing "$WORK/un/home/.profile" "link without a backup just goes away"
}

test_uninstall_dry_run_and_foreign_links() {
    fresh un2
    ln -s /elsewhere "$WORK/un2/home/.vimrc"
    out=$("$BS" -u -n -t "$WORK/un2/home" "$WORK/un2/repo")
    assert_contains "$out" "leaving $WORK/un2/home/.vimrc alone" "foreign link is not touched"
    assert_eq "/elsewhere" "$(readlink "$WORK/un2/home/.vimrc")" "still there after dry run"
}

test_manifest_with_windows_line_endings() {
    fresh crlf
    printf 'vimrc\r\nprofile .config/profile\r\n' > "$WORK/crlf/manifest"
    "$BS" -t "$WORK/crlf/home" -m "$WORK/crlf/manifest" "$WORK/crlf/repo" >/dev/null 2>&1
    assert_eq "$WORK/crlf/repo/vimrc" "$(readlink "$WORK/crlf/home/.vimrc")" "name without a trailing CR"
    assert_eq "$WORK/crlf/repo/profile" "$(readlink "$WORK/crlf/home/.config/profile")" "target without a trailing CR"
}

test_usage_error() {
    assert_status 2 "no directory" "$BS"
}

run_tests
