#!/usr/bin/env bash
# gen-systemd.sh - print a systemd service unit for a command
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: gen-systemd.sh -n NAME -c COMMAND [-t ONCALENDAR] [-o DIR] [-d DESCRIPTION]
                      [-u USER] [-w WORKDIR] [-e VAR=VALUE]...

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
  -t ONCALENDAR   also generate a timer that runs the service on this schedule
  -o DIR          write NAME.service (and NAME.timer) into DIR instead of stdout
  -h, --help      show this help
USAGE
}

tb_handle_help usage "$@"

name= cmd= desc= user= workdir= calendar= outdir=
envs=()
while getopts ':n:c:d:u:w:e:t:o:h' opt; do
    case $opt in
        n) name=$OPTARG ;;
        c) cmd=$OPTARG ;;
        d) desc=$OPTARG ;;
        u) user=$OPTARG ;;
        w) workdir=$OPTARG ;;
        e) envs+=("$OPTARG") ;;
        t) calendar=$OPTARG ;;
        o) outdir=$OPTARG ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ -n $name && -n $cmd ]] || tb_usage_error "-n and -c are required"
[[ $name =~ ^[A-Za-z0-9_.@-]+$ ]] || tb_usage_error "unit name has characters systemd does not allow"
[[ $cmd == /* ]] || tb_usage_error "COMMAND must start with an absolute path"

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
    echo
    echo "[Install]"
    echo "WantedBy=timers.target"
}

if [[ -n $outdir ]]; then
    mkdir -p "$outdir"
    emit_service > "$outdir/$name.service"
    echo "wrote $outdir/$name.service"
    if [[ -n $calendar ]]; then
        emit_timer > "$outdir/$name.timer"
        echo "wrote $outdir/$name.timer"
    fi
else
    emit_service
    if [[ -n $calendar ]]; then
        echo
        echo "# ---- $name.timer ----"
        emit_timer
    fi
fi
