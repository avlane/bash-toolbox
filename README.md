# bash-toolbox

Small shell scripts I keep reaching for: backups, log handling, disk checks and
a few other chores. Nothing here is clever, it is just written down once.

## Contents

- [Scripts](#scripts)
- [Examples](#examples)
- [Exit codes](#exit-codes)
- [Tests](#tests)
- [Continuous integration](#continuous-integration)
- [Portability](#portability)

See `CHANGELOG.md` for what changed when.

## Scripts

All scripts live in `bin/`. Every script supports `--help` (or `-h`) and exits 2
on a usage error. Shared helpers are in `lib/common.sh`.

| script | what it does |
| --- | --- |
| `backup.sh [-n] [-k N] [-x PAT] SRC DEST` | tar+gzip `SRC` into `DEST/NAME-DATE.tar.gz` with a `.sha256`, atomically; optionally keep only the newest N |
| `restore-backup.sh [-f] [-l] ARCHIVE DEST` | verify the checksum, refuse absolute or `..` paths, extract into an empty directory |
| `rotate-backups.sh [-n] [-p GLOB] DIR DAYS` | delete matching files (default `*.tar.gz`) older than `DAYS` days, always keeping the last one; `-g D,W,M` thins by day/week/month instead |
| `rotate-logs.sh [-k N] [-s SIZE] [-a DAYS] [-z gzip\|xz] FILE...` | numbered copy-and-truncate rotation with size/age triggers and compression |
| `disk-alert.sh [-i PCT] [-c FILE] [-w URL] [PCT]` | filesystems at or over `PCT` percent (default 90), optionally inode usage and per-mount overrides; exit 1 if any |
| `saferm.sh [-n] [-v] FILE...` / `-P DAYS` | move files to `~/.saferm-trash` (or `$SAFERM_TRASH`) as `NAME.EPOCH`; `-P` purges old entries |
| `tail-logs.sh [-n N] [-g RE] [-c] [-F] FILE...` | follow several logs, each line prefixed with the file name |
| `healthcheck.sh HOST PORT` / `-u URL` / `-f FILE` | TCP or HTTP checks, optional JSON output; exit 0 healthy, 1 unhealthy |
| `retry.sh [-t N] [-d S] [-j] [-r CODES] CMD...` | run a command again with exponential backoff, optional jitter and exit-code filter |
| `json-get.sh [-r] KEY [FILE]` | read a value from JSON; uses jq, with a limited pure-bash fallback |
| `gen-systemd.sh -n NAME -c CMD [-t CALENDAR] [-H] [-i] [-V]` | print a systemd service unit, and a timer with `-t`; sandboxing, user install and verification |
| `db-backup-postgres.sh [-F FMT] [-j N] [-V] [-k N] DEST DB...` | `pg_dump` dumps (custom, plain or directory) with retention and optional verify |
| `db-backup-mysql.sh [-A] [-k N] DEST DB...` | `mysqldump` + gzip with retention, `-A` for all user databases; password via option file, never argv |
| `git-maint.sh [-n] [-a] [REPO]` / `-r DIR` | prune, reflog expire and gc |
| `git-stale-branches.sh [-d DAYS] [-m BASE] [-s] [REPO]` | stale local branches, oldest first; optionally only merged ones, with a per-author count |
| `ssh-audit.sh [-d DIR] [-H HOSTS] [-s] [-v]` | key permissions, missing passphrases, weak keys, duplicate authorized_keys, unhashed known_hosts |
| `bootstrap-dotfiles.sh [-n] [-t DIR] [-m MANIFEST] DIR` | link entries of `DIR` as `~/.name`, idempotent, keeping `.bak` copies |
| `db-backup-sqlserver.sh [-S SRV] [-V] [-C] DEST DB...` | `BACKUP DATABASE` through `sqlcmd` |

## Exit codes

All scripts use the same convention: 0 success, 1 the thing being checked or
done failed (or a check found problems), 2 bad command line.

## Tests

```
make test        # or: bash tests/run.sh
```

`tests/harness.sh` is a small assert-style harness; each `tests/test_*.sh`
sources it. Output is TAP-like (`ok - name` / `not ok - name`, with `# FAIL`
detail lines and `# SKIP` for skipped tests). Tests use temporary directories
and do not touch your home. External programs (`pg_dump`, `mysqldump`,
`sqlcmd`, `curl`, `nc`) are replaced by small stubs placed first on `PATH`, so
no database or network is needed.

## Examples

```
# nightly backup as a systemd timer
bin/gen-systemd.sh -n nightly-backup -c '/opt/bash-toolbox/bin/backup.sh -k 14 /srv/data /backup' \
    -t '*-*-* 02:30:00' -o ~/.config/systemd/user

# retry a flaky download up to 6 times, waiting 2, 4, 8... seconds
bin/retry.sh -t 6 -d 2 curl -fsSLO https://example.com/file.tgz

# who has stale merged branches?
bin/git-stale-branches.sh -d 60 -m main -s ~/src/project
```

## Continuous integration

`.github/workflows/test.yml` runs the tests on Ubuntu and macOS and runs
shellcheck.

## Portability

Developed on macOS, where `/bin/bash` is 3.2, and meant to also run on Linux.
The scripts therefore avoid bash 4+ features unless they are guarded by a
version check with a fallback, and avoid GNU-only tools (`readlink -f`,
`date -d`, `stat -c`, `find -printf`, `timeout`, `sed -i` without a suffix).

| feature | needs | how it is handled |
| --- | --- | --- |
| `mapfile` | bash 4.0 | `tb_readlines` falls back to a `read` loop |
| associative arrays | bash 4.0 | `disk-alert.sh -c` falls back to scanning the file |
| `${var@Q}` | bash 4.4 | `tb_quote` falls back to `printf %q` |
| `EPOCHSECONDS` | bash 5.0 | `tb_now` falls back to `date +%s` |
| `EPOCHREALTIME` | bash 5.0 | `tb_now_ms` falls back to whole seconds |
| empty array under `set -u` | bash 4.4 | expanded as `${arr[@]+"${arr[@]}"}` |
| sha256 | `sha256sum` or `shasum` | `tb_sha256` picks whichever exists |
| `timeout` | GNU coreutils | `tb_run_timeout` is a small bash watchdog |
| date arithmetic | GNU `date -d` / BSD `date -j` | `tb_days_from_civil` is plain integer maths |

Other differences that the scripts deal with: `healthcheck.sh` needs an `nc`
with `-z` and `-w`; `ssh-audit.sh` reads permissions from `ls -l` because `stat`
flags differ; `df -i` output has a different layout on macOS and Linux and both
are parsed.
