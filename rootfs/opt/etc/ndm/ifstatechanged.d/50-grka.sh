#!/bin/sh
# GrKa Keen - ndm-хук: переприменение маршрутизации политики при изменении интерфейсов

pidof mihomo >/dev/null 2>&1 || exit 0

sh /opt/share/grka/scripts/policy-route.sh apply >/dev/null 2>&1

exit 0
