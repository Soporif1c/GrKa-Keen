#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"
. "$GRKA_SRC/lib/rci.sh"
. "$GRKA_SRC/lib/routing.sh"
. "$GRKA_SRC/lib/dnsredir.sh"
. "$GRKA_SRC/lib/core.sh"
. "$GRKA_SRC/lib/watchdog.sh"

# Ядро-подделка: состояние в файлах $T, TUN появляется при старте
fake_core() {
	core_running() { [ -f "$T/core.up" ]; }
	core_start() { echo start >> "$T/core.calls"; : > "$T/core.up"; stub_link_up grka-tun; return 0; }
	core_stop() { echo stop >> "$T/core.calls"; rm -f "$T/core.up"; stub_link_down grka-tun; }
	core_validate() { if [ -f "$T/core.badcfg" ]; then echo "bad config line 3"; return 1; fi; return 0; }
	core_config_sig() { cat "$T/core.sig" 2>/dev/null; }
	core_tun() { echo grka-tun; }
	core_pid() { echo 4242; }
	core_dns_port() { printf '%s' "${FAKE_DNS_PORT-1053}"; }
	sleep() { :; }
	NOW=1000
	now_ts() { echo "$NOW"; }
}

base_rci_ok() {
	settings_init
	state_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	stub_rci show/ip/hotspot 200 "$FIXTURES/hotspot.json"
}

st() {
	jqt -r "$1" "$STATUS_FILE"
}

test_tick_starts_core_and_applies_full_rules() {
	fake_core
	base_rci_ok
	wd_tick
	assert_eq start "$(cat "$T/core.calls")"
	assert_contains "$(ip route show table 1001)" "default dev grka-tun"
	assert_contains "$(ip route show table 1002)" "198.18.0.0/15 dev grka-tun"
	assert_contains "$(ip rule show)" "$(printf '99:\tfrom all fwmark 0xffffaab lookup 1001')"
	assert_eq ok "$(st .state)"
	assert_eq true "$(st .routing.tun_up)"
	assert_contains "$(cat "$JOURNAL_FILE")" "Ядро mihomo запущено"
	assert_contains "$(cat "$JOURNAL_FILE")" "Правила маршрутизации применены"
}

test_tick_first_pass_sets_kill_switch_before_core_start() {
	fake_core
	base_rci_ok
	core_start() {
		ip rule show > "$T/rules_at_start"
		ip route show table 1001 > "$T/t1001_at_start"
		echo start >> "$T/core.calls"; : > "$T/core.up"; stub_link_up grka-tun; return 0
	}
	wd_tick
	assert_contains "$(cat "$T/rules_at_start")" "fwmark 0xffffaab lookup 1001" "правило 99 стоит до запуска ядра"
	assert_contains "$(cat "$T/t1001_at_start")" "unreachable default" "пока ядро стартует, трафик политики не уходит мимо VPN"
	assert_contains "$(ip route show table 1001)" "default dev grka-tun"
	assert_eq 1 "$(grep -c 'Правила маршрутизации' "$JOURNAL_FILE")" "одно «применены», без ложного «восстановлены»"
}

test_routes_table_before_rule() {
	fake_core
	base_rci_ok
	wd_tick
	_tl="$(grep -n 'ip route replace unreachable' "$STUB/calls" | head -n 1 | cut -d: -f1)"
	_rl="$(grep -n 'ip rule add.*lookup 1001' "$STUB/calls" | head -n 1 | cut -d: -f1)"
	assert_eq yes "$(if [ "${_tl:-99999}" -lt "${_rl:-0}" ]; then echo yes; else echo no; fi)" "маршрут unreachable появляется раньше правила 99"
}

test_tick_watchdog_restart_is_quiet() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	wd_tick
	rm -f "$WD_ENV"
	NOW=1010; wd_tick
	assert_eq 1 "$(grep -c 'Правила маршрутизации' "$JOURNAL_FILE")" "перезапуск сторожа при работающем ядре правила не трогает"
	assert_eq 1 "$(grep -c 'Перенаправление DNS' "$JOURNAL_FILE")"
}

test_tick_policy_appears_after_boot() {
	fake_core
	settings_init
	state_init
	echo '{}' > "$T/empty.json"
	stub_rci_seq show/ip/policy "200 $T/empty.json" "200 $FIXTURES/policy.json"
	stub_rci show/ip/hotspot 200 "$FIXTURES/hotspot.json"
	wd_tick
	assert_eq waiting_policy "$(st .state)"
	assert_eq "" "$(ip rule show)"
	NOW=1002
	wd_tick
	assert_eq ok "$(st .state)"
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001"
	assert_contains "$(cat "$JOURNAL_FILE")" "попыток: 2"
}

test_tick_rci_down_uses_cached_mark() {
	fake_core
	settings_init
	state_init
	mkdir -p "$CACHE_DIR"
	echo "Policy0 0xffffaab" > "$CACHE_DIR/policy_mark"
	stub_rci show/ip/policy 000
	wd_tick
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001"
	assert_eq down "$(st .policy.rci)"
	assert_contains "$(cat "$JOURNAL_FILE")" "сохранённую метку"
}

test_tick_rci_auth_warns_about_token() {
	fake_core
	settings_init
	state_init
	stub_rci show/ip/policy 401
	wd_tick
	assert_eq auth "$(st .policy.rci)"
	assert_contains "$(st '.warnings | join(" ")')" "токен RCI"
}

test_tick_mark_change_replaces_rules() {
	fake_core
	base_rci_ok
	wd_tick
	printf '%s' '{"Policy0":{"description":"GrKa","mark":"ffffaad"}}' > "$T/policy2.json"
	stub_rci show/ip/policy 200 "$T/policy2.json"
	NOW=1061
	wd_tick
	assert_not_contains "$(ip rule show)" "0xffffaab"
	assert_contains "$(ip rule show)" "fwmark 0xffffaad lookup 1001"
	assert_contains "$(cat "$JOURNAL_FILE")" "сменилась"
}

test_tick_policy_missing_briefly_keeps_rules() {
	fake_core
	base_rci_ok
	wd_tick
	echo '{}' > "$T/empty.json"
	stub_rci_seq show/ip/policy "200 $T/empty.json" "200 $T/empty.json" "200 $FIXTURES/policy.json"
	NOW=1061; wd_tick
	NOW=1071; wd_tick
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001" "политика пропала меньше чем на 30 с — правила на месте"
	NOW=1081; wd_tick
	assert_eq ok "$(st .state)"
	assert_eq 1 "$(grep -c 'найдена' "$JOURNAL_FILE")" "кратковременный пропуск политики в журнал не пишется"
}

test_tick_policy_deleted_clears_rules_after_30s() {
	fake_core
	base_rci_ok
	wd_tick
	echo '{}' > "$T/empty.json"
	stub_rci show/ip/policy 200 "$T/empty.json"
	NOW=1061; wd_tick
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001"
	NOW=1091; wd_tick
	assert_eq "" "$(ip rule show)"
	assert_eq waiting_policy "$(st .state)"
	assert_file_missing "$CACHE_DIR/policy_mark" "метка удалённой политики забывается"
	assert_eq 1 "$(grep -c 'не найдена в Keenetic' "$JOURNAL_FILE")"
}

test_tick_policy_missing_at_boot_keeps_cached_mark() {
	fake_core
	settings_init
	state_init
	mkdir -p "$CACHE_DIR"
	echo "Policy0 0xffffaab" > "$CACHE_DIR/policy_mark"
	echo '{}' > "$T/empty.json"
	stub_rci show/ip/policy 200 "$T/empty.json"
	wd_tick
	assert_eq waiting_policy "$(st .state)"
	assert_file_exists "$CACHE_DIR/policy_mark" "один ответ без политики при загрузке не стирает сохранённую метку"
}

test_tick_core_crash_backoff_and_stop() {
	fake_core
	base_rci_ok
	wd_tick
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1010; wd_tick
	assert_eq 1 "$(grep -c start "$T/core.calls")"
	NOW=1016; wd_tick
	assert_eq 2 "$(grep -c start "$T/core.calls")"
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1020; wd_tick
	NOW=1036; wd_tick
	assert_eq 3 "$(grep -c start "$T/core.calls")"
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1040; wd_tick
	NOW=1101; wd_tick
	assert_eq 4 "$(grep -c start "$T/core.calls")"
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1110; wd_tick
	NOW=1500; wd_tick
	assert_eq 4 "$(grep -c start "$T/core.calls")"
	assert_eq error "$(st .state)"
	assert_contains "$(cat "$JOURNAL_FILE")" "повторы остановлены"
	assert_contains "$(ip route show table 1001)" "unreachable default"
	assert_not_contains "$(ip route show table 1001)" "dev grka-tun"
}

test_tick_start_flag_retries_after_crash_loop() {
	fake_core
	base_rci_ok
	wd_tick
	for _t in 1010:1016 1020:1036 1040:1101; do
		rm -f "$T/core.up"; stub_link_down grka-tun
		NOW=${_t%:*}; wd_tick
		NOW=${_t#*:}; wd_tick
	done
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1110; wd_tick
	assert_eq error "$(st .state)"
	flag_set start-core
	NOW=1120; wd_tick
	assert_eq 5 "$(grep -c start "$T/core.calls")" "«Запустить» после череды падений — новая попытка сразу"
	assert_eq ok "$(st .state)"
}

test_tick_bad_config_no_loop_until_changed() {
	fake_core
	base_rci_ok
	: > "$T/core.badcfg"
	echo sig1 > "$T/core.sig"
	wd_tick
	NOW=1010; wd_tick
	NOW=1500; wd_tick
	assert_file_missing "$T/core.calls" "ядро не должно запускаться с битым конфигом"
	assert_eq error "$(st .state)"
	assert_contains "$(st .core.error_log)" "bad config"
	assert_eq 1 "$(grep -c 'не прошёл проверку' "$JOURNAL_FILE")"
	rm -f "$T/core.badcfg"
	echo sig2 > "$T/core.sig"
	NOW=1510; wd_tick
	assert_eq start "$(cat "$T/core.calls")"
	assert_eq ok "$(st .state)"
}

test_tick_bad_config_rechecked_every_5_minutes() {
	fake_core
	base_rci_ok
	: > "$T/core.badcfg"
	echo sig1 > "$T/core.sig"
	wd_tick
	rm -f "$T/core.badcfg"
	NOW=1200; wd_tick
	assert_file_missing "$T/core.calls" "раньше 5 минут повторной проверки нет"
	NOW=1301; wd_tick
	assert_eq start "$(cat "$T/core.calls")"
	assert_eq ok "$(st .state)"
	assert_eq 1 "$(grep -c 'не прошёл проверку' "$JOURNAL_FILE")"
}

test_tick_core_not_installed_reports_once() {
	fake_core
	base_rci_ok
	core_validate() { echo "Ядро mihomo не установлено"; return 3; }
	wd_tick
	NOW=1010; wd_tick
	assert_eq error "$(st .state)"
	assert_contains "$(st .core.error)" "не установлено"
	assert_eq 1 "$(grep -c 'не установлено' "$JOURNAL_FILE")"
}

test_tick_restart_flag_restarts_core() {
	fake_core
	base_rci_ok
	wd_tick
	flag_set restart-core
	NOW=1005
	wd_tick
	assert_eq "start stop start" "$(tr '\n' ' ' < "$T/core.calls" | sed 's/ $//')"
}

test_tick_paused_routes_main_without_dns() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	state_set paused true
	wd_tick
	assert_contains "$(ip rule show)" "$(printf '99:\tfrom all fwmark 0xffffaab lookup main')"
	assert_not_contains "$(ip rule show)" "lookup 1002"
	assert_eq "" "$(iptables -t nat -S GRKA_DNS 2>/dev/null)"
	assert_eq paused "$(st .state)"
}

test_tick_gaming_ips_skip_offline_and_broken() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	state_set_device aa:bb:cc:00:00:03 gaming
	state_set_device aa:bb:cc:00:00:05 gaming
	state_set_device aa:bb:cc:00:00:04 gaming
	wd_tick
	assert_eq "192.168.1.90" "$(st '.routing.gaming_ips | join(" ")')"
	assert_contains "$(ip rule show)" "$(printf '97:\tfrom 192.168.1.90 fwmark 0xffffaab lookup 1002')"
	assert_contains "$(ip rule show)" "$(printf '98:\tfrom 192.168.1.90 fwmark 0xffffaab lookup main')"
	assert_eq 2 "$(iptables -t nat -S GRKA_DNS | grep -c -- '^-A')"
}

test_tick_gaming_ips_only_online_and_valid() {
	fake_core
	base_rci_ok
	cat > "$T/hotspot2.json" <<'EOF'
{"host":[
 {"mac":"aa:bb:cc:00:00:01","ip":"192.168.1.90","name":"PS5","policy":"Policy0","active":true},
 {"mac":"aa:bb:cc:00:00:06","ip":"192.168.1.91","name":"Xbox","policy":"Policy0","active":false},
 {"mac":"aa:bb:cc:00:00:07","ip":"0.0.0.0","name":"Switch","policy":"Policy0","active":true},
 {"mac":"aa:bb:cc:00:00:08","ip":"999.1.1.1","name":"Deck","policy":"Policy0","active":true}
]}
EOF
	stub_rci show/ip/hotspot 200 "$T/hotspot2.json"
	for _m in 01 06 07 08; do state_set_device "aa:bb:cc:00:00:$_m" gaming; done
	wd_tick
	assert_eq "192.168.1.90" "$(st '.routing.gaming_ips | join(" ")')" "только устройство в сети и с правильным IP"
	assert_not_contains "$(ip rule show)" "192.168.1.91" "IP отключённой консоли может достаться обычному устройству"
	assert_not_contains "$(iptables -t nat -S GRKA_DNS)" "192.168.1.91"
}

test_tick_gaming_without_core_dns_listener_skips_redirect() {
	fake_core
	base_rci_ok
	FAKE_DNS_PORT=""
	state_set_device aa:bb:cc:00:00:01 gaming
	wd_tick
	assert_eq "" "$(iptables -t nat -S GRKA_DNS 2>/dev/null)"
	assert_contains "$(st '.warnings | join(" ")')" "dns.listen"
	assert_contains "$(ip rule show)" "lookup 1002"
}

test_tick_gaming_dns_uses_core_port() {
	fake_core
	base_rci_ok
	FAKE_DNS_PORT=5353
	state_set_device aa:bb:cc:00:00:01 gaming
	wd_tick
	assert_contains "$(iptables -t nat -S GRKA_DNS)" "--to-ports 5353"
}

test_tick_ipv6_rule_failure_warns_without_journal_flood() {
	fake_core
	base_rci_ok
	mkdir -p "$GRKA_PROC/net"
	: > "$GRKA_PROC/net/if_inet6"
	stub_fail "ip -6 rule add"
	wd_tick
	NOW=1010; wd_tick
	NOW=1020; wd_tick
	assert_eq 1 "$(grep -c 'Правила маршрутизации' "$JOURNAL_FILE")" "несработавшее правило IPv6 — не ремонт, журнал не засоряется"
	assert_contains "$(st '.warnings | join(" ")')" "IPv6"
	assert_eq ok "$(st .state)"
}

test_tick_without_ipv6_skips_v6_rule() {
	fake_core
	base_rci_ok
	wd_tick
	assert_not_contains "$(cat "$STUB/calls")" "ip -6 rule add" "без IPv6 в системе блокировать нечего"
	assert_eq "" "$(st '.warnings | join(" ")')"
}

test_tick_rule_failure_warns_and_not_ok() {
	fake_core
	base_rci_ok
	stub_fail "ip rule add"
	wd_tick
	NOW=1010; wd_tick
	assert_eq false "$(st .routing.rules_ok)"
	assert_contains "$(st '.warnings | join(" ")')" "правила маршрутизации"
	assert_eq 1 "$(grep -c 'Не удалось применить правила' "$JOURNAL_FILE")"
	assert_eq 0 "$(grep -c 'Правила маршрутизации применены' "$JOURNAL_FILE")"
}

test_tick_dns_redirect_failure_warns() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	stub_fail "REDIRECT"
	wd_tick
	NOW=1010; wd_tick
	assert_eq 0 "$(grep -c 'Перенаправление DNS' "$JOURNAL_FILE")" "несработавшее перенаправление — не обновление"
	assert_contains "$(st '.warnings | join(" ")')" "DNS игровых устройств"
}

test_tick_disabled_stops_core_keeps_capture() {
	fake_core
	base_rci_ok
	wd_tick
	state_set enabled false
	NOW=1010
	wd_tick
	assert_contains "$(cat "$T/core.calls")" stop
	assert_contains "$(ip rule show)" "lookup 1001"
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
	assert_eq stopped "$(st .state)"
}

test_tick_hold_flag_keeps_core_off() {
	fake_core
	base_rci_ok
	flag_set hold
	wd_tick
	assert_file_missing "$T/core.calls"
	assert_eq stopped "$(st .state)"
}

test_status_hosts_have_types() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	wd_tick
	assert_eq gaming "$(st '.policy.hosts[] | select(.mac == "aa:bb:cc:00:00:01") | .type')"
	assert_eq regular "$(st '.policy.hosts[] | select(.mac == "aa:bb:cc:00:00:02") | .type')"
	assert_eq GrKa "$(st .policy.name)"
}

test_xkeen_detected_warning() {
	fake_core
	base_rci_ok
	: > "$GRKA_INITD/S05xkeen"
	wd_tick
	assert_contains "$(st '.warnings | join(" ")')" "XKeen"
}

test_boot_stop_lasts_until_reboot_when_autostart_on() {
	settings_init
	state_init
	state_set enabled false
	wd_boot
	assert_eq true "$(state_get enabled)" "после перезагрузки при автозапуске ядро снова включено"
	assert_file_missing "$GRKA_RUN/hold"
}

test_boot_restart_keeps_user_stop() {
	settings_init
	state_init
	wd_boot
	state_set enabled false
	wd_boot
	assert_eq false "$(state_get enabled)" "перезапуск сторожа без перезагрузки не отменяет «Остановить»"
}

test_boot_autostart_off_holds_only_first_start() {
	settings_init
	state_init
	settings_set autostart false
	wd_boot
	assert_file_exists "$GRKA_RUN/hold" "после загрузки без автозапуска ядро ждёт кнопки"
	rm -f "$GRKA_RUN/hold"
	wd_boot
	assert_file_missing "$GRKA_RUN/hold" "перезапуск сторожа не останавливает ядро, запущенное вручную"
}

test_wd_main_second_instance_exits() {
	mkdir -p "$GRKA_PROC/$$"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/$$/cmdline"
	echo $$ > "$GRKA_RUN/watchdog.pid"
	assert_contains "$(wd_main)" "уже запущен"
}

run_tests "$0"
