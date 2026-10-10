#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/routing.sh"

test_desired_rules_normal() {
	_w="$(rt_desired_rules 0xffffaab false "192.168.1.90 192.168.1.91")"
	assert_eq 5 "$(printf '%s\n' "$_w" | grep -c '^96|')"
	assert_contains "$_w" "96|all|192.168.0.0/16|0xffffaab|main"
	assert_contains "$_w" "97|192.168.1.90|all|0xffffaab|1002"
	assert_contains "$_w" "98|192.168.1.91|all|0xffffaab|main"
	assert_contains "$_w" "99|all|all|0xffffaab|1001"
}

test_desired_rules_paused() {
	_w="$(rt_desired_rules 0xffffaab true "192.168.1.90")"
	assert_not_contains "$_w" "|1002"
	assert_not_contains "$_w" "|1001"
	assert_contains "$_w" "99|all|all|0xffffaab|main"
}

test_desired_rules_skip_invalid_and_duplicate_ips() {
	_w="$(rt_desired_rules 0xffffaab false "192.168.1.90 192.168.1.90 192.168.001.090 192.168.1.300 1.2.3 abc 10.0.0.0")"
	assert_eq 2 "$(printf '%s\n' "$_w" | grep -c '^97|')"
	assert_eq 1 "$(printf '%s\n' "$_w" | grep -c '^97|192.168.1.90|')"
	assert_eq 1 "$(printf '%s\n' "$_w" | grep -c '^97|10.0.0.0|')"
	assert_not_contains "$_w" "192.168.001.090"
	assert_not_contains "$_w" "192.168.1.300"
}

test_rules_apply_adds_new_before_deleting_old() {
	rt_rules_apply 0xffffaab false "192.168.1.90" >/dev/null
	: > "$STUB/calls"
	rt_rules_apply 0xffffaac false "192.168.1.90" >/dev/null
	_add="$(grep -n 'rule add pref 99 fwmark 0xffffaac lookup 1001' "$STUB/calls" | cut -d: -f1)"
	_del="$(grep -n 'rule del pref 99 fwmark 0xffffaab lookup 1001' "$STUB/calls" | cut -d: -f1)"
	[ -n "$_add" ] && [ -n "$_del" ] || fail "нет нужных вызовов: add=[$_add] del=[$_del]"
	[ "${_add:-0}" -lt "${_del:-0}" ] || fail "новое правило 99 должно появиться раньше, чем удалится старое"
	assert_eq 1 "$(ip rule show | grep -c 'lookup 1001')"
	assert_not_contains "$(ip rule show)" "0xffffaab"
}

test_current_rules_parses_real_output_and_ignores_foreign() {
	ip() {
		printf '0:\tfrom all lookup local\n96:\tfrom all to 10.0.0.0/8 fwmark 0xffffaab lookup main\n97:\tfrom 192.168.1.90 fwmark 0xffffaab lookup 1002\n98:\tfrom all fwmark 0x5 lookup 200\n99:\tfrom all fwmark 0xffffaab lookup 1001\n100:\tfrom all fwmark 0xffffaaa lookup 42\n32766:\tfrom all lookup main\n'
	}
	_c="$(rt_current_rules)"
	assert_eq "$(printf '%s\n%s\n%s' '96|all|10.0.0.0/8|0xffffaab|main' '97|192.168.1.90|all|0xffffaab|1002' '99|all|all|0xffffaab|1001')" "$_c"
}

test_rules_apply_from_empty() {
	assert_eq changed "$(rt_rules_apply 0xffffaab false "192.168.1.90")"
	assert_eq 8 "$(ip rule show | grep -c 'fwmark 0xffffaab')"
	assert_contains "$(ip rule show)" "$(printf '96:\tfrom all to 10.0.0.0/8 fwmark 0xffffaab lookup main')"
	assert_contains "$(ip rule show)" "$(printf '97:\tfrom 192.168.1.90 fwmark 0xffffaab lookup 1002')"
	assert_contains "$(ip rule show)" "$(printf '99:\tfrom all fwmark 0xffffaab lookup 1001')"
}

test_rules_apply_twice_is_noop() {
	rt_rules_apply 0xffffaab false "192.168.1.90" >/dev/null
	: > "$STUB/calls"
	assert_eq "" "$(rt_rules_apply 0xffffaab false "192.168.1.90")"
	assert_eq 0 "$(grep -cE 'rule (add|del)' "$STUB/calls")"
}

test_rules_apply_replaces_stale_mark_and_keeps_foreign() {
	ip rule add pref 99 fwmark 0xdead lookup 1001
	ip rule add pref 98 fwmark 0x5 lookup 200
	rt_rules_apply 0xffffaab false "" >/dev/null
	assert_not_contains "$(ip rule show)" "0xdead"
	assert_contains "$(ip rule show)" "fwmark 0x5 lookup 200"
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001"
}

test_rules_apply_removes_duplicates() {
	rt_rules_apply 0xffffaab false "" >/dev/null
	ip rule add pref 99 fwmark 0xffffaab lookup 1001
	rt_rules_apply 0xffffaab false "" >/dev/null
	assert_eq 1 "$(ip rule show | grep -c 'lookup 1001')"
}

test_tables_apply() {
	RT_TUN=grka-tun
	assert_eq changed "$(rt_tables_apply false)"
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
	stub_link_up grka-tun
	rt_tables_apply true >/dev/null
	assert_contains "$(ip route show table 1001)" "default dev grka-tun"
	assert_contains "$(ip route show table 1002)" "198.18.0.0/15 dev grka-tun"
	assert_eq "" "$(rt_tables_apply true)"
	stub_link_down grka-tun
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
}

test_rt6_apply_and_disable() {
	assert_eq changed "$(rt6_apply 0xffffaab true)"
	assert_eq "$(printf '99:\tfrom all fwmark 0xffffaab prohibit')" "$(ip -6 rule show)"
	assert_eq "" "$(rt6_apply 0xffffaab true)"
	assert_eq changed "$(rt6_apply 0xffffaac true)"
	assert_eq 1 "$(ip -6 rule show | grep -c prohibit)"
	assert_eq changed "$(rt6_apply 0xffffaac false)"
	assert_eq "" "$(ip -6 rule show)"
}

test_rt_clear_removes_ours_keeps_foreign() {
	RT_TUN=grka-tun
	stub_link_up grka-tun
	ip rule add pref 100 fwmark 0xffffaaa lookup 42
	rt_rules_apply 0xffffaab false "192.168.1.90" >/dev/null
	rt_tables_apply true >/dev/null
	rt6_apply 0xffffaab true >/dev/null
	rt_clear
	assert_eq "$(printf '100:\tfrom all fwmark 0xffffaaa lookup 42')" "$(ip rule show)"
	assert_eq "" "$(ip -6 rule show)"
	assert_eq "" "$(ip route show table 1001)"
	assert_eq "" "$(ip route show table 1002)"
}

test_rpfilter_sets_loose() {
	RT_TUN=grka-tun
	mkdir -p "$GRKA_PROC/sys/net/ipv4/conf/grka-tun"
	echo 1 > "$GRKA_PROC/sys/net/ipv4/conf/grka-tun/rp_filter"
	rt_rpfilter
	assert_eq 2 "$(cat "$GRKA_PROC/sys/net/ipv4/conf/grka-tun/rp_filter")"
}

run_tests "$0"
