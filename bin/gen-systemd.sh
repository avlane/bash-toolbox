#!/usr/bin/env bash
# gen-systemd.sh - print a systemd service unit for a command
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../lib/common.sh"

usage() {
    cat <<'USAGE'
usage: gen-systemd.sh -n NAME -c COMMAND [-d DESCRIPTION] [-u USER] [-w WORKDIR] [-e VAR=VALUE]...

Print a NAME.service unit to standard output. COMMAND must start with an
absolute path, as systemd requires for ExecStart.

options:
  -n NAME         unit name, without the .service suffix
  -c COMMAND      command line to run
  -d DESCRIPTION  Description= (default: NAME)
  -u USER         User=
  -w WORKDIR      WorkingDirectory=
  -e VAR=VALUE    Environment= entry, repeatable
  -h, --help      show this help
USAGE
}

tb_handle_help usage "$@"

name= cmd= desc= user= workdir=
envs=()
while getopts ':n:c:d:u:w:e:h' opt; do
    case $opt in
        n) name=$OPTARG ;;
        c) cmd=$OPTARG ;;
        d) desc=$OPTARG ;;
        u) user=$OPTARG ;;
        w) workdir=$OPTARG ;;
        e) envs+=("$OPTARG") ;;
        h) usage; exit 0 ;;
        :) tb_usage_error "option -$OPTARG needs an argument" ;;
        *) tb_usage_error "unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ -n $name && -n $cmd ]] || tb_usage_error "-n and -c are required"
[[ $name =~ ^[A-Za-z0-9_.@-]+$ ]] || tb_usage_error "unit name has characters systemd does not allow"
[[ $cmd == /* ]] || tb_usage_error "COMMAND must start with an absolute path"

echo "[Unit]"
echo "Description=${desc:-$name}"
echo "After=network-online.target"
echo
echo "[Service]"
echo "Type=simple"
echo "ExecStart=$cmd"
[[ -z $user ]] || echo "User=$user"
[[ -z $workdir ]] || echo "WorkingDirectory=$workdir"
for e in ${envs[@]+"${envs[@]}"}; do
    echo "Environment=\"$e\""
done
echo "Restart=on-failure"
echo
echo "[Install]"
echo "WantedBy=multi-user.target"
