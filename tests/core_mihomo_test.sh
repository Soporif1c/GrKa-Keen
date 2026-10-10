#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"
. "$GRKA_SRC/lib/core.sh"

test_core_config_default_and_expert() {
	settings_init
	assert_eq "$MIHOMO_DIR/config.yaml" "$(core_config)"
	settings_set expert.mihomo '"/x/my.yaml"'
	assert_eq "/x/my.yaml" "$(core_config)"
}

test_core_tun_block_flow_and_default() {
	settings_init
	printf 'mixed-port: 7890\ntun:\n  enable: true\n  device: grka-tun\n  stack: system\ndns:\n  device: wrong\n' > "$MIHOMO_DIR/config.yaml"
	assert_eq grka-tun "$(core_tun)"
	printf 'tun: { enable: true, device: "my-tun", stack: system }\n' > "$MIHOMO_DIR/config.yaml"
	assert_eq my-tun "$(core_tun)"
	printf 'tun:\n  enable: true\nproxies: []\n' > "$MIHOMO_DIR/config.yaml"
	assert_eq Meta "$(core_tun)"
}

test_core_start_missing_binary_returns_3() {
	settings_init
	ensure_core() { echo ""; }
	core_start
	assert_eq 3 "$?"
}

test_core_start_missing_config_returns_4() {
	settings_init
	ensure_core() { echo /fake/mihomo; }
	core_start
	assert_eq 4 "$?"
}

test_core_start_spawns_with_args_and_writes_pid() {
	settings_init
	ensure_core() { echo /fake/mihomo; }
	echo 'tun: {device: grka-tun}' > "$MIHOMO_DIR/config.yaml"
	spawn_bg() { echo "$*" > "$T/spawn"; SPAWN_PID=777; }
	core_start
	assert_eq 0 "$?"
	assert_eq "$CORE_LOG /fake/mihomo -d $MIHOMO_DIR -f $MIHOMO_DIR/config.yaml" "$(cat "$T/spawn")"
	assert_eq 777 "$(cat "$CORE_PIDFILE")"
	assert_contains "$(cat "$CORE_LOG")" "[grka] запуск mihomo"
}

test_core_stop_terminates_then_kills() {
	echo 555 > "$CORE_PIDFILE"
	pid_alive() { [ "$1" = 555 ] && [ ! -f "$T/dead" ]; }
	kill() { echo "kill $*" >> "$T/kills"; [ "$1" != "-9" ] || : > "$T/dead"; return 0; }
	sleep() { :; }
	core_stop
	assert_eq "kill 555 kill -9 555" "$(tr '\n' ' ' < "$T/kills" | sed 's/ $//')"
	assert_file_missing "$CORE_PIDFILE"
}

test_core_log_rotate_copytruncate() {
	CORE_LOG_MAX=10
	printf '0123456789abcdef' > "$CORE_LOG"
	core_log_rotate
	assert_eq 0123456789abcdef "$(cat "$CORE_LOG.old")"
	assert_eq "" "$(cat "$CORE_LOG")"
}

test_core_find_pid_in_proc() {
	mkdir -p "$GRKA_PROC/1234" "$GRKA_PROC/99"
	printf '/opt/sbin/mihomo\000-d\000%s\000-f\000x.yaml\000' "$MIHOMO_DIR" > "$GRKA_PROC/1234/cmdline"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/99/cmdline"
	assert_eq 1234 "$(core_find_pid)"
}

test_core_validate_reports_not_installed() {
	ensure_core() { echo ""; }
	_o="$(core_validate x.yaml)"
	_r=$?
	assert_eq 3 "$_r"
	assert_contains "$_o" "не установлено"
}

test_core_api_port_and_secret() {
	settings_init
	printf "external-controller: 0.0.0.0:9191\nsecret: 'abc'\n" > "$MIHOMO_DIR/config.yaml"
	assert_eq 9191 "$(core_api_port)"
	assert_eq abc "$(core_api_secret)"
}

run_tests "$0"
