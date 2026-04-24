#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/disk-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# fake df output so the tests do not depend on this machine's disks
cat > "$WORK/fake-df" <<'FAKE'
#!/bin/bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/disk1 1000 500 500 50% /"
echo "/dev/disk2 1000 950 50 95% /data"
FAKE
chmod +x "$WORK/fake-df"
export DF_CMD="$WORK/fake-df"

test_reports_full_filesystem() {
    out=$("$ROOT/bin/disk-alert.sh" 90 || true)
    assert_eq "WARNING: /data is at 95% (/dev/disk2)" "$out" "reports /data"
}

test_exit_status_when_over() {
    assert_status 1 "over threshold exits 1" "$ROOT/bin/disk-alert.sh" 90
}

test_exit_status_when_ok() {
    assert_status 0 "under threshold exits 0" "$ROOT/bin/disk-alert.sh" 99
}

# inode output in the two layouts we know: macOS first, then GNU
cat > "$WORK/fake-dfi-mac" <<'FAKE'
#!/bin/bash
echo "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on"
echo "/dev/disk1 1000 500 500 50% 100 900 10% /"
echo "/dev/disk3 1000 100 900 10% 990 10 99% /Volumes/My Disk"
FAKE
cat > "$WORK/fake-dfi-gnu" <<'FAKE'
#!/bin/bash
echo "Filesystem Inodes IUsed IFree IUse% Mounted on"
echo "/dev/sda1 1000 100 900 10% /"
echo "/dev/sdb1 1000 970 30 97% /var"
echo "tmpfs 0 0 0 - /dev"
FAKE
chmod +x "$WORK/fake-dfi-mac" "$WORK/fake-dfi-gnu"

test_inode_usage_macos_layout() {
    export DFI_CMD="$WORK/fake-dfi-mac"
    out=$("$ROOT/bin/disk-alert.sh" -i 95 99 || true)
    assert_eq "WARNING: /Volumes/My Disk has used 99% of its inodes (/dev/disk3)" "$out" "mount names with spaces survive"
}

test_inode_usage_gnu_layout() {
    export DFI_CMD="$WORK/fake-dfi-gnu"
    out=$("$ROOT/bin/disk-alert.sh" -i 95 99 || true)
    assert_eq "WARNING: /var has used 97% of its inodes (/dev/sdb1)" "$out" "GNU layout, dash rows ignored"
}

test_inodes_are_opt_in() {
    export DFI_CMD="$WORK/fake-dfi-gnu"
    assert_status 0 "no -i means no inode check" "$ROOT/bin/disk-alert.sh" 99
}

test_per_mount_override() {
    printf '# data is expected to be full\n\n/data 99\n' > "$WORK/limits"
    assert_status 0 "/data override raises its limit" "$ROOT/bin/disk-alert.sh" -c "$WORK/limits" 90
    printf '/data 50\n' > "$WORK/limits"
    assert_status 1 "an override can also lower it" "$ROOT/bin/disk-alert.sh" -c "$WORK/limits" 99
}

test_override_file_with_windows_line_endings() {
    printf '/data 99\r\n' > "$WORK/crlf-limits"
    assert_status 0 "limit is read as 99, not '99<CR>'" "$ROOT/bin/disk-alert.sh" -c "$WORK/crlf-limits" 90
}

test_bad_override_file() {
    printf '/data lots\n' > "$WORK/limits"
    assert_status 1 "bad line is an error" "$ROOT/bin/disk-alert.sh" -c "$WORK/limits"
    assert_status 1 "missing file is an error" "$ROOT/bin/disk-alert.sh" -c "$WORK/nope"
}

# a curl that records its arguments and fails the first STUB_FAILS times
cat > "$WORK/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >> "$STUB_LOG"
echo "--" >> "$STUB_LOG"
n=$(cat "$STUB_LOG.n" 2>/dev/null || echo 0)
echo $((n + 1)) > "$STUB_LOG.n"
[ "$n" -ge "${STUB_FAILS:-0}" ]
STUB
chmod +x "$WORK/curl"

test_webhook_receives_json() {
    export CURL_BIN="$WORK/curl" STUB_LOG="$WORK/hook1" TB_SLEEP=true
    "$ROOT/bin/disk-alert.sh" -w http://hooks.test/alert 90 >/dev/null
    payload=$(grep '^{' "$STUB_LOG")
    assert_eq '"alerts":["WARNING: /data is at 95% (/dev/disk2)"]}' "${payload#*,}" "alerts array"
    assert_eq "1" "$(grep -c '^http://hooks.test/alert$' "$STUB_LOG")" "posted to the URL"
}

test_webhook_not_called_when_all_is_well() {
    export CURL_BIN="$WORK/curl" STUB_LOG="$WORK/hook2" TB_SLEEP=true
    "$ROOT/bin/disk-alert.sh" -w http://hooks.test/alert 99 >/dev/null
    assert_eq "no" "$([ -e "$STUB_LOG" ] && echo yes || echo no)" "no request without findings"
}

test_webhook_is_retried_and_failure_keeps_exit_status() {
    export CURL_BIN="$WORK/curl" STUB_LOG="$WORK/hook3" TB_SLEEP=true STUB_FAILS=2
    rm -f "$WORK/hook3.n"
    "$ROOT/bin/disk-alert.sh" -w http://hooks.test/alert 90 >/dev/null 2>&1 || status=$?
    assert_eq "1" "${status:-0}" "exit status still reports the full disk"
    assert_eq "3" "$(cat "$WORK/hook3.n")" "third attempt delivered"
    unset STUB_FAILS
}

test_json_output() {
    out=$("$ROOT/bin/disk-alert.sh" -j 90 || true)
    case $out in
        '{"host":"'*'","alerts":["WARNING: /data is at 95% (/dev/disk2)"]}') assert_eq 1 1 "one JSON document" ;;
        *) assert_eq '{"host":...,"alerts":[...]}' "$out" "one JSON document" ;;
    esac
    assert_eq "" "$("$ROOT/bin/disk-alert.sh" -j 99)" "silent when all is well"
    assert_status 1 "exit status unchanged" "$ROOT/bin/disk-alert.sh" -j 90
}

# df output like a Mac's: pseudo filesystems that always report 100%
cat > "$WORK/fake-df-mac" <<'FAKE'
#!/bin/bash
echo "Filesystem 512-blocks Used Available Capacity Mounted on"
echo "/dev/disk3s1s1 1000 500 500 50% /"
echo "devfs 410 410 0 100% /dev"
echo "map auto_home 0 0 0 100% /System/Volumes/Data/home"
echo "/dev/disk3s5 1000 950 50 95% /System/Volumes/Data"
echo "/dev/disk9 1000 990 10 99% /Volumes/Backup Drive"
FAKE
chmod +x "$WORK/fake-df-mac"

test_pseudo_filesystems_are_skipped() {
    out=$(DF_CMD="$WORK/fake-df-mac" "$ROOT/bin/disk-alert.sh" 90 || true)
    assert_eq "WARNING: /System/Volumes/Data is at 95% (/dev/disk3s5)
WARNING: /Volumes/Backup Drive is at 99% (/dev/disk9)" "$out" "devfs and map are not reported"
}

test_all_filesystems_with_dash_a() {
    out=$(DF_CMD="$WORK/fake-df-mac" "$ROOT/bin/disk-alert.sh" -a 90 || true)
    assert_contains "$out" "WARNING: /dev is at 100% (devfs)" "devfs shows up with -a"
}

test_extra_skip_regex() {
    out=$(DF_CMD="$WORK/fake-df-mac" "$ROOT/bin/disk-alert.sh" -x '^/Volumes/|disk3s5$' 90 || true)
    assert_eq "" "$out" "mount point and device matches both skip"
    DF_CMD="$WORK/fake-df-mac" assert_status 0 "nothing left to report" "$ROOT/bin/disk-alert.sh" -x '^/Volumes/|/Data$' 90
}

test_bad_threshold() {
    assert_status 2 "non numeric threshold" "$ROOT/bin/disk-alert.sh" lots
}

run_tests
