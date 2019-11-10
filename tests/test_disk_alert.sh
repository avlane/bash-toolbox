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

run_tests
