#!/usr/bin/env bash

# "claude session save strategy"
#
# Detects which Claude Code session is running in a pane and saves the pane
# command as `claude <original flags> --resume <session-id>`, so that
# restoring the pane resumes the exact same conversation.
#
# Claude Code maintains a state file for every running process in
# `~/.claude/sessions/<pid>.json` which contains the session id. This is an
# internal (undocumented) file, so all steps below are careful: if anything
# is off, the original command is saved unchanged.

PANE_PID="$1"
PANE_FULL_COMMAND="$2"
PANE_DIR="$3"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

save_original_command_and_exit() {
	echo "$PANE_FULL_COMMAND"
	exit 0
}

# pid of the claude process, i.e. the direct child of the pane's shell whose
# command matches the pane full command (same `ps` approach as the default
# `save_command_strategies/ps.sh`, with `-A` so it also works without a tty)
claude_pid() {
	ps -Ao "ppid,pid,args" |
		sed "s/^ *//" |
		grep "^${PANE_PID} " |
		while read -r ppid pid args; do
			if [ "$args" == "$PANE_FULL_COMMAND" ]; then
				echo "$pid"
				break
			fi
		done
}

# extracts a top-level string value from the session state file, without
# depending on `jq`
session_file_value() {
	local session_file="$1"
	local key="$2"
	sed -n "s/.*\"${key}\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$session_file" | head -1
}

session_transcript_exists() {
	local session_id="$1"
	local transcript
	for transcript in "$CLAUDE_DIR/projects/"*"/${session_id}.jsonl"; do
		if [ -e "$transcript" ]; then
			return 0
		fi
	done
	return 1
}

# removes any resume/continue flags from the original command so a fresh
# `--resume <session-id>` can be appended
strip_resume_flags() {
	local result=""
	local skip_next="false"
	local word
	for word in $1; do
		if [ "$skip_next" == "true" ]; then
			skip_next="false"
			if [[ "$word" != -* ]]; then
				continue # the flag's argument, e.g. a session id
			fi
		fi
		case "$word" in
			--resume|-r)
				skip_next="true"
				;;
			--continue|-c)
				;;
			*)
				result="$result $word"
				;;
		esac
	done
	echo "${result# }"
}

main() {
	local pid="$(claude_pid)"
	if [ -z "$pid" ]; then
		save_original_command_and_exit
	fi

	local session_file="$CLAUDE_DIR/sessions/${pid}.json"
	if [ ! -f "$session_file" ]; then
		save_original_command_and_exit
	fi

	local session_id="$(session_file_value "$session_file" "sessionId")"
	if [ -z "$session_id" ]; then
		save_original_command_and_exit
	fi

	# guards against a stale state file from a recycled pid
	if [ "$(session_file_value "$session_file" "cwd")" != "$PANE_DIR" ]; then
		save_original_command_and_exit
	fi
	if ! session_transcript_exists "$session_id"; then
		save_original_command_and_exit
	fi

	echo "$(strip_resume_flags "$PANE_FULL_COMMAND") --resume $session_id"
}
main
