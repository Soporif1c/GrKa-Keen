#!/bin/sh
# GrKa Keen - компактный режим хранения ядра
# on:  ядро хранится сжатым в /opt (~12 МБ вместо ~35), при старте распаковывается в /tmp (RAM)
# off: ядро хранится обычным бинарником
GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"
. "$GRKA_SHARE/lib/settings.sh"
. "$GRKA_SHARE/lib/core.sh"

cleanup() {
	rm -f "$TASK_LOCK"
}
trap cleanup EXIT
mkdir -p "$GRKA_RUN"
echo $$ > "$TASK_LOCK"

case "${1:-}" in
on)
	if compact_on; then
		echo "Компактный режим уже включён"
		exit 0
	fi
	if [ -x "$MIHOMO_BIN" ]; then
		echo "Сжатие ядра (может занять до минуты)..."
		mkdir -p "$(dirname "$MIHOMO_TMP")" "$MIHOMO_DIR"
		gzip -c "$MIHOMO_BIN" > "$MIHOMO_GZ" || { rm -f "$MIHOMO_GZ"; echo "ОШИБКА: не удалось сжать ядро"; exit 1; }
		cp "$MIHOMO_BIN" "$MIHOMO_TMP"
		chmod +x "$MIHOMO_TMP"
		rm -f "$MIHOMO_BIN"
	fi
	: > "$COMPACT_FLAG"
	flag_set restart-core
	flag_set dirty
	echo ""
	echo "Готово: компактный режим включён."
	echo "Ядро хранится в $MIHOMO_GZ и распаковывается в RAM при старте (~35 МБ RAM)."
	;;
off)
	if ! compact_on; then
		echo "Компактный режим уже выключен"
		exit 0
	fi
	if [ ! -x "$MIHOMO_BIN" ]; then
		_src="$(ensure_core)"
		[ -n "$_src" ] || { echo "ОШИБКА: ядро не найдено"; exit 1; }
		echo "Распаковка ядра в $MIHOMO_BIN..."
		cp "$_src" "$MIHOMO_BIN" || { echo "ОШИБКА: не удалось записать $MIHOMO_BIN (мало места в /opt?)"; exit 1; }
		chmod +x "$MIHOMO_BIN"
	fi
	rm -f "$COMPACT_FLAG" "$MIHOMO_GZ" "$MIHOMO_TMP"
	flag_set restart-core
	flag_set dirty
	echo ""
	echo "Готово: компактный режим выключен, ядро в $MIHOMO_BIN."
	;;
*)
	echo "ОШИБКА: неизвестный режим «${1:-}» (ожидается on или off)"
	exit 1
	;;
esac
