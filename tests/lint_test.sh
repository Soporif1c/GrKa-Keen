#!/bin/sh
. "$(dirname "$0")/lib/env.sh"

test_shellcheck_clean() {
	_files="$(ls "$GRKA_SRC"/bin/* "$GRKA_SRC"/lib/*.sh "$GRKA_SRC"/scripts/*.sh "$GRKA_SRC/www/cgi-bin/api" \
		"$REPO_DIR"/rootfs/opt/etc/init.d/* "$REPO_DIR"/rootfs/opt/etc/ndm/*/*.sh \
		"$REPO_DIR/install.sh" "$REPO_DIR/build.sh" "$REPO_DIR/build-ipk.sh")"
	# shellcheck disable=SC2086
	_out="$(shellcheck -s sh -S warning -e SC1090,SC1091 $_files 2>&1)"
	assert_eq "" "$_out"
}

test_no_crlf_in_rootfs() {
	assert_eq "" "$(grep -rl "$(printf '\r')" "$REPO_DIR/rootfs" 2>/dev/null)"
}

test_version_is_alpha() {
	assert_eq "1.0.0-alpha.1" "$(tr -d ' \r\n' < "$GRKA_SRC/version")"
}

run_tests "$0"
