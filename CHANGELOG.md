# Changelog

## 2026

- `VERSION` file and `--version` on every script (1.0.0).
- `backup.sh -z zstd`; `restore-backup.sh` reads `.tar.zst`.
- `db-backup-mysql.sh -F` (option file, must be private).
- `ssh-audit.sh -F [-y]` proposes or applies chmod fixes.
- `tests/run.sh`: `-v`, `-f TEXT`, file patterns, quiet by default.
- Fixed: `disk-alert.sh` reported macOS `devfs` and the automounter `map` as
  100% full; pseudo filesystems are skipped by default (`-a`, `-x`).
- Fixed: `retry.sh` restarted commands killed by SIGINT/SIGTERM.
- Fixed: `json-get.sh` fallback mishandled escaped quotes and backslashes.

## 2025

- `healthcheck.sh -N` monitoring-plugin mode; `disk-alert.sh -j`.
- `bootstrap-dotfiles.sh -u`; `saferm.sh -l` and `-R`; `rotate-logs.sh -P`.
- `git-maint.sh -g` (commit-graph); `gen-systemd.sh -R`.
- `backup.sh` reads the archive back before keeping it;
  `db-backup-postgres.sh` runs `pg_isready` first.
- `ssh-audit.sh` flags group/world-writable `authorized_keys` and `config`.
- `tb_now_ms`, harness `assert_contains` family.
- Fixed: files with CR LF line endings (targets, manifests, overrides, host
  lists) left a trailing CR in the last field.

## 2024

- `healthcheck.sh -s/-x` TLS expiry; `tb_run_timeout`; `retry.sh -T`.
- `ssh-audit.sh -j`; `git-stale-branches.sh -i`, `-C`; `json-get.sh -d`.
- `tail-logs.sh` accepts directories; `bootstrap-dotfiles.sh` host overlays.
- `backup.sh -X`; `db-backup-sqlserver.sh -s`, `-o`.
- `docs/usage.md` generated from `--help` and tested.
- Fixed: `backup.sh .` named the archive after the dot.

## 2023

- `backup.sh` writes a SHA-256 file next to each archive; new `restore-backup.sh`
  verifies it and refuses absolute or `..` entries.
- `rotate-backups.sh -g D,W,M` keeps the newest backup per day/week/month.
- `rotate-logs.sh` gained `-s`, `-a` and `-z gzip|xz`.
- `gen-systemd.sh` gained `-H`/`-W` (sandboxing), `-i` (install as user units) and
  `-V` (verify with `systemd-analyze`).
- `disk-alert.sh -w URL` posts findings as JSON.
- `db-backup-mysql.sh -A`, `db-backup-postgres.sh -F plain|directory -j N`.
- `saferm.sh` refuses `/`, `$HOME` and the trash directory.
- `git-maint.sh -r DIR` maintains many repositories.
- `tests/run.sh` isolates `TMPDIR` per test file.
- Fixed: `tb_prune_newest` listed matching directories by their contents.

## 2022

- New `db-backup-sqlserver.sh` (sqlcmd): `-V` verify, `-C` trust certificate for
  sqlcmd 18.
- `healthcheck.sh -f FILE` and `-j` JSON output.
- `retry.sh -j` jitter, `-r` retry only on listed exit codes.
- `json-get.sh` fallback learned array indexes.
- `ssh-audit.sh -H`, `-s`, `-v`.
- `bootstrap-dotfiles.sh`: manifest, `-n`, `-t`; repeat runs are idempotent.
- `tb_quote` (`${var@Q}` on bash 4.4+). Test harness output became TAP-like.
- Fixed: `rotate-backups.sh` split file names containing spaces (rewritten).

## 2021

- New: `gen-systemd.sh`, `db-backup-postgres.sh`, `db-backup-mysql.sh`.
- `disk-alert.sh`: inode checks and per-mount overrides.
- `saferm.sh` rewritten; `tail-logs.sh` rewritten; `git-stale-branches.sh` rewritten.
- Fixed: MySQL password no longer passed on the command line.
- Fixed: `saferm.sh` overwrote earlier trash entries with the same name.
- GitHub Actions workflow added.

## 2020

- `lib/common.sh`; `backup.sh` rewritten with getopts and atomic output.
- New: `retry.sh`, `rotate-logs.sh`, `ssh-audit.sh`, `git-maint.sh`, `json-get.sh`.
- `healthcheck.sh` learned HTTP checks.
- Fixed: `rotate-logs.sh` shifted copies in the wrong order.

## 2019

- First scripts: `backup.sh`, `rotate-backups.sh`, `disk-alert.sh`, `saferm.sh`,
  `tail-logs.sh`, `healthcheck.sh`, `git-stale-branches.sh`, `bootstrap-dotfiles.sh`.
- Test harness and runner.
- Fixed: `disk-alert.sh` never exited 1 (pipe into `while` ran in a subshell).
