# shellcheck shell=sh
# DNS игровых устройств -> DNS ядра (спека §5.3). Обычные устройства не трогаем: их DNS идёт через DoT/DoH роутера.
# Цепочка nat GRKA_DNS: по два правила (udp и tcp) на IP; один переход из PREROUTING, первым.

DNS_CHAIN="GRKA_DNS"

ipt() {
	iptables -w "$@"
}

# $1 - IP через пробел, $2 - порт DNS ядра
dns_desired_lines() {
	for _di in $1; do
		printf '%s\n' "-A $DNS_CHAIN -s $_di/32 -p udp --dport 53 -j REDIRECT --to-ports $2"
		printf '%s\n' "-A $DNS_CHAIN -s $_di/32 -p tcp --dport 53 -j REDIRECT --to-ports $2"
	done
}

# Текущие правила цепочки; настоящий iptables -S добавляет "-m udp"/"-m tcp", их убираем
dns_current_lines() {
	ipt -t nat -S "$DNS_CHAIN" 2>/dev/null | grep -- '^-A ' | sed 's/ -m udp//; s/ -m tcp//'
}

# Убирает все переходы в GRKA_DNS из PREROUTING (включая старый вариант 0.0.2 с -m mark)
dns_unjump() {
	ipt -t nat -S PREROUTING 2>/dev/null | grep -- "-j $DNS_CHAIN\$" | sed 's/^-A PREROUTING //' | while read -r _dr; do
		# shellcheck disable=SC2086
		ipt -t nat -D PREROUTING $_dr 2>/dev/null
	done
}

dns_clear() {
	_dhad="$(ipt -t nat -S "$DNS_CHAIN" 2>/dev/null)$(ipt -t nat -S PREROUTING 2>/dev/null | grep -- "-j $DNS_CHAIN\$")"
	dns_unjump
	ipt -t nat -F "$DNS_CHAIN" 2>/dev/null
	ipt -t nat -X "$DNS_CHAIN" 2>/dev/null
	[ -z "$_dhad" ] || echo changed
}

# $1 - IP через пробел (пусто — снять перенаправление), $2 - порт DNS ядра
dns_apply() {
	_dips="$(for _di in $1; do echo "$_di"; done | sort -u | tr '\n' ' ')"
	if [ -z "$_dips" ]; then
		dns_clear
		return 0
	fi
	_dch=""
	ipt -t nat -N "$DNS_CHAIN" 2>/dev/null
	if [ "$(dns_desired_lines "$_dips" "$2" | sort)" != "$(dns_current_lines | sort)" ]; then
		ipt -t nat -F "$DNS_CHAIN"
		dns_desired_lines "$_dips" "$2" | sed "s/^-A $DNS_CHAIN //" | while read -r _dr; do
			# shellcheck disable=SC2086
			ipt -t nat -A "$DNS_CHAIN" $_dr
		done
		_dch=1
	fi
	_djumps="$(ipt -t nat -S PREROUTING 2>/dev/null | grep -c -- "-j $DNS_CHAIN\$")"
	if [ "$_djumps" -ne 1 ] || ! ipt -t nat -C PREROUTING -j "$DNS_CHAIN" 2>/dev/null; then
		dns_unjump
		ipt -t nat -I PREROUTING 1 -j "$DNS_CHAIN"
		_dch=1
	fi
	[ -z "$_dch" ] || echo changed
}
