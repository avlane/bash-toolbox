# bash-toolbox

Small shell scripts I keep reaching for: backups, log handling, disk checks and
a few other chores. Nothing here is clever, it is just written down once.

## Scripts

All scripts live in `bin/`. Run them with no arguments (or the wrong number) to
get a usage line.

| script | what it does |
| --- | --- |
| `backup.sh SRC DEST` | tar+gzip `SRC` into `DEST/NAME-DATE.tar.gz` |
| `rotate-backups.sh DIR DAYS` | delete `*.tar.gz` in `DIR` older than `DAYS` days |
| `disk-alert.sh [PCT]` | print filesystems at or over `PCT` percent (default 90); exit 1 if any |
| `saferm.sh FILE...` | move files to `~/.saferm-trash` (or `$SAFERM_TRASH`) with a timestamp suffix |
| `tail-logs.sh FILE...` | follow several logs, each line prefixed with the file name |
| `healthcheck.sh HOST PORT` | exit 0 if the TCP port is open, 1 if not |
| `git-stale-branches.sh [DAYS] [REPO]` | list local branches without commits for `DAYS` days (default 90) |
| `bootstrap-dotfiles.sh DIR` | link every file in `DIR` as `~/.name`, keeping `.bak` copies |

## Tests

```
make test        # or: bash tests/run.sh
```

`tests/harness.sh` is a small assert-style harness; each `tests/test_*.sh`
sources it. Tests use temporary directories and do not touch your home.

## Portability

Developed on macOS (bash 3.2 at `/bin/bash`) and meant to also work on Linux.
`git-stale-branches.sh` tries BSD `date -v` first and then GNU `date -d`.
`healthcheck.sh` needs `nc` with `-z` and `-w`.
