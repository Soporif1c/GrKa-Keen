#!/bin/sh
# GrKa Keen - заворачивание трафика клиентов политики Keenetic в TUN mihomo.
#
# Как это работает:
#   1. В веб-интерфейсе Keenetic создаётся политика доступа (по умолчанию "GrKa"),
#      в неё добавляются клиенты. Подключения политике не назначаются — тогда без
#      запущенного mihomo у клиентов политики не будет интернета (нет утечек).
#   2. NDM маркирует трафик клиентов политики своим fwmark (виден в show ip policy).
#   3. Мы добавляем: ip rule fwmark <mark> -> таблица 1001 (pref 99 — раньше правил
#      самих политик, у которых pref 100-107) и маршрут default dev <tun> в этой
#      таблице. Весь трафик клиентов политики уходит в TUN mihomo, остальные
#      клиенты роутера не затрагиваются.
#   4. DNS клиентов политики (запросы на порт 53, в т.ч. к самому роутеру)
#      перенаправляются в DNS mihomo (порт 1053) правилом iptables по той же марке.
#
# Использование: policy-route.sh apply | apply-wait | clear | status | clients

PATH="/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GRKA_CONF="/opt/etc/grka/grka.conf"
CONFIG_FILE="/opt/etc/mihomo/config.yaml"

# Значения по умолчанию (переопределяются в /opt/etc/grka/grka.conf)
POLICY_NAME="GrKa"
GRKA_TABLE=1001
GRKA_PREF=99
GRKA_DNS_PORT=1053

[ -f "$GRKA_CONF" ] && . "$GRKA_CONF"

rci() {
	curl -s --connect-timeout 2 "http://127.0.0.1:79/rci/$1" 2>/dev/null
}

# TUN-устройство из конфига mihomo (tun.device), по умолчанию Meta
tun_device() {
	local d=""
	[ -f "$CONFIG_FILE" ] && d="$(awk '/^[[:space:]]*device:/ { v=$2; gsub(/["'\'']/,"",v); print v; exit }' "$CONFIG_FILE")"
	echo "${d:-Meta}"
}

tun_up() {
	# mihomo сам поднимает свой TUN — достаточно проверить, что интерфейс существует
	ip link show "$(tun_device)" >/dev/null 2>&1
}

# fwmark политики с описанием $POLICY_NAME из NDM (нормализованный вид 0x...)
policy_mark() {
	local m
	m="$(rci show/ip/policy | jq -r --arg n "$POLICY_NAME" \
		'to_entries[] | select((.value.description // "") == $n) | .value.mark' 2>/dev/null | head -n1)"
	case "$m" in
	"" | null)
		return 1
		;;
	0x* | 0X*)
		printf '0x%x\n' "$((m))" 2>/dev/null || return 1
		;;
	*[!0-9]*)
		# голый hex без префикса
		printf '0x%x\n' "$((0x$m))" 2>/dev/null || return 1
		;;
	*)
		printf '0x%x\n' "$m" 2>/dev/null || return 1
		;;
	esac
}

rule_ok() {
	# $1 - mark
	ip rule show 2>/dev/null | grep -q "fwmark $1 lookup $GRKA_TABLE"
}

route_ok() {
	ip route show table "$GRKA_TABLE" 2>/dev/null | grep -q "^default dev $(tun_device)"
}

dns_apply() {
	# $1 - mark; перенаправление DNS клиентов политики в DNS mihomo (best-effort)
	command -v iptables >/dev/null 2>&1 || return 0
	iptables -t nat -N GRKA_DNS 2>/dev/null
	iptables -t nat -F GRKA_DNS 2>/dev/null
	iptables -t nat -A GRKA_DNS -p udp --dport 53 -j REDIRECT --to-ports "$GRKA_DNS_PORT" 2>/dev/null
	iptables -t nat -A GRKA_DNS -p tcp --dport 53 -j REDIRECT --to-ports "$GRKA_DNS_PORT" 2>/dev/null
	iptables -t nat -C PREROUTING -m mark --mark "$1" -j GRKA_DNS 2>/dev/null ||
		iptables -t nat -I PREROUTING 1 -m mark --mark "$1" -j GRKA_DNS 2>/dev/null
}

dns_clear() {
	command -v iptables >/dev/null 2>&1 || return 0
	while iptables -t nat -D PREROUTING -j GRKA_DNS 2>/dev/null; do :; done
	# на случай, если правило добавлялось с маркой
	iptables -t nat -S PREROUTING 2>/dev/null | grep -- "-j GRKA_DNS" | sed 's/^-A //' | while read -r r; do
		# shellcheck disable=SC2086
		iptables -t nat -D $r 2>/dev/null
	done
	iptables -t nat -F GRKA_DNS 2>/dev/null
	iptables -t nat -X GRKA_DNS 2>/dev/null
}

apply() {
	local MARK DEV
	MARK="$(policy_mark)" || {
		echo "Политика «$POLICY_NAME» не найдена в Keenetic."
		echo "Создайте её: веб-интерфейс Keenetic -> Приоритеты подключений -> Политики доступа в интернет,"
		echo "имя политики: $POLICY_NAME, затем добавьте в неё клиентов (Применение политик)."
		return 1
	}
	DEV="$(tun_device)"
	if ! tun_up; then
		echo "TUN-интерфейс $DEV не найден или не поднят (mihomo не запущен?)"
		return 1
	fi
	rule_ok "$MARK" || ip rule add fwmark "$MARK" table "$GRKA_TABLE" pref "$GRKA_PREF" 2>/dev/null
	ip route replace default dev "$DEV" table "$GRKA_TABLE" || {
		echo "Не удалось добавить маршрут default dev $DEV table $GRKA_TABLE"
		return 1
	}
	dns_apply "$MARK"
	echo "Маршрутизация применена: политика «$POLICY_NAME» (fwmark $MARK) -> $DEV (таблица $GRKA_TABLE)"
}

# apply с ожиданием появления TUN-интерфейса (используется после старта mihomo)
apply_wait() {
	local i=0
	while [ $i -lt 30 ]; do
		if tun_up; then
			apply
			return $?
		fi
		i=$((i + 1))
		sleep 1
	done
	echo "TUN-интерфейс $(tun_device) не появился за 30 секунд — маршрутизация политики не применена"
	return 1
}

clear_all() {
	while ip rule del table "$GRKA_TABLE" 2>/dev/null; do :; done
	ip route flush table "$GRKA_TABLE" 2>/dev/null
	dns_clear
	echo "Маршрутизация политики очищена"
}

status() {
	local MARK="" FOUND=0 RULE=0 ROUTE=0 TUN_UP=0
	if MARK="$(policy_mark)"; then
		FOUND=1
		rule_ok "$MARK" && RULE=1
		route_ok && ROUTE=1
	fi
	tun_up && TUN_UP=1
	# вывод пригоден для eval в CGI-бэкенде
	echo "P_NAME='$(printf '%s' "$POLICY_NAME" | tr -d "'")'"
	echo "P_FOUND=$FOUND"
	echo "P_MARK='$MARK'"
	echo "P_TABLE='$GRKA_TABLE'"
	echo "P_RULE=$RULE"
	echo "P_ROUTE=$ROUTE"
	echo "P_TUN='$(tun_device | tr -d "'")'"
	echo "P_TUN_UP=$TUN_UP"
}

# Имена клиентов, привязанных к политике (по данным ip hotspot), по одному в строке
clients() {
	local pid
	pid="$(rci show/ip/policy | jq -r --arg n "$POLICY_NAME" \
		'to_entries[] | select((.value.description // "") == $n) | .key' 2>/dev/null | head -n1)"
	[ -n "$pid" ] || return 0
	rci show/ip/hotspot | jq -r --arg p "$pid" \
		'(.host // [])[] | select((.policy // "") == $p) | (.name // .hostname // .mac // empty)' 2>/dev/null
}

case "$1" in
apply) apply ;;
apply-wait) apply_wait ;;
clear) clear_all ;;
status) status ;;
clients) clients ;;
*)
	echo "Использование: $0 apply | apply-wait | clear | status | clients"
	exit 1
	;;
esac
