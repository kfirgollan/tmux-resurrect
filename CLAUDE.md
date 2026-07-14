# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Public repository — privacy

This is a public fork of tmux-plugins/tmux-resurrect. Before committing, double-check nothing personal or machine-specific leaks in:

- Resurrect save files (`~/.tmux/resurrect/*`) contain working directory paths, running commands, and (with pane-contents capture) full terminal output. Never commit real save files — test fixtures in `tests/fixtures/` are hand-crafted with `/tmp` paths.
- Anything generated while testing locally (pane content archives, hostnames, home directory paths).

## Stack

Pure Bash — no other languages, no external dependencies beyond standard Unix tools (`awk`, `sed`, `ps`, `tar`, `gzip`) and tmux itself. Tests additionally use `expect`. Keep it that way; contributions must not add runtime dependencies.

Portability constraints:
- Must run on macOS's bash 3.2 as well as Linux — avoid bash 4+ features (associative arrays, `${var,,}`, etc.).
- Must cope with BSD *and* GNU userland (`sed`, `ps` flags differ). `save_command_strategies/ps.sh` is the portable default; `linux_procfs.sh`/`pgrep.sh` are opt-in alternatives.
- Supports tmux >= 1.9 (`SUPPORTED_VERSION` in `scripts/variables.sh`, enforced by `scripts/check_tmux_version.sh`).

Code style (match the existing files):
- Tabs for indentation.
- Small snake_case functions; "private" helpers prefixed with `_`; each script defines `main()` and calls it as the last line.
- `local` for all function variables.

## Running tests

Tests live in `tests/` and depend on the `lib/tmux-test` git submodule (several files, including `run_tests` and `tests/run_tests_in_isolation`, are symlinks into it):

```sh
git submodule update --init    # required once, or symlinks are broken
./run_tests                    # runs the suite in a Vagrant VM
./tests/run_tests_in_isolation # runs directly on the current machine (used by CI)
```

Warning: `run_tests_in_isolation` installs the plugin and manipulates the *local* tmux server and `~/.tmux/resurrect` — only run it in a throwaway environment, never casually on a dev machine. The safe local way is an ubuntu container with the same deps CI installs (`.github/workflows/ci.yml`), running the suite under `script -qec ... /dev/null` for a pty; note the harness clones the plugin from the repo's *committed* state, so commit (or commit inside a container copy) before running.

Most tests are end-to-end: `expect` scripts (`tests/helpers/*.exp`) drive a real tmux session, save/restore it, and diff the resulting save file against `tests/fixtures/*.txt` (pane titles are host-specific and get normalized by `tests/helpers/resurrect_helpers.sh` before diffing). If you change the save-file format, the fixtures must be regenerated in lockstep. `tests/test_claude_strategies.sh` is standalone (no tmux needed). Fixtures assume the CI environment: tmux from ubuntu's apt, 200x50 pty, `vim`/`man`/`less` installed.

CI (GitHub Actions) also gates on `shellcheck -s bash -S error` over all shell files and a gitleaks secret scan; `lefthook.yml` mirrors these as local pre-commit/pre-push hooks.

## Architecture

### Entry point

`resurrect.tmux` is the TPM plugin entry point: it binds `prefix + C-s` → `scripts/save.sh` and `prefix + C-r` → `scripts/restore.sh` (keys configurable via tmux options).

### The save file is the central contract

Save and restore communicate only through a TSV text file (`~/.tmux/resurrect/tmux_resurrect_<timestamp>.txt`, with `last` symlinked to the newest one; falls back to `$XDG_DATA_HOME/tmux/resurrect` when `~/.tmux/resurrect` doesn't exist). Each line starts with a type token:

- `pane` — session, window index/flags, pane index/title, cwd, active flags, current command, full command
- `window` — name, layout string, automatic-rename setting
- `state` — active and alternate session (client)
- `grouped_session` — grouped-session relationships

Fields that may be empty are stored with a `:` prefix and stripped on read via `remove_first_char` — this keeps `IFS=$'\t' read` field counts stable. Any format change touches `scripts/save.sh` (writers), `scripts/restore.sh` (readers, including the `awk` field-position extractors like `$11`), and `tests/fixtures/`.

### Save path (`scripts/save.sh`)

Dumps state using `tmux list-panes/list-windows -a -F <format>` with tab-delimited format strings. The pane's full command is resolved from its PID by a pluggable script in `save_command_strategies/` (default `ps.sh`; selected via `@resurrect-save-command-strategy`). Optional pane-contents capture tars up per-pane `capture-pane` output. Keeps timestamped backups, pruning ones older than `@resurrect-delete-backup-after` days (keeping at least 5).

### Restore path (`scripts/restore.sh`)

Order matters in `main()`: recreate panes/windows/sessions → apply window layouts and properties → restart processes → restore active/alternate panes, windows, sessions. Restoration is idempotent: panes that already exist are registered in `EXISTING_PANES_VAR` and skipped, including their processes. "Restoring from scratch" (exactly one pane on the server) enables overwriting that pane and killing session 0.

### Process restore strategies

`scripts/process_restore_helpers.sh` decides whether/how to restart each pane's command:

- Default whitelist of programs is in `scripts/variables.sh` (`default_proc_list`); users extend via `@resurrect-processes`.
- Inline strategies in the option value: `~program -> replacement command` (`->` token) and `*` for "restore with original arguments".
- Script strategies in `strategies/`, named `<program>_<strategy>.sh`, selected via `@resurrect-strategy-<program>` tmux option. They receive the original command and directory as `$1`/`$2` and echo the command to run (e.g. `vim_session.sh` echoes `vim -S` when a `Session.vim` exists).

### Per-program save strategies

The save-side mirror of restore strategies: `save_strategies/<program>_<strategy>.sh`, selected via `@resurrect-save-strategy-<program>`, invoked from `dump_panes` with `(pane_pid, full_command, dir)`; stdout replaces the saved full command. Used by `save_strategies/claude_session.sh` to save Claude Code panes as `claude ... --resume <session-id>` (paired with restore-side `strategies/claude_session.sh`). These scripts must stay tmux-free (args + filesystem only) so they can be tested standalone — see `tests/test_claude_strategies.sh`, which runs directly without the tmux-test harness.

### Configuration and hooks

All user-facing tmux option names (`@resurrect-*`) are declared in `scripts/variables.sh` — treat it as the option registry. Hooks (`@resurrect-hook-<name>`, e.g. `post-save-all`, `pre-restore-all`) are `eval`ed via `execute_hook` in `scripts/helpers.sh`. User-facing behavior is documented in `docs/` — update the relevant doc when changing options or behavior.
