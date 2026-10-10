#!/bin/sh
# GrKa Keen - установка/обновление ядра mihomo с официального репозитория MetaCubeX/mihomo
# Ядро перезапускает сторож: скрипт только заменяет бинарник и ставит флаг restart-core
GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"
. "$GRKA_SHARE/lib/settings.sh"
. "$GRKA_SHARE/lib/core.sh"

TMP_GZ="/opt/tmp/grka-mihomo.gz"
TMP_BIN="/opt/tmp/grka-mihomo"

cleanup() {
	rm -f "$TASK_LOCK" "$TMP_GZ" "$TMP_BIN"
}
trap cleanup EXIT
mkdir -p "$GRKA_RUN" /opt/tmp
echo $$ > "$TASK_LOCK"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
	echo "Получение последней версии mihomo с GitHub..."
	VERSION="$(latest_tag "$MIHOMO_REPO")"
	[ -n "$VERSION" ] || { echo "ОШИБКА: не удалось получить версию с GitHub API"; exit 1; }
fi

ARCH="$(mihomo_arch)"
[ -n "$ARCH" ] || { echo "ОШИБКА: не удалось определить архитектуру устройства"; exit 1; }

echo "Версия: $VERSION"
echo "Архитектура: $ARCH"

URL="https://github.com/$MIHOMO_REPO/releases/download/$VERSION/mihomo-linux-$ARCH-$VERSION.gz"
echo "Загрузка: $URL"
download "$URL" "$TMP_GZ" || { echo "ОШИБКА: не удалось скачать ядро"; exit 1; }

echo "Распаковка..."
gunzip -c "$TMP_GZ" > "$TMP_BIN" || { echo "ОШИБКА: не удалось распаковать архив"; exit 1; }
chmod +x "$TMP_BIN"

"$TMP_BIN" -v >/dev/null 2>&1 || {
	echo "ОШИБКА: бинарник не запускается — возможно, неверная архитектура ($ARCH)"
	exit 1
}

# mv заменяет файл, даже если старое ядро ещё работает: процесс держит старый inode
if compact_on; then
	echo "Компактный режим: ядро сохраняется сжатым ($MIHOMO_GZ)"
	cp "$TMP_GZ" "$MIHOMO_GZ"
	mkdir -p "$(dirname "$MIHOMO_TMP")"
	mv -f "$TMP_BIN" "$MIHOMO_TMP"
	chmod +x "$MIHOMO_TMP"
	rm -f "$MIHOMO_BIN"
else
	mv -f "$TMP_BIN" "$MIHOMO_BIN"
	chmod +x "$MIHOMO_BIN"
	rm -f "$MIHOMO_GZ" "$MIHOMO_TMP"
fi

flag_set restart-core
flag_set dirty
echo ""
echo "Готово: установлено ядро mihomo $VERSION ($ARCH). Сторож перезапустит ядро в течение секунды"
