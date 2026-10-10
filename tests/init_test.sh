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

test_lighttpd_conf_upload_dir_is_tmpdir() {
	settings_init
	gen_lighttpd_conf
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.upload-dirs   = ( \"$GRKA_TMPDIR\" )"
}

test_lighttpd_conf_bad_port_falls_back() {
	settings_init
	settings_set panel_port '"80; rm -rf /"'
	gen_lighttpd_conf
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.port          = 1100"
}

fake_spawn() {
	spawn_bg() { echo "$*" >> "$T/spawned"; SPAWN_PID=4321; }
}

test_start_runs_watchdog_without_lighttpd() {
	settings_init
	fake_spawn
	LIGHTTPD="$T/no-such-lighttpd"
	_out="$(do_start)"
	assert_eq 1 "$?" "без lighttpd старт сообщает об ошибке"
	assert_contains "$_out" "lighttpd не найден"
	assert_contains "$(cat "$T/spawned" 2>/dev/null)" "grka-watchdog" "сторож запускается и без панели"
}

test_start_runs_watchdog_when_lighttpd_fails() {
	settings_init
	fake_spawn
	fake_lighttpd() { return 1; }
	LIGHTTPD=fake_lighttpd
	_out="$(do_start)"
	assert_eq 1 "$?"
	assert_contains "$_out" "панель не запустилась"
	assert_contains "$(cat "$T/spawned" 2>/dev/null)" "grka-watchdog" "сторож запускается, даже если панель не поднялась"
}

test_start_launches_watchdog_and_panel() {
	settings_init
	fake_spawn
	fake_lighttpd() { echo "$*" > "$T/lighttpd.args"; }
	LIGHTTPD=fake_lighttpd
	_out="$(do_start)"
	assert_eq 0 "$?"
	assert_contains "$_out" "панель на порту 1100"
	assert_eq "-f $GRKA_ETC/lighttpd.conf" "$(cat "$T/lighttpd.args" 2>/dev/null)"
	assert_contains "$(cat "$T/spawned" 2>/dev/null)" "grka-watchdog"
	assert_file_exists "$GRKA_TMPDIR"
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
