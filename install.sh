#!/bin/sh
# GrKa Keen - установщик (Keenetic + Entware)
# Использование: sh -c "$(wget -qO- https://raw.githubusercontent.com/Soporif1c/GrKa-Keen/main/install.sh)"

REPO="Soporif1c/GrKa-Keen"
TMP_TAR="/opt/tmp/grka-keen.tar.gz"

PATH="/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GREEN=$'\033[1;32m'
RED=$'\033[1;31m'
CYAN=$'\033[1;96m'
NC=$'\033[0m'

fail() {
	printf "%s ОШИБКА:%s %s\n" "$RED" "$NC" "$1" >&2
	exit 1
}

fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -sfL --connect-timeout 10 --retry 2 "$1"
	else
		wget -qO- "$1"
	fi
}

download() {
	if command -v curl >/dev/null 2>&1; then
		curl -fL --connect-timeout 10 --retry 2 -o "$2" "$1"
	else
		wget -qO "$2" "$1"
	fi
}

printf "\n%s=== GrKa Keen — установка ===%s\n\n" "$CYAN" "$NC"

[ -x /opt/bin/opkg ] || fail "Entware не найден (/opt/bin/opkg). GrKa Keen работает поверх Entware на Keenetic. Установите Entware: https://help.keenetic.com/hc/ru/articles/360021214160"

printf "Установка зависимостей (lighttpd, jq, curl, iptables, ip-full)...\n"
/opt/bin/opkg update >/dev/null 2>&1
/opt/bin/opkg install lighttpd lighttpd-mod-cgi jq curl iptables ip-full >/dev/null 2>&1 || \
	printf "%sПредупреждение:%s не все пакеты установились — проверьте opkg вручную\n" "$RED" "$NC"
command -v jq >/dev/null 2>&1 || fail "jq не установлен (opkg install jq)"
command -v lighttpd >/dev/null 2>&1 || fail "lighttpd не установлен (opkg install lighttpd lighttpd-mod-cgi)"

# Отдельный экземпляр lighttpd для панели поднимает S99grka-keen со своим конфигом.
# Глобальный S80lighttpd из пакета не нужен — выключаем его автозапуск, если он появился только что.
if [ -f /opt/etc/init.d/S80lighttpd ] && [ ! -f /opt/etc/lighttpd/.grka-keep ]; then
	sed -i 's/^ENABLED=yes/ENABLED=no/' /opt/etc/init.d/S80lighttpd 2>/dev/null
fi

mkdir -p /opt/tmp

TAG="${1:-}"
if [ -z "$TAG" ]; then
	printf "Получение последней версии...\n"
	TAG="$(fetch "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
	[ -n "$TAG" ] || fail "не удалось получить версию с GitHub API"
fi
VER="${TAG#v}"

printf "Загрузка GrKa Keen %s...\n" "$VER"
download "https://github.com/$REPO/releases/download/$TAG/grka-keen-$VER.tar.gz" "$TMP_TAR" || fail "не удалось скачать релиз"

printf "Установка файлов...\n"
tar -C / -xzf "$TMP_TAR" || fail "не удалось распаковать архив"
rm -f "$TMP_TAR"
chmod +x /opt/share/grka/scripts/*.sh /opt/share/grka/www/cgi-bin/api \
	/opt/etc/init.d/S97mihomo /opt/etc/init.d/S99grka-keen \
	/opt/etc/ndm/netfilter.d/50-grka.sh /opt/etc/ndm/ifstatechanged.d/50-grka.sh

mkdir -p /opt/etc/mihomo/backups /opt/var/log/grka /opt/var/run
if [ ! -f /opt/etc/mihomo/config.yaml ]; then
	cp /opt/share/grka/config.yaml.default /opt/etc/mihomo/config.yaml
	printf "Создана конфигурация по умолчанию: /opt/etc/mihomo/config.yaml\n"
fi

if [ ! -f /opt/etc/grka/grka.conf ]; then
	printf "# GrKa Keen - настройки\nPOLICY_NAME='GrKa'\n" > /opt/etc/grka/grka.conf
fi

if [ ! -x /opt/sbin/mihomo ] && [ ! -f /opt/share/grka/mihomo.gz ]; then
	printf "\nУстановка ядра mihomo с официального репозитория...\n"
	sh /opt/share/grka/scripts/core-update.sh || printf "%s Не удалось установить ядро автоматически — установите его через панель (вкладка «Статус»).%s\n" "$RED" "$NC"
fi

printf "Запуск веб-панели...\n"
/opt/etc/init.d/S99grka-keen restart >/dev/null 2>&1

[ -e /dev/net/tun ] || printf "\n%sВНИМАНИЕ:%s /dev/net/tun не найден. Установите компонент системы «OpenVPN» в веб-интерфейсе Keenetic (Управление -> Параметры системы -> Обновления и компоненты) — он добавляет поддержку TUN, затем перезагрузите роутер.\n" "$RED" "$NC"

IP_HINT="$(ip -4 addr show br0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n1)"
[ -n "$IP_HINT" ] || IP_HINT="<IP роутера>"

printf "\n%s✔ Готово!%s Панель: %shttp://%s:1100%s\n" "$GREEN" "$NC" "$CYAN" "$IP_HINT" "$NC"
printf "  1. В веб-интерфейсе Keenetic создайте политику доступа «GrKa» (подключения ей не назначайте)\n"
printf "     и добавьте в неё клиентов: Приоритеты подключений -> Применение политик\n"
printf "  2. В панели: «Конфигурация» -> добавьте прокси из ссылки -> «Сохранить и перезапустить»\n"
printf "  3. «Статус» -> проверьте, что сервис запущен и маршрутизация политики активна\n\n"
