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

# Канонический IPv4: четыре числа 0–255 без ведущих нулей. Иначе ip rule add не пройдёт или ядро
# напечатает адрес не так, как мы его записали, и правила переставлялись бы на каждом проходе
rt_ipv4_ok() {
	case "$1" in
	"" | *[!0-9.]* | .* | *. | *..*) return 1 ;;
	esac
	_rifs="$IFS"
	IFS=.
	# shellcheck disable=SC2086
	set -- $1
	IFS="$_rifs"
	[ $# -eq 4 ] || return 1
	for _oc in "$@"; do
		case "$_oc" in
		0?*) return 1 ;;
		esac
		[ "${#_oc}" -le 3 ] && [ "$_oc" -le 255 ] || return 1
	done
}

# $1 - метка, $2 - пауза (true/false), $3 - IP игровых устройств через пробел (неверные и повторы пропускаются)
rt_desired_rules() {
	for _rn in $RT_PRIVATE; do
		echo "96|all|$_rn|$1|main"
	done
	if [ "$2" = true ]; then
		echo "99|all|all|$1|main"
		return 0
	fi
	_rips=""
	for _ri in $3; do
		rt_ipv4_ok "$_ri" || continue
		case " $_rips " in *" $_ri "*) continue ;; esac
		_rips="$_rips $_ri"
	done
	for _ri in $_rips; do
		echo "97|$_ri|all|$1|$RT_TABLE_GAME"
	done
	for _ri in $_rips; do
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

# $1 - add|del, $2 - правило "pref|from|to|mark|table"
rt_rule_cmd() {
	_rcl="$2"
	_rcp="${_rcl%%|*}"
	_rcl="${_rcl#*|}"
	_rcf="${_rcl%%|*}"
	_rcl="${_rcl#*|}"
	_rct="${_rcl%%|*}"
	_rcl="${_rcl#*|}"
	_rcm="${_rcl%%|*}"
	_rctb="${_rcl#*|}"
	set -- "$1" pref "$_rcp"
	[ "$_rcf" = all ] || set -- "$@" from "$_rcf"
	[ "$_rct" = all ] || set -- "$@" to "$_rct"
	[ -z "$_rcm" ] || set -- "$@" fwmark "$_rcm"
	set -- "$@" lookup "$_rctb"
	ip rule "$@" 2>/dev/null
}

rt_rules_flush() {
	rt_current_rules | while IFS= read -r _l; do
		[ -z "$_l" ] || rt_rule_cmd del "$_l"
	done
}

# Приводит правила к желаемым. Сначала добавляет недостающие, потом удаляет лишние и повторы:
# при смене метки или паузе правило 99 не пропадает ни на миг
rt_rules_apply() {
	_want="$(rt_desired_rules "$1" "$2" "$3" | sort -u)"
	_have="$(rt_current_rules | sort)"
	[ "$_want" != "$_have" ] || return 0
	printf '%s\n' "$_want" | while IFS= read -r _l; do
		[ -n "$_l" ] || continue
		printf '%s\n' "$_have" | grep -qxF -- "$_l" || rt_rule_cmd add "$_l"
	done
	printf '%s\n' "$_have" | uniq -c | while read -r _cnt _l; do
		[ -n "$_l" ] || continue
		_keep=0
		if printf '%s\n' "$_want" | grep -qxF -- "$_l"; then _keep=1; fi
		_extra=$((_cnt - _keep))
		while [ "$_extra" -gt 0 ]; do
			rt_rule_cmd del "$_l"
			_extra=$((_extra - 1))
		done
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
