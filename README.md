# bash-toolbox

Small shell scripts I keep reaching for: backups, log handling, disk checks and
a few other chores. Nothing here is clever, it is just written down once.

## Scripts

All scripts live in `bin/`. Every script supports `--help` (or `-h`) and exits 2
on a usage error. Shared helpers are in `lib/common.sh`.

| script | what it does |
| --- | --- |
| `backup.sh [-n] [-k N] [-x PAT] SRC DEST` | tar+gzip `SRC` into `DEST/NAME-DATE.tar.gz`, atomically; optionally keep only the newest N |
| `rotate-backups.sh DIR DAYS` | delete `*.tar.gz` in `DIR` older than `DAYS` days |
| `rotate-logs.sh [-k N] FILE...` | numbered copy-and-truncate rotation |
| `disk-alert.sh [PCT]` | print filesystems at or over `PCT` percent (default 90); exit 1 if any |
| `saferm.sh FILE...` | move files to `~/.saferm-trash` (or `$SAFERM_TRASH`) with a timestamp suffix |
| `tail-logs.sh FILE...` | follow several logs, each line prefixed with the file name |
| `healthcheck.sh HOST PORT` / `-u URL` | TCP or HTTP check; exit 0 healthy, 1 unhealthy |
| `retry.sh [-t N] [-d S] CMD...` | run a command again with exponential backoff |
| `json-get.sh [-r] KEY [FILE]` | read a value from JSON; uses jq, with a limited pure-bash fallback |
| `git-maint.sh [-n] [-a] [REPO]` | prune, reflog expire and gc |
| `git-stale-branches.sh [DAYS] [REPO]` | list local branches without commits for `DAYS` days (default 90) |
| `ssh-audit.sh [-d DIR]` | key permissions, missing passphrases, weak keys, duplicate authorized_keys, unhashed known_hosts |
| `bootstrap-dotfiles.sh DIR` | link every file in `DIR` as `~/.name`, keeping `.bak` copies |

## Tests

```
make test        # or: bash tests/run.sh
```

`tests/harness.sh` is a small assert-style harness; each `tests/test_*.sh`
sources it. Tests use temporary directories and do not touch your home.

## Portability

Developed on macOS, where `/bin/bash` is 3.2, and meant to also run on Linux.
The scripts therefore avoid bash 4+ features unless they are guarded.

Known differences that the scripts deal with:

- `git-stale-branches.sh` tries BSD `date -v` first and then GNU `date -d`.
- `healthcheck.sh` needs an `nc` that supports `-z` and `-w`.
- `ssh-audit.sh` reads permissions from `ls -l` rather than `stat`, because
  `stat` flags differ between BSD and GNU.
- With `set -u`, bash 3.2 and 4.0 to 4.3 treat an empty array as unset, so
  arrays are expanded as `${arr[@]+"${arr[@]}"}`.
