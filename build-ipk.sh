#!/bin/sh
# Сборка opkg-пакета grka-keen_<version>_all.ipk из rootfs/
# Формат ipk (Entware/OpenWRT): tar.gz с файлами debian-binary, control.tar.gz, data.tar.gz
set -e

cd "$(dirname "$0")"
VERSION="$(tr -d ' \r\n' < rootfs/opt/share/grka/version)"
OUT="grka-keen_${VERSION}_all.ipk"
STAGE=".ipk-stage"

# Проверка: в файлах не должно быть CRLF (иначе shell-скрипты сломаются на роутере)
if grep -rl "$(printf '\r')" rootfs/ 2>/dev/null; then
	echo "ОШИБКА: найдены файлы с CRLF (список выше). Исправьте окончания строк на LF." >&2
	exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE/control"

printf '2.0\n' > "$STAGE/debian-binary"

cat > "$STAGE/control/control" <<EOF
Package: grka-keen
Version: $VERSION
Architecture: all
Maintainer: Soporif1c
Section: net
Priority: optional
Depends: lighttpd, lighttpd-mod-cgi, jq, curl, iptables, ip-full
Description: Панель управления mihomo для Keenetic. Вебморда на порту 1100,
 трафик заворачивается только для клиентов политики доступа Keenetic «GrKa».
 https://github.com/Soporif1c/GrKa-Keen
EOF

# Файлы, которые opkg не должен перезаписывать при обновлении (настройки/состояние)
cat > "$STAGE/control/conffiles" <<'EOF'
/opt/etc/grka/lighttpd.conf
/opt/etc/init.d/S97mihomo
/opt/etc/init.d/S99grka-keen
EOF

cat > "$STAGE/control/postinst" <<'EOF'
#!/bin/sh
chmod +x /opt/share/grka/scripts/*.sh /opt/share/grka/www/cgi-bin/api \
	/opt/etc/init.d/S97mihomo /opt/etc/init.d/S99grka-keen \
	/opt/etc/ndm/netfilter.d/50-grka.sh /opt/etc/ndm/ifstatechanged.d/50-grka.sh 2>/dev/null

mkdir -p /opt/etc/mihomo/backups /opt/var/log/grka /opt/var/run /opt/tmp

if [ ! -f /opt/etc/mihomo/config.yaml ]; then
	cp /opt/share/grka/config.yaml.default /opt/etc/mihomo/config.yaml
fi
if [ ! -f /opt/etc/grka/grka.conf ]; then
	printf "# GrKa Keen - настройки\nPOLICY_NAME='GrKa'\n" > /opt/etc/grka/grka.conf
fi

# наш lighttpd — отдельный экземпляр; глобальному автозапуск не нужен
if [ -f /opt/etc/init.d/S80lighttpd ]; then
	sed -i 's/^ENABLED=yes/ENABLED=no/' /opt/etc/init.d/S80lighttpd 2>/dev/null
fi

/opt/etc/init.d/S99grka-keen restart >/dev/null 2>&1

IP_HINT="$(ip -4 addr show br0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n1)"
[ -n "$IP_HINT" ] || IP_HINT="<IP роутера>"

echo ""
echo "GrKa Keen установлен. Панель: http://$IP_HINT:1100"
echo "  1. Установите ядро mihomo: вкладка «Статус» -> «Установить ядро»"
echo "     (или: sh /opt/share/grka/scripts/core-update.sh)"
echo "  2. В веб-интерфейсе Keenetic создайте политику доступа «GrKa» и добавьте клиентов"
echo "  3. «Конфигурация» -> добавьте прокси -> «Сохранить и перезапустить»"
[ -e /dev/net/tun ] || echo "ВНИМАНИЕ: /dev/net/tun нет — установите компонент Keenetic «OpenVPN» и перезагрузите роутер"
exit 0
EOF

cat > "$STAGE/control/prerm" <<'EOF'
#!/bin/sh
/opt/etc/init.d/S97mihomo stop >/dev/null 2>&1
/opt/etc/init.d/S99grka-keen stop >/dev/null 2>&1
sh /opt/share/grka/scripts/policy-route.sh clear >/dev/null 2>&1
exit 0
EOF

# control.tar.gz — всё 0755, чтобы postinst/prerm были исполняемыми независимо от ОС сборки
tar -C "$STAGE/control" --owner=0 --group=0 --numeric-owner --mode=0755 -czf "$STAGE/control.tar.gz" .

# data.tar.gz — права выставляет postinst (chmod выше), поэтому обычные режимы
tar -C rootfs --owner=0 --group=0 --numeric-owner -czf "$STAGE/data.tar.gz" ./opt

tar -C "$STAGE" --owner=0 --group=0 --numeric-owner -czf "$OUT" ./debian-binary ./control.tar.gz ./data.tar.gz

rm -rf "$STAGE"
echo "Собрано: $OUT"
tar -tzf "$OUT"
