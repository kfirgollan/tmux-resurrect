---
name: verify
description: Verify tmux-resurrect changes end-to-end on an isolated tmux server, without touching the user's real tmux server or resurrect files.
---

# Verifying tmux-resurrect changes

The surface is a tmux server running this plugin. Never test against the
default server — always use a separate socket (`tmux -L rtest ...`).

## Recipe

1. Write a minimal test conf (in a scratch dir):

   ```
   set -g @resurrect-dir '<scratch>/resurrect'
   set -g @resurrect-processes '<programs under test>'
   run-shell '<repo>/resurrect.tmux'
   ```

2. Start the server and arrange panes:

   ```sh
   tmux -L rtest -f <conf> new-session -d -s test -c <dir>
   tmux -L rtest split-window -t test:0 -c /tmp    # control pane
   tmux -L rtest send-keys -t test:0.0 "<program>" Enter
   ```

3. Save via the plugin path (run-shell sets $TMUX so the scripts target the
   test server): `tmux -L rtest run-shell "<repo>/scripts/save.sh quiet"`,
   then inspect `<scratch>/resurrect/last`. View tabs with
   `sed 's/\t/<TAB>/g'` — field shifts indicate the empty-field/IFS-collapse
   class of bug (possibly-empty fields must be `:`-prefixed in the format).

4. Simulate reboot: `tmux -L rtest kill-server`, start a fresh server with
   the same conf, `run-shell "<repo>/scripts/restore.sh"`, then check
   `list-panes -a -F ...`, `capture-pane -p`, and `ps -Ao ppid,pid,args`
   filtered by the restored `#{pane_pid}`.

5. Cleanup: `tmux -L rtest kill-server`.

## Gotchas

- The tmux-test harness (`./run_tests`, Vagrant) is CI's job and its
  fixtures are stale relative to the current save format — don't use it as
  verification.
- Strategy scripts (`strategies/`, `save_strategies/`) are tmux-free by
  design; `./tests/test_claude_strategies.sh` runs them standalone.
- For Claude Code panes: a first-run dir shows a trust dialog that blocks
  startup (send Enter); `~/.claude/sessions/<pid>.json` appears only after
  full boot. Create a throwaway session with
  `claude -p "..." --output-format json` (gives `session_id`) instead of
  resuming real user sessions, and delete its
  `~/.claude/projects/<munged-dir>/` afterwards.
- `ps -a` only shows tty-attached processes; use `ps -A` when probing from
  a non-tty context.
