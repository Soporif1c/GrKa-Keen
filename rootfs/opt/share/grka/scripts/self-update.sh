#!/bin/sh
# GrKa Keen - самообновление панели с GitHub-релизов

# Обновление перезапишет этот файл, поэтому работаем из копии в /tmp
if [ "${GRKA_SELFUPDATE_COPY:-}" != 1 ]; then
	cp "$0" /tmp/grka-self-update-run.sh
	export GRKA_SELFUPDATE_COPY=1
	exec sh /tmp/grka-self-update-run.sh "$@"
fi

GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"

TMP_TAR="/opt/tmp/grka-panel.tar.gz"

cleanup() {
	rm -f "$TASK_LOCK" "$TMP_TAR" /tmp/grka-self-update-run.sh
}
trap cleanup EXIT
mkdir -p "$GRKA_RUN" /opt/tmp
echo $$ > "$TASK_LOCK"

echo "Проверка последней версии GrKa Keen..."
TAG="$(latest_tag "$GRKA_REPO")"
[ -n "$TAG" ] || { echo "ОШИБКА: не удалось получить версию с GitHub API"; exit 1; }

CUR="$(cat "$GRKA_SHARE/version" 2>/dev/null)"
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
chmod +x "$GRKA_SHARE"/bin/* "$GRKA_SHARE"/scripts/*.sh "$GRKA_SHARE/www/cgi-bin/api" \
	/opt/etc/init.d/S99grka-keen /opt/etc/ndm/netfilter.d/50-grka.sh /opt/etc/ndm/ifstatechanged.d/50-grka.sh 2>/dev/null
sh "$GRKA_SHARE/bin/grka" migrate

echo "Перезапуск веб-панели (ядро продолжает работать)..."
/opt/etc/init.d/S99grka-keen restart >/dev/null 2>&1

echo ""
echo "Готово: панель обновлена до версии $VER."
echo "Обновите страницу в браузере (Ctrl+F5)."
