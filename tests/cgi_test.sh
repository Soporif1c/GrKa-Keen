#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"

API="$GRKA_SRC/www/cgi-bin/api"

# $1 - тело. Окружение запроса можно поменять переменными H_METHOD, H_CT, H_X, H_ORIGIN, H_HOST, H_FWD
cgi_call() {
	_len="$(printf '%s' "$1" | wc -c | tr -d ' ')"
	_resp="$(printf '%s' "$1" | REQUEST_METHOD="${H_METHOD:-POST}" CONTENT_TYPE="${H_CT-application/json}" \
		HTTP_X_GRKA_REQUEST="${H_X-1}" HTTP_ORIGIN="${H_ORIGIN:-}" HTTP_HOST="${H_HOST:-192.168.1.1:1100}" \
		HTTP_X_FORWARDED_HOST="${H_FWD:-}" CONTENT_LENGTH="$_len" sh "$API" | tr -d '\r')"
	CGI_STATUS="$(printf '%s\n' "$_resp" | sed -n '1s/^Status: \([0-9]*\).*/\1/p')"
	CGI_BODY="$(printf '%s\n' "$_resp" | sed '1,/^$/d')"
}

body() {
	printf '%s' "$CGI_BODY" | jqt -r "$1"
}

fake_watchdog_alive() {
	mkdir -p "$GRKA_PROC/$$"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/$$/cmdline"
	echo $$ > "$GRKA_RUN/watchdog.pid"
}

test_csrf_rejects_missing_header() {
	settings_init
	H_X="" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
	assert_eq forbidden "$(body .code)"
}

test_csrf_rejects_wrong_content_type() {
	settings_init
	H_CT="text/plain" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_rejects_get() {
	settings_init
	H_METHOD=GET cgi_call ''
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_rejects_foreign_origin() {
	settings_init
	H_ORIGIN="https://evil.example" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_allows_same_origin_and_forwarded_host() {
	settings_init
	state_init
	H_ORIGIN="http://192.168.1.1:1100" cgi_call '{"method":"status"}'
	assert_eq 200 "$CGI_STATUS"
	settings_set allowed_hosts '["home.keenetic.pro"]'
	H_ORIGIN="https://home.keenetic.pro" H_FWD="home.keenetic.pro" cgi_call '{"method":"status"}'
	assert_eq 200 "$CGI_STATUS"
}

test_csrf_rejects_dns_rebinding_host() {
	settings_init
	H_HOST="evil.example:1100" H_ORIGIN="http://evil.example:1100" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
	H_HOST="evil.example:1100" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_rejects_forged_forwarded_host() {
	settings_init
	H_HOST="192.168.1.1:1100" H_ORIGIN="http://evil.example" H_FWD="evil.example" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_allows_known_names_and_ip_literals() {
	settings_init
	state_init
	H_HOST="my.keenetic.net:1100" H_ORIGIN="http://my.keenetic.net:1100" cgi_call '{"method":"status"}'
	assert_eq 200 "$CGI_STATUS"
	H_HOST="[fe80::1]:1100" cgi_call '{"method":"status"}'
	assert_eq 200 "$CGI_STATUS"
	settings_set allowed_hosts '["router.home"]'
	H_HOST="Router.Home:1100" H_ORIGIN="http://Router.Home:1100" cgi_call '{"method":"status"}'
	assert_eq 200 "$CGI_STATUS"
}

test_settings_set_allowed_hosts_validated() {
	settings_init
	cgi_call '{"method":"settings.set","params":{"allowed_hosts":["home.keenetic.pro","bad host"]}}'
	assert_eq false "$(body .ok)"
	cgi_call '{"method":"settings.set","params":{"allowed_hosts":["Home.Keenetic.Pro"]}}'
	assert_eq true "$(body .ok)"
	assert_eq "home.keenetic.pro" "$(settings_get 'allowed_hosts[0]')"
}

test_status_without_watchdog_is_down() {
	settings_init
	state_init
	cgi_call '{"method":"status"}'
	assert_eq true "$(body .ok)"
	assert_eq down "$(body .state)"
	assert_eq false "$(body .running)"
}

test_status_merges_watchdog_file() {
	settings_init
	state_init
	fake_watchdog_alive
	printf '%s' '{"state":"ok","warnings":[],"core":{"running":true,"pid":"42","memory_kb":"48000","error":"","error_log":"","enabled":true},"policy":{"name":"GrKa","found":true,"mark":"0xffffaab","rci":"ok","hosts":[{"mac":"aa:bb:cc:00:00:01","ip":"192.168.1.90","name":"PS5","type":"gaming"}]},"routing":{"rules_ok":true,"tun":"grka-tun","tun_up":true},"paused":false}' > "$STATUS_FILE"
	cgi_call '{"method":"status"}'
	assert_eq ok "$(body .state)"
	assert_eq true "$(body .running)"
	assert_eq true "$(body .policy.rule_ok)"
	assert_eq "PS5 (игровое)" "$(body '.policy.clients[0]')"
}

test_status_warns_about_open_api() {
	settings_init
	state_init
	printf "external-controller: 0.0.0.0:9090\nsecret: ''\n" > "$MIHOMO_DIR/config.yaml"
	cgi_call '{"method":"status"}'
	assert_eq true "$(body .api_open)"
	assert_contains "$(body '.warnings | join(" ")')" "без пароля"
}

test_settings_get_hides_token() {
	settings_init
	settings_set rci_token '"tok123"'
	cgi_call '{"method":"settings.get"}'
	assert_eq true "$(body .settings.has_token)"
	assert_not_contains "$CGI_BODY" "tok123"
}

test_settings_set_validates() {
	settings_init
	cgi_call '{"method":"settings.set","params":{"panel_port":80}}'
	assert_eq false "$(body .ok)"
	assert_contains "$(body .error)" "Порт"
	cgi_call '{"method":"settings.set","params":{"rci_token":"a b"}}'
	assert_eq false "$(body .ok)"
	cgi_call '{"method":"settings.set","params":{"panel_port":2000,"rci_token":"Abc.123","evil":1}}'
	assert_eq true "$(body .ok)"
	assert_eq 2000 "$(settings_get panel_port)"
	assert_eq "Abc.123" "$(settings_get rci_token)"
	assert_eq "" "$(settings_get evil)"
	assert_file_exists "$GRKA_RUN/rci-refresh"
}

test_set_policy_updates_settings_and_flags() {
	settings_init
	cgi_call '{"method":"set_policy","params":{"name":"Мой VPN / & \"дом\""}}'
	assert_eq true "$(body .ok)"
	assert_eq 'Мой VPN / & "дом"' "$(settings_get policy_name)"
	assert_file_exists "$GRKA_RUN/dirty"
	cgi_call '{"method":"set_policy","params":{"name":""}}'
	assert_eq false "$(body .ok)"
}

test_devices_set_type_and_get() {
	settings_init
	state_init
	echo '[{"mac":"aa:bb:cc:00:00:01","ip":"192.168.1.90","name":"PS5","active":true}]' > "$HOSTS_FILE"
	cgi_call '{"method":"devices.set_type","params":{"mac":"AA:BB:CC:00:00:01","type":"gaming"}}'
	assert_eq true "$(body .ok)"
	cgi_call '{"method":"devices.get"}'
	assert_eq gaming "$(body '.devices[0].type')"
	cgi_call '{"method":"devices.set_type","params":{"mac":"bad","type":"gaming"}}'
	assert_eq false "$(body .ok)"
}

test_service_actions_map_to_state_and_flags() {
	settings_init
	state_init
	cgi_call '{"method":"service","params":{"action":"stop"}}'
	assert_eq false "$(state_get enabled)"
	cgi_call '{"method":"service","params":{"action":"start"}}'
	assert_eq true "$(state_get enabled)"
	cgi_call '{"method":"service","params":{"action":"restart"}}'
	assert_file_exists "$GRKA_RUN/restart-core"
	cgi_call '{"method":"service","params":{"action":"disable"}}'
	assert_eq false "$(settings_get autostart)"
	cgi_call '{"method":"service.pause"}'
	assert_eq true "$(state_get paused)"
}

test_journal_returns_newest_first() {
	settings_init
	journal info "первое"
	journal warn "второе"
	cgi_call '{"method":"journal"}'
	assert_eq "второе" "$(body '.entries[0].message')"
	assert_eq warn "$(body '.entries[0].level')"
}

test_set_config_without_core_saves_with_warning() {
	settings_init
	cgi_call '{"method":"set_config","params":{"content":"mixed-port: 7890\n"}}'
	assert_eq true "$(body .ok)"
	assert_contains "$(body .warning)" "без проверки"
	assert_eq "mixed-port: 7890" "$(cat "$MIHOMO_DIR/config.yaml")"
}

test_unknown_method() {
	settings_init
	cgi_call '{"method":"rm_rf"}'
	assert_eq false "$(body .ok)"
	assert_contains "$(body .error)" "Неизвестный метод"
}

run_tests "$0"
