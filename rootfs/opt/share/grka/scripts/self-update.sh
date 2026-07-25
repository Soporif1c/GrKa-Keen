#!/bin/sh
# GrKa Keen - самообновление панели с GitHub-релизов

# Обновление перезапишет этот файл, поэтому перезапускаем себя из /tmp
if [ "${GRKA_SELFUPDATE_COPY:-}" != "1" ]; then
	cp "$0" /tmp/grka-self-update-run.sh
	export GRKA_SELFUPDATE_COPY=1
	exec sh /tmp/grka-self-update-run.sh "$@"
fi

. /opt/share/grka/scripts/common.sh

LOCK="/tmp/grka-task.lock"
TMP_TAR="/opt/tmp/grka-panel.tar.gz"

cleanup() {
	rm -f "$LOCK" "$TMP_TAR" /tmp/grka-self-update-run.sh
}
trap cleanup EXIT
echo $$ > "$LOCK"

mkdir -p /opt/tmp

echo "Проверка последней версии GrKa Keen..."
TAG="$(latest_tag "$GRKA_REPO")"
[ -n "$TAG" ] || { echo "ОШИБКА: не удалось получить версию с GitHub API"; exit 1; }

CUR="$(cat /opt/share/grka/version 2>/dev/null)"
if [ "v$CUR" = "$TAG" ]; then
	echo "Уже установлена последняя версия ($CUR)"
	exit 0
fi

VER="${TAG#v}"
URL="https://github.com/$GRKA_REPO/releases/download/$TAG/grka-keen-$VER.tar.gz"
echo "Загрузка: $URL"
download "$URL" "$TMP_TAR" || { echo "ОШИБКА: не удалось скачать релиз"; exit 1; }

echo "Установка..."
tar -C / -xzf "$TMP_TAR" || { echo "ОШИБКА: не удалось распаковать архив"; exit 1; }
chmod +x /opt/share/grka/scripts/*.sh /opt/share/grka/www/cgi-bin/api \
	/opt/etc/init.d/S97mihomo /opt/etc/init.d/S99grka-keen \
	/opt/etc/ndm/netfilter.d/50-grka.sh /opt/etc/ndm/ifstatechanged.d/50-grka.sh 2>/dev/null

echo "Перезапуск веб-панели..."
/opt/etc/init.d/S99grka-keen restart >/dev/null 2>&1

echo ""
echo "Готово: панель обновлена до версии $VER."
echo "Обновите страницу в браузере (Ctrl+F5)."
