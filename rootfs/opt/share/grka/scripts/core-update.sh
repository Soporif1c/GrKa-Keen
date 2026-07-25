#!/bin/sh
# GrKa Keen - установка/обновление ядра mihomo с официального репозитория MetaCubeX/mihomo

. /opt/share/grka/scripts/common.sh

LOCK="/tmp/grka-task.lock"
TMP_GZ="/opt/tmp/grka-mihomo.gz"
TMP_BIN="/opt/tmp/grka-mihomo"

cleanup() {
	rm -f "$LOCK" "$TMP_GZ" "$TMP_BIN"
}
trap cleanup EXIT
echo $$ > "$LOCK"

mkdir -p /opt/tmp

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

WAS_RUNNING="$(pidof mihomo 2>/dev/null || true)"
[ -n "$WAS_RUNNING" ] && { echo "Остановка mihomo..."; /opt/etc/init.d/S97mihomo stop; }

if compact_on; then
	echo "Компактный режим: ядро сохраняется сжатым ($CORE_GZ)"
	cp "$TMP_GZ" "$CORE_GZ"
	mkdir -p /tmp/grka
	mv "$TMP_BIN" "$CORE_TMP"
	chmod +x "$CORE_TMP"
	rm -f "$CORE_BIN"
else
	mv "$TMP_BIN" "$CORE_BIN"
	chmod +x "$CORE_BIN"
	rm -f "$CORE_GZ" "$CORE_TMP"
fi

[ -n "$WAS_RUNNING" ] && { echo "Запуск mihomo..."; /opt/etc/init.d/S97mihomo start force; }

echo ""
echo "Готово: установлено ядро mihomo $VERSION ($ARCH)"
