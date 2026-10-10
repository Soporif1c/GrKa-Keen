# shellcheck shell=sh
# Маршрутизация политики (спека §5.2). Только идемпотентные операции: сначала читаем, потом меняем.
#   pref 96: метка политики + частные сети -> main (локальные адреса не уходят в ядро)
#   pref 97: игровое устройство -> таблица 1002 (там только VPN-направления)
#   pref 98: игровое устройство -> main (всё остальное мимо ядра)
#   pref 99: метка политики -> таблица 1001 (всё в ядро); на паузе -> main
# Наши правила — pref 96–99 с lookup 1001/1002 или lookup main с fwmark. Чужие правила не трогаем.

RT_TABLE_CAPTURE=1001
RT_TABLE_GAME=1002
RT_TUN="${RT_TUN:-grka-tun}"
RT_FAKE_RANGE="198.18.0.0/15"
RT_PRIVATE="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10"

# $1 - метка, $2 - пауза (true/false), $3 - IP игровых устройств через пробел
rt_desired_rules() {
	for _rn in $RT_PRIVATE; do
		echo "96|all|$_rn|$1|main"
	done
	if [ "$2" = true ]; then
		echo "99|all|all|$1|main"
		return 0
	fi
	for _ri in $3; do
		echo "97|$_ri|all|$1|$RT_TABLE_GAME"
	done
	for _ri in $3; do
		echo "98|$_ri|all|$1|main"
	done
	echo "99|all|all|$1|$RT_TABLE_CAPTURE"
}

# Наши текущие правила в том же виде: pref|from|to|mark|table
rt_current_rules() {
	ip rule show 2>/dev/null | awk '
	{
		pref = $1
		sub(":", "", pref)
		if (pref < 96 || pref > 99) next
		from = "all"; to = "all"; mark = ""; table = ""
		for (i = 2; i <= NF; i++) {
			if ($i == "from") from = $(i + 1)
			else if ($i == "to") to = $(i + 1)
			else if ($i == "fwmark") { mark = $(i + 1); sub("/0xffffffff$", "", mark) }
			else if ($i == "lookup" || $i == "table") table = $(i + 1)
		}
		if (table == "1001" || table == "1002" || (table == "main" && mark != ""))
			print pref "|" from "|" to "|" mark "|" table
	}'
}

rt_rules_flush() {
	rt_current_rules | while IFS='|' read -r _p _f _t _m _tb; do
		set -- del pref "$_p"
		[ "$_f" = all ] || set -- "$@" from "$_f"
		[ "$_t" = all ] || set -- "$@" to "$_t"
		[ -z "$_m" ] || set -- "$@" fwmark "$_m"
		set -- "$@" lookup "$_tb"
		ip rule "$@" 2>/dev/null
	done
}

# Приводит правила к желаемым. При любом расхождении удаляет все наши и ставит заново (доли секунды)
rt_rules_apply() {
	_want="$(rt_desired_rules "$1" "$2" "$3")"
	_have="$(rt_current_rules)"
	if [ "$(printf '%s\n' "$_want" | sort)" = "$(printf '%s\n' "$_have" | sort)" ]; then
		return 0
	fi
	rt_rules_flush
	printf '%s\n' "$_want" | while IFS='|' read -r _p _f _t _m _tb; do
		[ -n "$_p" ] || continue
		set -- add pref "$_p"
		[ "$_f" = all ] || set -- "$@" from "$_f"
		[ "$_t" = all ] || set -- "$@" to "$_t"
		set -- "$@" fwmark "$_m" lookup "$_tb"
		ip rule "$@" 2>/dev/null
	done
	echo changed
}

# $1 - поднят ли TUN (true/false). unreachable в 1001 стоит всегда: без ядра нет утечки мимо VPN
rt_tables_apply() {
	_tc=""
	if ! ip route show table "$RT_TABLE_CAPTURE" 2>/dev/null | grep -q '^unreachable default'; then
		ip route replace unreachable default metric 4294967295 table "$RT_TABLE_CAPTURE" 2>/dev/null
		_tc=1
	fi
	if [ "$1" = true ]; then
		if ! ip route show table "$RT_TABLE_CAPTURE" 2>/dev/null | grep -q "^default dev $RT_TUN"; then
			ip route replace default dev "$RT_TUN" table "$RT_TABLE_CAPTURE" 2>/dev/null
			_tc=1
		fi
		if ! ip route show table "$RT_TABLE_GAME" 2>/dev/null | grep -q "^$RT_FAKE_RANGE dev $RT_TUN"; then
			ip route replace "$RT_FAKE_RANGE" dev "$RT_TUN" table "$RT_TABLE_GAME" 2>/dev/null
			_tc=1
		fi
	fi
	[ -z "$_tc" ] || echo changed
}

rt6_current_marks() {
	ip -6 rule show 2>/dev/null | awk '$1 == "99:" && /prohibit/ { for (i = 2; i <= NF; i++) if ($i == "fwmark") print $(i + 1) }'
}

rt6_flush() {
	rt6_current_marks | while read -r _m6; do
		ip -6 rule del pref 99 fwmark "$_m6" prohibit 2>/dev/null
	done
}

# IPv6 для меченого трафика запрещён: устройства политики переходят на IPv4 (спека §5.5)
# $1 - метка, $2 - блокировать ли (true/false)
rt6_apply() {
	_h6="$(rt6_current_marks)"
	if [ "$2" = true ]; then
		[ "$_h6" != "$1" ] || return 0
		rt6_flush
		ip -6 rule add pref 99 fwmark "$1" prohibit 2>/dev/null
		echo changed
	elif [ -n "$_h6" ]; then
		rt6_flush
		echo changed
	fi
}

# loose rp_filter на TUN: ответы из ядра не отбрасываются как «марсианские»
rt_rpfilter() {
	_rpf="$GRKA_PROC/sys/net/ipv4/conf/$RT_TUN/rp_filter"
	[ -w "$_rpf" ] || return 0
	[ "$(cat "$_rpf" 2>/dev/null)" = 2 ] || echo 2 > "$_rpf"
}

rt_clear() {
	rt_rules_flush
	rt6_flush
	ip route flush table "$RT_TABLE_CAPTURE" 2>/dev/null
	ip route flush table "$RT_TABLE_GAME" 2>/dev/null
}
