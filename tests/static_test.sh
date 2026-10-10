#!/bin/sh
. "$(dirname "$0")/lib/env.sh"

test_api_sends_csrf_header() {
	assert_contains "$(cat "$GRKA_SRC/www/app.js")" "'X-GrKa-Request': '1'"
}

test_no_references_to_removed_files() {
	_r="$(grep -rlE 'S97mihomo|policy-route\.sh|/tmp/grka-task\.lock' "$GRKA_SRC" "$REPO_DIR/rootfs/opt/etc" 2>/dev/null | grep -v 'lib/migrate.sh')"
	assert_eq "" "$_r"
}

test_scripts_use_new_library() {
	for _s in core-update.sh compact-toggle.sh self-update.sh dashboard-install.sh; do
		assert_contains "$(cat "$GRKA_SRC/scripts/$_s")" 'lib/common.sh' "$_s"
	done
}

run_tests "$0"
