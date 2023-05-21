#!/bin/bash
. "$(dirname "$0")/harness.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/systemd-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

test_service_golden_output() {
    cat > "$WORK/expected" <<'UNIT'
[Unit]
Description=Static web
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server 8080
User=www
WorkingDirectory=/srv/www
Environment="MODE=prod"
Environment="GREETING=hello world"
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
    "$ROOT/bin/gen-systemd.sh" -n web -d "Static web" -c "/usr/bin/python3 -m http.server 8080" \
        -u www -w /srv/www -e MODE=prod -e "GREETING=hello world" > "$WORK/actual"
    assert_eq "" "$(diff "$WORK/expected" "$WORK/actual")" "service unit matches"
}

test_timer_makes_oneshot_service() {
    "$ROOT/bin/gen-systemd.sh" -n nightly -c /usr/local/bin/job -t "*-*-* 02:30:00" -o "$WORK/units" >/dev/null
    assert_file_exists "$WORK/units/nightly.service" "service written"
    assert_file_exists "$WORK/units/nightly.timer" "timer written"
    assert_eq "Type=oneshot" "$(grep '^Type=' "$WORK/units/nightly.service")" "timer jobs are oneshot"
    assert_eq "OnCalendar=*-*-* 02:30:00" "$(grep '^OnCalendar=' "$WORK/units/nightly.timer")" "calendar copied"
    assert_eq "0" "$(grep -c '^\[Install\]' "$WORK/units/nightly.service")" "service has no Install section"
}

test_hardening_options() {
    out=$("$ROOT/bin/gen-systemd.sh" -n job -c /usr/local/bin/job -H -W /var/lib/job -W /var/log/job)
    assert_eq "ProtectSystem=strict" "$(echo "$out" | grep '^ProtectSystem=')" "sandboxing present"
    assert_eq "ReadWritePaths=/var/lib/job
ReadWritePaths=/var/log/job" "$(echo "$out" | grep '^ReadWritePaths=')" "writable paths listed"
    plain=$("$ROOT/bin/gen-systemd.sh" -n job -c /usr/local/bin/job)
    assert_eq "0" "$(echo "$plain" | grep -c 'ProtectSystem')" "off by default"
}

test_writable_paths_need_hardening() {
    assert_status 2 "-W without -H" "$ROOT/bin/gen-systemd.sh" -n job -c /bin/true -W /tmp
}

test_rejects_relative_command() {
    assert_status 2 "relative ExecStart" "$ROOT/bin/gen-systemd.sh" -n x -c ./run.sh
}

test_rejects_bad_name() {
    assert_status 2 "slash in unit name" "$ROOT/bin/gen-systemd.sh" -n a/b -c /bin/true
}

run_tests
