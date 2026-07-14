#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $CURRENT_DIR/helpers/helpers.sh
source $CURRENT_DIR/helpers/resurrect_helpers.sh

create_tmux_test_environment_and_save() {
	set_screen_dimensions_helper
	$CURRENT_DIR/helpers/create_and_save_tmux_test_environment.exp
}

main() {
	install_tmux_plugin_under_test_helper
	mkdir -p /tmp/bar # setup required dirs
	mkdir -p "${HOME}/.tmux/resurrect" # so saving uses the default dir and not the XDG fallback
	create_tmux_test_environment_and_save

	if last_save_file_differs_helper "tests/fixtures/save_file.txt"; then
		fail_helper "Saved file not correct (initial save)"
		# aid debugging (e.g. in CI): show where a save might have landed
		ls -la "${HOME}/.tmux/resurrect/" \
			"${XDG_DATA_HOME:-${HOME}/.local/share}/tmux/resurrect/" >&2 || true
	fi
	exit_helper
}
main
