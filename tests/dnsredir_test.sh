#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/dnsredir.sh"

test_dns_apply_failure_is_not_a_change() {
	stub_fail "REDIRECT"
	_o="$(dns_apply "192.168.1.90" 1053)"
	_r=$?
	assert_eq "" "$_o" "несработавшая команда — не изменение"
	assert_eq 1 "$_r"
}

test_dns_apply_creates_chain_and_one_jump() {
	assert_eq changed "$(dns_apply "192.168.1.90" 1053)"
	assert_eq 2 "$(iptables -t nat -S GRKA_DNS | grep -c -- '^-A')"
	assert_eq 1 "$(iptables -t nat -S PREROUTING | grep -c -- '-j GRKA_DNS$')"
	assert_eq "-A PREROUTING -j GRKA_DNS" "$(iptables -t nat -S PREROUTING | sed -n 2p)"
}

test_dns_apply_twice_noop() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	: > "$STUB/calls"
	assert_eq "" "$(dns_apply "192.168.1.90" 1053)"
	assert_eq 0 "$(grep -cE -- ' -(A|I|D|F|X) ' "$STUB/calls")"
}

test_dns_apply_rebuilds_on_ip_change() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_eq changed "$(dns_apply "192.168.1.91" 1053)"
	assert_not_contains "$(iptables -t nat -S GRKA_DNS)" "192.168.1.90"
	assert_contains "$(iptables -t nat -S GRKA_DNS)" "-s 192.168.1.91/32 -p tcp --dport 53"
}

test_dns_apply_rebuilds_on_port_change() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_eq changed "$(dns_apply "192.168.1.90" 5353)"
	assert_contains "$(iptables -t nat -S GRKA_DNS)" "--to-ports 5353"
	assert_not_contains "$(iptables -t nat -S GRKA_DNS)" "--to-ports 1053"
}

test_dns_apply_replaces_0_0_2_marked_jump() {
	iptables -t nat -N GRKA_DNS
	iptables -t nat -I PREROUTING 1 -m mark --mark 0xffffaab -j GRKA_DNS
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_not_contains "$(iptables -t nat -S PREROUTING)" "--mark"
	assert_eq 1 "$(iptables -t nat -S PREROUTING | grep -c -- '-j GRKA_DNS$')"
}

test_dns_apply_empty_clears() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_eq changed "$(dns_apply "" 1053)"
	assert_eq "" "$(iptables -t nat -S GRKA_DNS 2>/dev/null)"
	assert_eq 0 "$(iptables -t nat -S PREROUTING | grep -c GRKA_DNS)"
	assert_eq "" "$(dns_clear)"
}

test_dns_current_lines_strips_match_modules() {
	iptables() {
		[ "$*" = "-w -t nat -S GRKA_DNS" ] || return 1
		printf '%s\n' '-N GRKA_DNS' '-A GRKA_DNS -s 192.168.1.90/32 -p udp -m udp --dport 53 -j REDIRECT --to-ports 1053'
	}
	assert_eq "-A GRKA_DNS -s 192.168.1.90/32 -p udp --dport 53 -j REDIRECT --to-ports 1053" "$(dns_current_lines)"
}

run_tests "$0"
