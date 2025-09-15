#!/usr/bin/env bash
# gen-systemd.sh - print a systemd service unit for a command
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: gen-systemd.sh -n NAME -c COMMAND [-t ONCALENDAR] [-R SECONDS] [-o DIR] [-d DESCRIPTION]
                      [-u USER] [-w WORKDIR] [-e VAR=VALUE]... [-H] [-W PATH]... [-i] [-V]

Print a NAME.service unit to standard output. COMMAND must start with an
absolute path, as systemd requires for ExecStart.

With -t the service becomes a one-shot job and a matching NAME.timer is
generated too, for example -t daily or -t '*-*-* 02:30:00'. Enable the timer,
not the service: systemctl enable --now NAME.timer

options:
  -n NAME         unit name, without the .service suffix
  -c COMMAND      command line to run
  -d DESCRIPTION  Description= (default: NAME)
  -u USER         User=
  -w WORKDIR      WorkingDirectory=
  -e VAR=VALUE    Environment= entry, repeatable
  -H              add sandboxing: NoNewPrivileges, PrivateTmp, ProtectSystem=strict,
                  ProtectHome=read-only, ProtectKernelTunables, RestrictSUIDSGID
  -W PATH         with -H, a path the service may still write to
                  (ReadWritePaths=), repeatable
  -t ONCALENDAR   also generate a timer that runs the service on this schedule
  -i              install as user units into ${XDG_CONFIG_HOME:-~/.config}/systemd/user
                  (same as -o with that directory) and print the systemctl commands
  -V              verify the generated files with systemd-analyze verify
                  (skipped with a warning when systemd-analyze is not installed)
  -R SECONDS      with -t, RandomizedDelaySec=: start up to this long after the
                  scheduled time, so a fleet of machines does not hit a shared
                  server at the same second
  -o DIR          write NAME.service (and NAME.timer) into DIR instead of stdout
  -h, --help      show this help
USAGE
}

tb_handle_help usage "$@"

name= cmd= desc= user= workdir= calendar= outdir=
random_delay=
install=0
validate=0
harden=0
envs=()
writable=()
while getopts ':n:c:d:u:w:e:t:R:o:HW:iVh' opt; do
    case $opt in
        n) name=$OPTARG ;;
        c) cmd=$OPTARG ;;
        d) desc=$OPTARG ;;
        u) user=$OPTARG ;;
        w) workdir=$OPTARG ;;
        e) envs+=("$OPTARG") ;;
        t) calendar=$OPTARG ;;
        R) random_delay=$OPTARG ;;
        o) outdir=$OPTARG ;;
        H) harden=1 ;;
        i) install=1 ;;
        V) validate=1 ;;
        W) writable+=("$OPTARG") ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ -n $name && -n $cmd ]] || tb_usage_error "-n and -c are required"
[[ $name =~ ^[A-Za-z0-9_.@-]+$ ]] || tb_usage_error "unit name has characters systemd does not allow"
[[ $cmd == /* ]] || tb_usage_error "COMMAND must start with an absolute path"
if [[ -n $random_delay ]]; then
    [[ -n $calendar ]] || tb_usage_error "-R only makes sense together with -t"
    [[ $random_delay =~ ^[0-9]+$ ]] || tb_usage_error "-R needs a number of seconds"
fi
if (( ! harden )) && [[ ${#writable[@]} -gt 0 ]]; then
    tb_usage_error "-W only makes sense together with -H"
fi

emit_service() {
    echo "[Unit]"
    echo "Description=${desc:-$name}"
    echo "After=network-online.target"
    echo
    echo "[Service]"
    if [[ -n $calendar ]]; then
        echo "Type=oneshot"
    else
        echo "Type=simple"
    fi
    echo "ExecStart=$cmd"
    [[ -z $user ]] || echo "User=$user"
    [[ -z $workdir ]] || echo "WorkingDirectory=$workdir"
    for e in ${envs[@]+"${envs[@]}"}; do
        echo "Environment=\"$e\""
    done
    if (( harden )); then
        echo "NoNewPrivileges=true"
        echo "PrivateTmp=true"
        echo "ProtectSystem=strict"
        echo "ProtectHome=read-only"
        echo "ProtectKernelTunables=true"
        echo "RestrictSUIDSGID=true"
        for p in ${writable[@]+"${writable[@]}"}; do
            echo "ReadWritePaths=$p"
        done
    fi
    if [[ -z $calendar ]]; then
        echo "Restart=on-failure"
        echo
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    fi
}

emit_timer() {
    echo "[Unit]"
    echo "Description=Timer for ${desc:-$name}"
    echo
    echo "[Timer]"
    echo "OnCalendar=$calendar"
    echo "Persistent=true"
    [[ -z $random_delay ]] || echo "RandomizedDelaySec=$random_delay"
    echo
    echo "[Install]"
    echo "WantedBy=timers.target"
}

if (( install )); then
    [[ -z $outdir ]] || tb_usage_error "-i and -o cannot be combined"
    outdir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
fi

# verifying needs files, so without -o/-i write them to a temporary directory
tmpdir=
if (( validate )) && [[ -z $outdir ]]; then
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/gen-systemd.XXXXXX")
    trap 'rm -rf "$tmpdir"' EXIT
fi

verify_units() {
    local dir=$1 unit
    if ! command -v systemd-analyze >/dev/null 2>&1; then
        tb_warn "systemd-analyze not found, units were not verified"
        return 0
    fi
    for unit in "$dir/$name.service" "$dir/$name.timer"; do
        [[ -f $unit ]] || continue
        systemd-analyze verify "$unit" || tb_die "systemd-analyze rejected $unit"
    done
}

if [[ -n $outdir || -n $tmpdir ]]; then
    target=${outdir:-$tmpdir}
    outdir=$target
    mkdir -p "$outdir"
    emit_service > "$outdir/$name.service"
    echo "wrote $outdir/$name.service"
    if [[ -n $calendar ]]; then
        emit_timer > "$outdir/$name.timer"
        echo "wrote $outdir/$name.timer"
    fi
    (( ! validate )) || verify_units "$outdir"
    if (( install )); then
        main_unit=$name.service
        [[ -z $calendar ]] || main_unit=$name.timer
        echo "next: systemctl --user daemon-reload && systemctl --user enable --now $main_unit"
    fi
else
    emit_service
    if [[ -n $calendar ]]; then
        echo
        echo "# ---- $name.timer ----"
        emit_timer
    fi
fi
