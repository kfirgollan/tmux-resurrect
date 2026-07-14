#!/usr/bin/env bash

# Standalone tests for the claude session save/restore strategies.
#
# Unlike the other tests, this does not require the tmux-test harness, tmux
# or claude - it fakes the Claude Code state directory via CLAUDE_CONFIG_DIR
# and uses a `sleep` child process as a stand-in for a running claude.
# Run directly: ./tests/test_claude_strategies.sh

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SAVE_STRATEGY="$CURRENT_DIR/../save_strategies/claude_session.sh"
RESTORE_STRATEGY="$CURRENT_DIR/../strategies/claude_session.sh"

SESSION_ID="11111111-2222-3333-4444-555555555555"
FAILED=0

setup() {
	export CLAUDE_CONFIG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/resurrect_claude_test.XXXXXX")"
	mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
	mkdir -p "$CLAUDE_CONFIG_DIR/projects/-tmp-fake-project"

	# stand-in for a running claude process: a child of this script ($$),
	# just like claude is a child of the pane's shell
	sleep 60 &
	FAKE_CLAUDE_PID=$!
	disown
	FAKE_CLAUDE_COMMAND="sleep 60"
	FAKE_CLAUDE_CWD="/tmp/fake-project"

	write_session_file "$FAKE_CLAUDE_PID" "$SESSION_ID" "$FAKE_CLAUDE_CWD"
	touch "$CLAUDE_CONFIG_DIR/projects/-tmp-fake-project/${SESSION_ID}.jsonl"
}

teardown() {
	kill "$FAKE_CLAUDE_PID" 2>/dev/null
	rm -rf "$CLAUDE_CONFIG_DIR"
}

write_session_file() {
	local pid="$1"
	local session_id="$2"
	local cwd="$3"
	cat > "$CLAUDE_CONFIG_DIR/sessions/${pid}.json" <<-EOF
	{"pid":${pid},"sessionId":"${session_id}","cwd":"${cwd}","kind":"interactive"}
	EOF
}

assert_equals() {
	local test_name="$1"
	local expected="$2"
	local actual="$3"
	if [ "$expected" == "$actual" ]; then
		echo "ok: $test_name"
	else
		echo "FAIL: $test_name"
		echo "  expected: $expected"
		echo "  actual:   $actual"
		FAILED=1
	fi
}

test_save_happy_path() {
	assert_equals "save: rewrites command to --resume <session-id>" \
		"$FAKE_CLAUDE_COMMAND --resume $SESSION_ID" \
		"$($SAVE_STRATEGY $$ "$FAKE_CLAUDE_COMMAND" "$FAKE_CLAUDE_CWD")"
}

test_save_preserves_flags() {
	# a stand-in process that carries claude-like flags in its args
	perl -e 'sleep 60' -- --resume old-name --model opus &
	local pid=$!
	disown
	local full_command="perl -e sleep 60 -- --resume old-name --model opus"
	write_session_file "$pid" "$SESSION_ID" "$FAKE_CLAUDE_CWD"
	assert_equals "save: strips old resume flags, keeps other flags" \
		"perl -e sleep 60 -- --model opus --resume $SESSION_ID" \
		"$($SAVE_STRATEGY $$ "$full_command" "$FAKE_CLAUDE_CWD")"
	kill "$pid" 2>/dev/null
}

test_save_falls_back_without_session_file() {
	rm "$CLAUDE_CONFIG_DIR/sessions/${FAKE_CLAUDE_PID}.json"
	assert_equals "save: original command when session file is missing" \
		"$FAKE_CLAUDE_COMMAND" \
		"$($SAVE_STRATEGY $$ "$FAKE_CLAUDE_COMMAND" "$FAKE_CLAUDE_CWD")"
	write_session_file "$FAKE_CLAUDE_PID" "$SESSION_ID" "$FAKE_CLAUDE_CWD"
}

test_save_falls_back_on_cwd_mismatch() {
	assert_equals "save: original command when cwd does not match (stale pid)" \
		"$FAKE_CLAUDE_COMMAND" \
		"$($SAVE_STRATEGY $$ "$FAKE_CLAUDE_COMMAND" "/somewhere/else")"
}

test_save_falls_back_without_transcript() {
	write_session_file "$FAKE_CLAUDE_PID" "99999999-aaaa-bbbb-cccc-dddddddddddd" "$FAKE_CLAUDE_CWD"
	assert_equals "save: original command when transcript is missing" \
		"$FAKE_CLAUDE_COMMAND" \
		"$($SAVE_STRATEGY $$ "$FAKE_CLAUDE_COMMAND" "$FAKE_CLAUDE_CWD")"
	write_session_file "$FAKE_CLAUDE_PID" "$SESSION_ID" "$FAKE_CLAUDE_CWD"
}

test_save_falls_back_without_child_process() {
	assert_equals "save: original command when process is not found" \
		"claude --nonexistent" \
		"$($SAVE_STRATEGY $$ "claude --nonexistent" "$FAKE_CLAUDE_CWD")"
}

test_restore_passes_through_when_transcript_exists() {
	assert_equals "restore: command unchanged when transcript exists" \
		"claude --model opus --resume $SESSION_ID" \
		"$($RESTORE_STRATEGY "claude --model opus --resume $SESSION_ID" "$FAKE_CLAUDE_CWD")"
}

test_restore_drops_resume_when_transcript_missing() {
	assert_equals "restore: --resume dropped when transcript is missing" \
		"claude --model opus" \
		"$($RESTORE_STRATEGY "claude --model opus --resume 99999999-aaaa-bbbb-cccc-dddddddddddd" "$FAKE_CLAUDE_CWD")"
}

test_restore_passes_through_without_resume() {
	assert_equals "restore: command without --resume unchanged" \
		"claude --model opus" \
		"$($RESTORE_STRATEGY "claude --model opus" "$FAKE_CLAUDE_CWD")"
}

main() {
	setup
	trap teardown EXIT

	test_save_happy_path
	test_save_preserves_flags
	test_save_falls_back_without_session_file
	test_save_falls_back_on_cwd_mismatch
	test_save_falls_back_without_transcript
	test_save_falls_back_without_child_process
	test_restore_passes_through_when_transcript_exists
	test_restore_drops_resume_when_transcript_missing
	test_restore_passes_through_without_resume

	exit "$FAILED"
}
main
