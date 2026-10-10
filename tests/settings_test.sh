#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"

test_settings_init_creates_defaults() {
	settings_init
	assert_eq GrKa "$(settings_get policy_name)"
	assert_eq 1100 "$(settings_get panel_port)"
	assert_eq true "$(settings_get autostart)"
	assert_eq 1053 "$(settings_get dns_port)"
}

test_settings_init_keeps_values_and_adds_missing() {
	echo '{"policy_name":"Дом","panel_port":2000}' > "$SETTINGS_FILE"
	settings_init
	assert_eq "Дом" "$(settings_get policy_name)"
	assert_eq 2000 "$(settings_get panel_port)"
	assert_eq true "$(settings_get ipv6_block)"
}

test_settings_init_moves_broken_file() {
	echo 'это не json' > "$SETTINGS_FILE"
	settings_init
	assert_file_exists "$SETTINGS_FILE.broken"
	assert_eq GrKa "$(settings_get policy_name)"
}

test_settings_set_cyrillic_name_with_quotes() {
	settings_init
	_name='Мой "VPN" / & '\''дом'\'''
	settings_set policy_name "$(json_str "$_name")"
	assert_eq "$_name" "$(settings_get policy_name)"
}

test_json_get_prints_false() {
	state_init
	assert_eq false "$(state_get paused)"
	state_set paused true
	assert_eq true "$(state_get paused)"
}

test_json_get_missing_key_is_empty() {
	settings_init
	assert_eq "" "$(settings_get nonexistent)"
}

test_state_set_device_gaming_and_back() {
	state_init
	state_set_device AA:BB:CC:00:00:01 gaming || fail "gaming"
	assert_eq gaming "$(state_get 'devices["aa:bb:cc:00:00:01"].type')"
	state_set_device aa:bb:cc:00:00:01 regular || fail "regular"
	assert_eq "{}" "$(jqt -c .devices "$STATE_FILE")"
}

test_state_set_device_rejects_garbage() {
	state_init
	if state_set_device 'aa:bb"; rm -rf /' gaming; then fail "мусорный MAC принят"; fi
	if state_set_device aa:bb:cc:00:00:01 weird; then fail "неизвестный тип принят"; fi
	assert_eq "{}" "$(jqt -c .devices "$STATE_FILE")"
}

test_policy_name_valid() {
	policy_name_valid "GrKa" || fail "GrKa"
	policy_name_valid "Мой VPN" || fail "кириллица"
	if policy_name_valid ""; then fail "пустое"; fi
	if policy_name_valid "$(printf 'a\tb')"; then fail "управляющий символ"; fi
	if policy_name_valid "$(printf '%065d' 0)"; then fail "65 символов"; fi
	assert_eq 1 1
}

run_tests "$0"
