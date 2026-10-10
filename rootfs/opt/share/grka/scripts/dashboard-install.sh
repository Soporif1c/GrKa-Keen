#!/bin/sh
# GrKa Keen - установка веб-дашборда MetaCubeXD (Clash API UI) в /opt/etc/mihomo/ui
GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"

TMP_TGZ="$GRKA_TMPDIR/grka-ui.tgz"
UI_DIR="$MIHOMO_DIR/ui"

cleanup() {
	rm -f "$TASK_LOCK" "$TMP_TGZ"
}
trap cleanup EXIT
mkdir -p "$GRKA_RUN" "$GRKA_TMPDIR"
echo $$ > "$TASK_LOCK"

echo "Загрузка дашборда MetaCubeXD..."
download "$DASHBOARD_URL" "$TMP_TGZ" || { echo "ОШИБКА: не удалось скачать дашборд"; exit 1; }

echo "Установка в $UI_DIR..."
rm -rf "$UI_DIR"
mkdir -p "$UI_DIR"
tar -C "$UI_DIR" -xzf "$TMP_TGZ" || { echo "ОШИБКА: не удалось распаковать архив"; exit 1; }

# Если архив содержит вложенную папку (dist/ и т.п.) — поднимаем содержимое на уровень выше
if [ ! -f "$UI_DIR/index.html" ]; then
	SUB="$(find "$UI_DIR" -mindepth 2 -maxdepth 2 -name index.html 2>/dev/null | head -n1)"
	if [ -n "$SUB" ]; then
		SUBDIR="$(dirname "$SUB")"
		mv "$SUBDIR"/* "$UI_DIR"/ 2>/dev/null
		rmdir "$SUBDIR" 2>/dev/null
	fi
fi

[ -f "$UI_DIR/index.html" ] || { echo "ОШИБКА: index.html не найден после распаковки"; exit 1; }

echo ""
echo "Готово: дашборд установлен."
echo "Он будет доступен по адресу http://<роутер>:9090/ui после (пере)запуска ядра,"
echo "если в конфиге указано: external-controller: 0.0.0.0:9090 и external-ui: ui"
