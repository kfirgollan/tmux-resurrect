#!/usr/bin/env bash

# "claude session strategy"
#
# Restores a Claude Code session saved as `claude ... --resume <session-id>`
# (see `save_strategies/claude_session.sh`).
# If the session transcript no longer exists (e.g. it was cleaned up by
# Claude Code), the `--resume` flag is dropped so the pane still comes back
# with a fresh claude instead of an error.

ORIGINAL_COMMAND="$1"
DIRECTORY="$2"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

saved_session_id() {
	local previous_word=""
	local word
	for word in $ORIGINAL_COMMAND; do
		if [ "$previous_word" == "--resume" ] || [ "$previous_word" == "-r" ]; then
			echo "$word"
			return
		fi
		previous_word="$word"
	done
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

# removes the resume flags (and their argument) from the original command
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
	local session_id="$(saved_session_id)"
	if [ -z "$session_id" ]; then
		echo "$ORIGINAL_COMMAND"
	elif session_transcript_exists "$session_id"; then
		echo "$ORIGINAL_COMMAND"
	else
		strip_resume_flags "$ORIGINAL_COMMAND"
	fi
}
main
