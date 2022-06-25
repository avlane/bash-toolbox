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

test_usage_error() {
    assert_status 2 "no directory" "$BS"
}

run_tests
