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

test_bad_override_file() {
    printf '/data lots\n' > "$WORK/limits"
    assert_status 1 "bad line is an error" "$ROOT/bin/disk-alert.sh" -c "$WORK/limits"
    assert_status 1 "missing file is an error" "$ROOT/bin/disk-alert.sh" -c "$WORK/nope"
}

test_bad_threshold() {
    assert_status 2 "non numeric threshold" "$ROOT/bin/disk-alert.sh" lots
}

run_tests
