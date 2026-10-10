#!/bin/sh
# Проверка тестового каркаса, заглушек и инструментов
. "$(dirname "$0")/lib/env.sh"

test_jq_keeps_quotes_slashes_and_cyrillic() {
	_out="$(jqt -n -r --arg s 'Мой "VPN" / & x' '$s | ascii_downcase')"
	assert_eq 'Мой "vpn" / & x' "$_out"
}

test_kill_0_on_self_works() {
	kill -0 $$ || fail "kill -0 \$\$ не работает в этой оболочке"
	assert_eq 1 1
}

test_ip_stub_add_show_del() {
	ip rule add pref 99 fwmark 0xffffaab lookup 1001
	assert_eq "$(printf '99:\tfrom all fwmark 0xffffaab lookup 1001')" "$(ip rule show)"
	ip rule del pref 99 fwmark 0xffffaab lookup 1001 || fail "del вернул ошибку"
	assert_eq "" "$(ip rule show)"
	if ip rule del pref 99; then fail "повторный del должен вернуть ошибку"; fi
}

test_ip_stub_routes_follow_link() {
	ip route replace unreachable default metric 4294967295 table 1001
	if ip route replace default dev grka-tun table 1001; then fail "маршрут через несуществующий интерфейс"; fi
	stub_link_up grka-tun
	ip route replace default dev grka-tun table 1001
	assert_eq "$(printf 'unreachable default metric 4294967295\ndefault dev grka-tun scope link')" "$(ip route show table 1001)"
	stub_link_down grka-tun
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
}

test_iptables_stub_chain_ops() {
	iptables -w -t nat -N GRKA_DNS
	iptables -w -t nat -A GRKA_DNS -s 1.2.3.4/32 -p udp --dport 53 -j REDIRECT --to-ports 1053
	iptables -w -t nat -I PREROUTING 1 -j GRKA_DNS
	assert_eq "$(printf '%s\n%s' '-N GRKA_DNS' '-A GRKA_DNS -s 1.2.3.4/32 -p udp --dport 53 -j REDIRECT --to-ports 1053')" "$(iptables -t nat -S GRKA_DNS)"
	iptables -t nat -C PREROUTING -j GRKA_DNS || fail "-C не нашёл правило"
	assert_eq "-P PREROUTING ACCEPT" "$(iptables -t nat -S PREROUTING | head -n 1)"
}

test_curl_stub_codes_and_seq() {
	echo '{"a":1}' > "$T/body.json"
	stub_rci show/version 200 "$T/body.json"
	assert_eq 200 "$(curl -s -o "$T/out" -w '%{http_code}' http://127.0.0.1:79/rci/show/version)"
	assert_eq '{"a":1}' "$(cat "$T/out")"
	stub_rci_seq show/ip/policy 000 "200 $T/body.json"
	assert_eq 000 "$(curl -s -o "$T/o2" -w '%{http_code}' http://127.0.0.1:79/rci/show/ip/policy)"
	assert_eq 200 "$(curl -s -o "$T/o3" -w '%{http_code}' http://127.0.0.1:79/rci/show/ip/policy)"
}

run_tests "$0"
