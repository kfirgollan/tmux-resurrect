# Restoring Claude Code sessions

[Claude Code](https://claude.com/claude-code) conversations survive restarts:
`claude --resume <session-id>` reopens the exact conversation. tmux-resurrect
can detect which session is running in each pane at save time, and restore
every pane to its own conversation.

### Setup

Add `claude` to the list of restored programs in `.tmux.conf`:

    set -g @resurrect-processes 'claude'

That's it. On save, a pane running `claude` is recorded as
`claude <your flags> --resume <session-id>`; on restore, each pane reopens
its own conversation, in its original working directory, with flags such as
`--model` preserved.

### How it works

- On save, the pane's claude process id is looked up in Claude Code's
  session state files (`~/.claude/sessions/<pid>.json`, or under
  `$CLAUDE_CONFIG_DIR` if set) to find its session id
  (`save_strategies/claude_session.sh`). If the session can't be determined,
  the command is saved unchanged.
- On restore, if the session transcript no longer exists (e.g. cleaned up by
  Claude Code after `cleanupPeriodDays`), the `--resume` flag is dropped and
  a fresh `claude` is started instead of failing
  (`strategies/claude_session.sh`).

Both strategies are enabled by default. To opt out, set either option to a
non-existent strategy name in `.tmux.conf`, e.g.:

    set -g @resurrect-save-strategy-claude 'off'
    set -g @resurrect-strategy-claude 'off'

### Limitations

- The pid → session lookup relies on Claude Code's internal
  `~/.claude/sessions/` state files (verified with Claude Code 2.x). If the
  lookup fails, tmux-resurrect degrades gracefully: the pane is restored
  with the claude command that was originally typed.
- `claude --resume <session-id>` only finds sessions from the same working
  directory and machine. Panes are restored to their saved directory, so
  this only matters if you move or rename project directories between save
  and restore.
- A brand-new claude that never sent a prompt has no transcript yet and is
  restored as a fresh `claude`.
- If claude runs under a wrapper (so the saved process line doesn't start
  with `claude`), the strategy won't match. Check how the command is saved
  in your resurrect file and see [restoring programs](restoring_programs.md)
  for `~` matching.
