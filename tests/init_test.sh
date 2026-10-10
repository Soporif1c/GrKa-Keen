#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
export GRKA_LPID="$T/lighttpd.pid"
GRKA_INIT_NO_MAIN=1
. "$REPO_DIR/rootfs/opt/etc/init.d/S99grka-keen"

HOOK_NF="$REPO_DIR/rootfs/opt/etc/ndm/netfilter.d/50-grka.sh"
HOOK_IF="$REPO_DIR/rootfs/opt/etc/ndm/ifstatechanged.d/50-grka.sh"

test_lighttpd_conf_uses_port_from_settings() {
	settings_init
	settings_set panel_port 1234
	gen_lighttpd_conf
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.port          = 1234"
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.document-root = \"$GRKA_SHARE/www\""
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.pid-file      = \"$T/lighttpd.pid\""
}

test_lighttpd_conf_bad_port_falls_back() {
	settings_init
	settings_set panel_port '"80; rm -rf /"'
	gen_lighttpd_conf
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.port          = 1100"
}

test_netfilter_hook_ipv4_tables_set_flag() {
	type=iptables table=mangle sh "$HOOK_NF"
	assert_file_exists "$GRKA_RUN/dirty"
	rm -f "$GRKA_RUN/dirty"
	type=iptables table=nat sh "$HOOK_NF"
	assert_file_exists "$GRKA_RUN/dirty"
}

test_netfilter_hook_ignores_ipv6_and_raw() {
	type=ip6tables table=mangle sh "$HOOK_NF"
	assert_file_missing "$GRKA_RUN/dirty"
	type=iptables table=raw sh "$HOOK_NF"
	assert_file_missing "$GRKA_RUN/dirty"
}

test_netfilter_hook_burst_only_sets_flag() {
	_i=0
	while [ $_i -lt 20 ]; do
		type=iptables table=nat sh "$HOOK_NF"
		_i=$((_i + 1))
	done
	assert_eq "dirty" "$(ls "$GRKA_RUN")"
	assert_eq "" "$(cat "$STUB/calls")"
}

test_ifstate_hook_sets_flag() {
	sh "$HOOK_IF"
	assert_file_exists "$GRKA_RUN/dirty"
}

run_tests "$0"
