#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"

test_paths_follow_environment() {
	assert_eq "$T/etc/grka/settings.json" "$SETTINGS_FILE"
	assert_eq "$T/run/status.json" "$STATUS_FILE"
	assert_eq "$T/log/journal.log" "$JOURNAL_FILE"
}

test_write_atomic_replaces_content() {
	echo old > "$T/f"
	echo new | write_atomic "$T/f"
	assert_eq new "$(cat "$T/f")"
	assert_eq "" "$(ls "$T" | grep tmp)"
}

test_write_atomic_refuses_empty_input() {
	echo old > "$T/f"
	if printf '' | write_atomic "$T/f"; then fail "пустой ввод должен вернуть ошибку"; fi
	assert_eq old "$(cat "$T/f")"
}

test_journal_line_format() {
	journal info "Политика найдена"
	assert_contains "$(cat "$JOURNAL_FILE")" "|info|Политика найдена"
}

test_journal_flattens_newlines_and_pipes() {
	journal warn "$(printf 'a|b\nc')"
	assert_eq 1 "$(wc -l < "$JOURNAL_FILE" | tr -d ' ')"
	assert_contains "$(cat "$JOURNAL_FILE")" "|warn|a b c"
}

test_journal_rotates_over_limit() {
	JOURNAL_MAX=50
	journal info "1234567890123456789012345678901234567890"
	journal info "второй"
	journal info "третий"
	assert_file_exists "$JOURNAL_FILE.old"
	assert_contains "$(cat "$JOURNAL_FILE")" "третий"
}

test_flags() {
	if flag_take dirty; then fail "флага ещё нет"; fi
	flag_set dirty
	flag_take dirty || fail "флаг должен быть"
	assert_file_missing "$GRKA_RUN/dirty"
}

test_lock_twice_fails_then_release() {
	lock_acquire config || fail "первый захват"
	if lock_acquire config; then fail "второй захват должен провалиться"; fi
	lock_release config
	lock_acquire config || fail "захват после освобождения"
	assert_file_exists "$GRKA_RUN/config.lock/pid"
}

test_stale_lock_is_taken() {
	mkdir -p "$GRKA_RUN/config.lock"
	echo 99999999 > "$GRKA_RUN/config.lock/pid"
	lock_acquire config || fail "протухшая блокировка не снята"
	assert_eq "$$" "$(cat "$GRKA_RUN/config.lock/pid")"
}

test_pid_alive_checks_cmdline() {
	mkdir -p "$GRKA_PROC/$$"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/$$/cmdline"
	pid_alive $$ grka-watchdog || fail "свой процесс с подходящей строкой"
	if pid_alive $$ mihomo; then fail "строка не совпадает"; fi
	if pid_alive ""; then fail "пустой PID"; fi
	assert_eq 1 1
}

run_tests "$0"
