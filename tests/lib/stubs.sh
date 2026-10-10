# shellcheck shell=sh
# Заглушки системных команд. Состояние хранится в файлах $STUB, все вызовы пишутся в $STUB/calls.
# Формат вывода повторяет iproute2 4.4 и iptables 1.4: "99:<TAB>from all fwmark 0x1 lookup 1001".

stubs_reset() {
	STUB="$T/stub"
	rm -rf "$STUB"
	mkdir -p "$STUB/links" "$STUB/curl"
	: > "$STUB/calls"
	: > "$STUB/rules4"
	: > "$STUB/rules6"
	echo "PREROUTING INPUT OUTPUT POSTROUTING" > "$STUB/ipt.nat.builtin"
	echo "INPUT FORWARD OUTPUT" > "$STUB/ipt.filter.builtin"
	echo "PREROUTING INPUT FORWARD OUTPUT POSTROUTING" > "$STUB/ipt.mangle.builtin"
	for _sc in PREROUTING INPUT OUTPUT POSTROUTING; do : > "$STUB/ipt.nat.$_sc"; done
	for _sc in INPUT FORWARD OUTPUT; do : > "$STUB/ipt.filter.$_sc"; done
}

# ---------- ip ----------

stub_rule_text() {
	# $1 from, $2 to, $3 mark, $4 table, $5 действие (prohibit и т.п.)
	_st="from $1"
	[ -z "$2" ] || _st="$_st to $2"
	[ -z "$3" ] || _st="$_st fwmark $3"
	if [ -n "$5" ]; then _st="$_st $5"; else _st="$_st lookup $4"; fi
	printf '%s' "$_st"
}

ip() {
	echo "ip $*" >> "$STUB/calls"
	_fam=4
	if [ "$1" = "-6" ]; then
		_fam=6
		shift
	fi
	_obj="$1"
	shift
	case "$_obj" in
	rule) stub_ip_rule "$_fam" "$@" ;;
	route) stub_ip_route "$@" ;;
	link)
		if [ "$1" = show ] && [ -e "$STUB/links/$2" ]; then
			echo "7: $2: <POINTOPOINT,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN"
			return 0
		fi
		return 1
		;;
	*) return 1 ;;
	esac
}

stub_ip_rule() {
	_rf="$STUB/rules$1"
	shift
	_cmd="${1:-show}"
	[ $# -gt 0 ] && shift
	_from=all _to="" _mark="" _table="" _pref="" _act=""
	while [ $# -gt 0 ]; do
		case "$1" in
		from) _from="$2"; shift ;;
		to) _to="$2"; shift ;;
		fwmark) _mark="$2"; shift ;;
		lookup | table) _table="$2"; shift ;;
		pref | priority) _pref="$2"; shift ;;
		prohibit | unreachable | blackhole) _act="$1" ;;
		esac
		shift
	done
	case "$_cmd" in
	show | list)
		sort -s -n -k1,1 "$_rf" | awk -F '\t' '{ print $1 ":\t" $2 }'
		;;
	add)
		printf '%s\t%s\n' "${_pref:-32000}" "$(stub_rule_text "$_from" "$_to" "$_mark" "$_table" "$_act")" >> "$_rf"
		;;
	del)
		_full=""
		[ -z "$_table$_act" ] || _full="$(stub_rule_text "$_from" "$_to" "$_mark" "$_table" "$_act")"
		awk -F '\t' -v p="$_pref" -v w="$_full" '
			!done && (p == "" || $1 == p) && (w == "" || $2 == w) { done = 1; next }
			{ print }
			END { exit(done ? 0 : 1) }' "$_rf" > "$_rf.n"
		_dr=$?
		mv -f "$_rf.n" "$_rf"
		[ $_dr -eq 0 ] || return 2
		;;
	esac
}

stub_ip_route() {
	_cmd="$1"
	shift
	_type="" _dst="" _dev="" _metric="" _table="main"
	while [ $# -gt 0 ]; do
		case "$1" in
		unreachable | blackhole | prohibit | throw) _type="$1" ;;
		dev) _dev="$2"; shift ;;
		metric) _metric="$2"; shift ;;
		table) _table="$2"; shift ;;
		*) [ -n "$_dst" ] || _dst="$1" ;;
		esac
		shift
	done
	_rtf="$STUB/route.$_table"
	touch "$_rtf"
	case "$_cmd" in
	show) cat "$_rtf" ;;
	flush) : > "$_rtf" ;;
	replace | add)
		if [ -n "$_type" ]; then
			_line="$_type $_dst"
		else
			[ -e "$STUB/links/$_dev" ] || return 2
			_line="$_dst dev $_dev scope link"
		fi
		[ -z "$_metric" ] || _line="$_line metric $_metric"
		awk -v k="$_dst|${_metric:-0}" '{
			d = ($1 ~ /^(unreachable|blackhole|prohibit|throw)$/) ? $2 : $1
			m = 0
			for (i = 1; i <= NF; i++) if ($i == "metric") m = $(i + 1)
			if (d "|" m != k) print
		}' "$_rtf" > "$_rtf.n"
		echo "$_line" >> "$_rtf.n"
		mv -f "$_rtf.n" "$_rtf"
		;;
	esac
}

stub_link_up() {
	: > "$STUB/links/$1"
}

# Как в ядре: при удалении интерфейса пропадают все маршруты через него
stub_link_down() {
	rm -f "$STUB/links/$1"
	for _lf in "$STUB"/route.*; do
		[ -f "$_lf" ] || continue
		grep -v " dev $1 " "$_lf" > "$_lf.n"
		mv -f "$_lf.n" "$_lf"
	done
}

# ---------- iptables ----------

iptables() {
	echo "iptables $*" >> "$STUB/calls"
	_it=filter
	while [ $# -gt 0 ]; do
		case "$1" in
		-w) shift ;;
		-t) _it="$2"; shift 2 ;;
		*) break ;;
		esac
	done
	_op="$1"
	_ch="${2:-}"
	shift
	[ $# -gt 0 ] && shift
	_if="$STUB/ipt.$_it.$_ch"
	case "$_op" in
	-N)
		[ ! -e "$_if" ] || return 1
		: > "$_if"
		;;
	-F)
		[ -e "$_if" ] || return 1
		: > "$_if"
		;;
	-X)
		[ -e "$_if" ] || return 1
		grep -qw -- "$_ch" "$STUB/ipt.$_it.builtin" && return 1
		rm -f "$_if"
		;;
	-A)
		[ -e "$_if" ] || return 1
		echo "-A $_ch $*" >> "$_if"
		;;
	-I)
		[ -e "$_if" ] || return 1
		_pos=1
		case "${1:-}" in [0-9]*) _pos="$1"; shift ;; esac
		awk -v p="$_pos" -v l="-A $_ch $*" 'NR == p { print l; ins = 1 } { print } END { if (!ins) print l }' "$_if" > "$_if.n"
		mv -f "$_if.n" "$_if"
		;;
	-D)
		[ -e "$_if" ] || return 1
		grep -qxF -- "-A $_ch $*" "$_if" || return 1
		awk -v l="-A $_ch $*" '!d && $0 == l { d = 1; next } { print }' "$_if" > "$_if.n"
		mv -f "$_if.n" "$_if"
		;;
	-C)
		[ -e "$_if" ] || return 1
		grep -qxF -- "-A $_ch $*" "$_if"
		;;
	-S)
		[ -e "$_if" ] || return 1
		if grep -qw -- "$_ch" "$STUB/ipt.$_it.builtin"; then echo "-P $_ch ACCEPT"; else echo "-N $_ch"; fi
		cat "$_if"
		;;
	*) return 1 ;;
	esac
}

# ---------- curl ----------
# Ответ задаётся по пути URL после хоста: rci/show/ip/policy -> $STUB/curl/rci_show_ip_policy.{code,body,seq}
# .seq — построчно "код [файл_тела]" на каждый вызов; код 000 — нет соединения

stub_curl_key() {
	printf '%s' "$1" | tr '/?&=' '____'
}

curl() {
	echo "curl $*" >> "$STUB/calls"
	_co="" _cw="" _cu=""
	while [ $# -gt 0 ]; do
		case "$1" in
		-o) _co="$2"; shift ;;
		-w) _cw="$2"; shift ;;
		-H | -m | --connect-timeout | -A | --retry) shift ;;
		-*) ;;
		*) _cu="$1" ;;
		esac
		shift
	done
	_ck="$(stub_curl_key "${_cu#*://*/}")"
	_code=000
	_cb="$STUB/curl/$_ck.body"
	if [ -s "$STUB/curl/$_ck.seq" ]; then
		_cl="$(head -n 1 "$STUB/curl/$_ck.seq")"
		sed -i 1d "$STUB/curl/$_ck.seq"
		_code="${_cl%% *}"
		[ "$_cl" = "$_code" ] || _cb="${_cl#* }"
	elif [ -f "$STUB/curl/$_ck.code" ]; then
		_code="$(cat "$STUB/curl/$_ck.code")"
	fi
	if [ "$_code" != 000 ] && [ -f "$_cb" ]; then
		if [ -n "$_co" ]; then cat "$_cb" > "$_co"; else cat "$_cb"; fi
	fi
	[ -z "$_cw" ] || printf '%s' "$_code"
	[ "$_code" != 000 ]
}

stub_rci() {
	# $1 - путь RCI (show/ip/policy), $2 - HTTP-код, $3 - файл тела (необязательно)
	_ck="$(stub_curl_key "rci/$1")"
	echo "$2" > "$STUB/curl/$_ck.code"
	[ -z "${3:-}" ] || cp "$3" "$STUB/curl/$_ck.body"
}

stub_rci_seq() {
	# $1 - путь RCI, дальше по одному аргументу на вызов: "код [файл_тела]"
	_ck="$(stub_curl_key "rci/$1")"
	shift
	printf '%s\n' "$@" > "$STUB/curl/$_ck.seq"
}
