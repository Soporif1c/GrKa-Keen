# shellcheck shell=sh
# Настройки панели (settings.json) и выбор пользователя (state.json).
# Запись атомарная и под блокировкой "config": CGI, CLI и сторож могут писать одновременно.

SETTINGS_DEFAULTS='{"schema":1,"policy_name":"GrKa","rci_token":"","panel_port":1100,"autostart":true,"core":"mihomo","expert":{"mihomo":"","xray":""},"log_level":"warning","ipv6_block":true,"dns_port":1053,"allowed_hosts":[]}'
STATE_DEFAULTS='{"schema":1,"enabled":true,"paused":false,"devices":{}}'

# Создаёт файл $1 со значениями по умолчанию $2 или дописывает недостающие ключи. Битый файл -> .broken
json_init() {
	if [ -s "$1" ] && jqc -e 'type == "object"' "$1" >/dev/null 2>&1; then
		jqc --argjson d "$2" '$d * .' "$1" | write_atomic "$1"
	else
		[ ! -s "$1" ] || mv -f "$1" "$1.broken"
		printf '%s\n' "$2" | jqc '.' | write_atomic "$1"
	fi
}

settings_init() {
	json_init "$SETTINGS_FILE" "$SETTINGS_DEFAULTS"
}

state_init() {
	json_init "$STATE_FILE" "$STATE_DEFAULTS"
}

# Значение по пути jq $2 из файла $1. false печатается как false, отсутствие — пусто
json_get() {
	jqc -r "($2) | select(. != null)" "$1" 2>/dev/null
}

settings_get() {
	json_get "$SETTINGS_FILE" ".$1"
}

state_get() {
	json_get "$STATE_FILE" ".$1"
}

# $1 - файл, $2 - путь jq (.policy_name), $3 - значение в JSON ("\"строка\"", 10, true)
json_set() {
	lock_acquire config || { sleep 1; lock_acquire config; } || return 1
	jqc --argjson v "$3" "$2 = \$v" "$1" | write_atomic "$1"
	_jr=$?
	lock_release config
	return $_jr
}

settings_set() {
	json_set "$SETTINGS_FILE" ".$1" "$2"
}

state_set() {
	json_set "$STATE_FILE" ".$1" "$2"
}

# Строка -> JSON-строка с экранированием
json_str() {
	jqc -n --arg s "$1" '$s'
}

# Имя политики: от 1 до 64 символов, без управляющих символов
policy_name_valid() {
	[ -n "$1" ] || return 1
	jqc -n -e --arg s "$1" '($s | length) <= 64 and ($s | explode | all(. >= 32 and . != 127))' >/dev/null 2>&1
}

# MAC -> нижний регистр. Неверный MAC -> код 1.
# Проверка через case по всей строке: grep сверял бы каждую строку отдельно и пропустил бы "MAC\nмусор"
mac_normalize() {
	_mn="$(printf '%s' "$1" | tr 'A-F' 'a-f')"
	case "$_mn" in
	[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]) ;;
	*) return 1 ;;
	esac
	printf '%s\n' "$_mn"
}

# Тип устройства. $1 - MAC, $2 - gaming|regular (regular удаляет запись)
# MAC передаётся в jq только через --arg: данные никогда не попадают в текст программы jq
state_set_device() {
	_dm="$(mac_normalize "$1")" || return 1
	case "$2" in
	gaming) _df='.devices[$m] = {type: "gaming"}' ;;
	regular) _df='del(.devices[$m])' ;;
	*) return 1 ;;
	esac
	lock_acquire config || { sleep 1; lock_acquire config; } || return 1
	jqc --arg m "$_dm" "$_df" "$STATE_FILE" | write_atomic "$STATE_FILE"
	_jr=$?
	lock_release config
	return $_jr
}
