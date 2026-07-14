# we want "fixed" dimensions no matter the size of real display
set_screen_dimensions_helper() {
	stty cols 200
	stty rows 50
}

# pane titles default to the machine's hostname, so they can't be part of
# fixture files - blank out the pane title field (7th) before comparing
_normalize_save_file_helper() {
	local file="$1"
	sed "s/^\(pane	[^	]*	[^	]*	[^	]*	[^	]*	[^	]*	\):[^	]*/\1:/" "$file"
}

last_save_file_differs_helper() {
	local original_file="$1"
	diff <(_normalize_save_file_helper "$original_file") \
		<(_normalize_save_file_helper "${HOME}/.tmux/resurrect/last")
	[ $? -ne 0 ]
}
