#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
GRKA_CLI_NO_MAIN=1
. "$GRKA_SRC/bin/grka"

test_device_command_sets_type_and_kicks() {
	settings_init
	state_init
	assert_contains "$(grka_main device AA:BB:CC:00:00:01 gaming)" "игровое"
	assert_eq gaming "$(jqt -r '.devices["aa:bb:cc:00:00:01"].type' "$STATE_FILE")"
	assert_file_exists "$DIRTY_FLAG"
}

test_device_command_rejects_bad_input() {
	settings_init
	state_init
	assert_contains "$(grka_main device zz gaming)" "Неверный MAC"
	assert_contains "$(grka_main device aa:bb:cc:00:00:01 weird)" "Использование"
}

test_pause_resume() {
	settings_init
	state_init
	grka_main pause >/dev/null
	assert_eq true "$(state_get paused)"
	assert_contains "$(cat "$JOURNAL_FILE")" "на паузу"
	grka_main resume >/dev/null
	assert_eq false "$(state_get paused)"
}

test_start_requests_retry() {
	settings_init
	state_init
	grka_main start >/dev/null
	assert_file_exists "$GRKA_RUN/start-core" "grka start после ошибки ядра — новая попытка"
}

test_start_stop_restart() {
	settings_init
	state_init
	flag_set hold
	grka_main start >/dev/null
	assert_file_missing "$GRKA_RUN/hold"
	assert_eq true "$(state_get enabled)"
	grka_main stop >/dev/null
	assert_eq false "$(state_get enabled)"
	grka_main restart >/dev/null
	assert_file_exists "$GRKA_RUN/restart-core"
}

test_diag_redacts_token_and_masks_macs() {
	settings_init
	state_init
	settings_set rci_token '"secret-token-123"'
	printf '%s' '{"policy":{"hosts":[{"mac":"aa:bb:cc:dd:ee:ff"}]}}' > "$STATUS_FILE"
	DIAG_DIR="$T"
	_f="$(grka_diag)"
	assert_file_exists "$_f"
	assert_not_contains "$(cat "$_f")" "secret-token-123"
	assert_contains "$(cat "$_f")" "aa:bb:cc:**:**:**"
	assert_not_contains "$(cat "$_f")" "dd:ee:ff"
}

test_status_without_watchdog() {
	assert_contains "$(grka_main status)" "Сторож не запущен"
}

run_tests "$0"
