#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"
. "$GRKA_SRC/lib/rci.sh"

test_rci_get_ok_returns_body() {
	settings_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	_out="$(rci_get show/ip/policy)"
	assert_eq 0 "$?"
	assert_contains "$_out" '"Policy0"'
}

test_rci_get_sends_token_only_when_set() {
	settings_init
	stub_rci show/version 200 "$FIXTURES/policy.json"
	rci_get show/version >/dev/null
	assert_not_contains "$(cat "$STUB/calls")" "X-Ndma-Tkn"
	settings_set rci_token '"abc123"'
	rci_get show/version >/dev/null
	assert_contains "$(cat "$STUB/calls")" "-H X-Ndma-Tkn: abc123"
}

test_rci_get_401_returns_2() {
	settings_init
	stub_rci show/ip/policy 401
	rci_get show/ip/policy >/dev/null
	assert_eq 2 "$?"
}

test_rci_get_unreachable_returns_1() {
	settings_init
	rci_get show/ip/policy >/dev/null
	assert_eq 1 "$?"
}

test_mark_normalize_variants() {
	assert_eq 0xffffaab "$(mark_normalize ffffaab)"
	assert_eq 0xffffaab "$(mark_normalize 0xFFFFAAB)"
	assert_eq 0xffffaab "$(mark_normalize 268434091)"
	if mark_normalize "0xZZ" >/dev/null; then fail "мусор принят"; fi
	if mark_normalize "" >/dev/null; then fail "пусто принято"; fi
	if mark_normalize "null" >/dev/null; then fail "null принят"; fi
}

test_policy_lookup_found_case_insensitive() {
	settings_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	assert_eq "Policy0 0xffffaab" "$(rci_policy_lookup grka)"
}

test_policy_lookup_cyrillic_name() {
	settings_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	assert_eq "Policy1 0xffffaac" "$(rci_policy_lookup "Дети")"
}

test_policy_lookup_missing_returns_3() {
	settings_init
	echo '{}' > "$T/empty.json"
	stub_rci show/ip/policy 200 "$T/empty.json"
	rci_policy_lookup GrKa >/dev/null
	assert_eq 3 "$?"
}

test_policy_lookup_passes_auth_code() {
	settings_init
	stub_rci show/ip/policy 403
	rci_policy_lookup GrKa >/dev/null
	assert_eq 2 "$?"
}

test_policy_hosts_filters_and_normalizes() {
	settings_init
	stub_rci show/ip/hotspot 200 "$FIXTURES/hotspot.json"
	_h="$(rci_policy_hosts Policy0)"
	assert_eq 4 "$(printf '%s' "$_h" | jqt 'length')"
	assert_eq "aa:bb:cc:00:00:01" "$(printf '%s' "$_h" | jqt -r '.[0].mac')"
	assert_eq "macbook" "$(printf '%s' "$_h" | jqt -r '.[1].name')"
	assert_eq true "$(printf '%s' "$_h" | jqt -r '.[1].active')"
	assert_eq "" "$(printf '%s' "$_h" | jqt -r '.[3].ip')"
}

run_tests "$0"
