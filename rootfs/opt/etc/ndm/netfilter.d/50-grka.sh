#!/bin/sh
# GrKa Keen - ndm-хук: переприменение правил при перезагрузке таблиц netfilter.
# NDM вызывает скрипт с переменными окружения $type (iptables/ip6tables) и $table.

[ "$type" = "ip6tables" ] && exit 0
[ "$table" = "nat" ] || [ "$table" = "mangle" ] || exit 0

pidof mihomo >/dev/null 2>&1 || exit 0

sh /opt/share/grka/scripts/policy-route.sh apply >/dev/null 2>&1

exit 0
