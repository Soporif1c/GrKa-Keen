# shellcheck shell=sh
# shellcheck disable=SC2034
# GrKa Keen — общие пути и функции.
# Подключение: . "${GRKA_SHARE:-/opt/share/grka}/lib/common.sh"
# Любой путь можно переопределить переменной окружения (так делают тесты).
# SC2034 выключен: переменные путей используются в других файлах.

[ -n "${GRKA_TEST:-}" ] || PATH="/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
GRKA_ETC="${GRKA_ETC:-/opt/etc/grka}"
GRKA_RUN="${GRKA_RUN:-/tmp/grka}"
GRKA_LOGDIR="${GRKA_LOGDIR:-/opt/var/log/grka}"
GRKA_INITD="${GRKA_INITD:-/opt/etc/init.d}"
GRKA_PROC="${GRKA_PROC:-/proc}"
MIHOMO_DIR="${MIHOMO_DIR:-/opt/etc/mihomo}"

GRKA_REPO="Soporif1c/GrKa-Keen"
MIHOMO_REPO="MetaCubeX/mihomo"
DASHBOARD_URL="https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz"

SETTINGS_FILE="$GRKA_ETC/settings.json"
STATE_FILE="$GRKA_ETC/state.json"
CACHE_DIR="$GRKA_ETC/cache"
JOURNAL_FILE="$GRKA_LOGDIR/journal.log"
STATUS_FILE="$GRKA_RUN/status.json"
HOSTS_FILE="$GRKA_RUN/hosts.json"
DIRTY_FLAG="$GRKA_RUN/dirty"
CORE_LOG="$GRKA_RUN/core.log"
TASK_LOG="$GRKA_RUN/task.log"
TASK_LOCK="$GRKA_RUN/task.lock"

JOURNAL_MAX="${JOURNAL_MAX:-262144}"
CORE_LOG_MAX="${CORE_LOG_MAX:-1048576}"

# jq с флагами из окружения (в тестах на Windows: -b, без CRLF)
jqc() {
	# shellcheck disable=SC2086
	jq ${GRKA_JQ_FLAGS:-} "$@"
}

now_ts() {
	date +%s
}

# Событие в журнал. $1 - info|warn|error, $2 - текст (переводы строк и | заменяются пробелами).
# То же событие чаще раза в минуту не пишется (спека §6.2 п.8): события последней минуты — в $GRKA_RUN/journal.recent.
# Текст передаётся в awk через окружение: -v разобрал бы обратные косые черты
journal() {
	_jt="$(printf '%s' "$2" | tr '\n|' '  ')"
	_jn="$(now_ts)"
	_jr="$GRKA_RUN/journal.recent"
	if [ -f "$_jr" ] && JM="$1 $_jt" awk -v n="$_jn" '
		n - $1 >= 0 && n - $1 < 60 && substr($0, index($0, " ") + 1) == ENVIRON["JM"] { f = 1 }
		END { exit !f }' "$_jr"; then
		return 0
	fi
	mkdir -p "$GRKA_LOGDIR" "$GRKA_RUN"
	{
		[ ! -f "$_jr" ] || awk -v n="$_jn" 'n - $1 >= 0 && n - $1 < 60' "$_jr"
		printf '%s %s %s\n' "$_jn" "$1" "$_jt"
	} > "$_jr.$$" && mv -f "$_jr.$$" "$_jr"
	if [ -f "$JOURNAL_FILE" ] && [ "$(wc -c < "$JOURNAL_FILE")" -gt "$JOURNAL_MAX" ]; then
		mv -f "$JOURNAL_FILE" "$JOURNAL_FILE.old"
	fi
	printf '%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$_jt" >> "$JOURNAL_FILE"
}

# stdin -> файл $1 атомарно. Пустой ввод не записывается: это защита от упавшего jq
write_atomic() {
	mkdir -p "$(dirname "$1")"
	if cat > "$1.tmp.$$" && [ -s "$1.tmp.$$" ]; then
		mv -f "$1.tmp.$$" "$1"
	else
		rm -f "$1.tmp.$$"
		return 1
	fi
}

# Флаги-файлы в $GRKA_RUN. flag_take возвращает 0, если флаг был, и снимает его
flag_set() {
	mkdir -p "$GRKA_RUN" && : > "$GRKA_RUN/$1"
}

flag_take() {
	[ -e "$GRKA_RUN/$1" ] || return 1
	rm -f "$GRKA_RUN/$1"
}

# Блокировка через mkdir. Если владелец умер, блокировка снимается
lock_acquire() {
	mkdir -p "$GRKA_RUN"
	if mkdir "$GRKA_RUN/$1.lock" 2>/dev/null; then
		echo $$ > "$GRKA_RUN/$1.lock/pid"
		return 0
	fi
	_lp="$(cat "$GRKA_RUN/$1.lock/pid" 2>/dev/null)"
	if [ -n "$_lp" ] && kill -0 "$_lp" 2>/dev/null; then
		return 1
	fi
	rm -rf "$GRKA_RUN/$1.lock"
	mkdir "$GRKA_RUN/$1.lock" 2>/dev/null && echo $$ > "$GRKA_RUN/$1.lock/pid"
}

lock_release() {
	rm -rf "$GRKA_RUN/$1.lock"
}

# Жив ли процесс $1. Если задан $2, его командная строка должна содержать $2 (защита от переиспользования PID)
pid_alive() {
	[ -n "$1" ] || return 1
	kill -0 "$1" 2>/dev/null || return 1
	[ -n "${2:-}" ] || return 0
	tr '\000' ' ' < "$GRKA_PROC/$1/cmdline" 2>/dev/null | grep -q -- "$2"
}

# Запуск в фоне, отвязанно от родителя. $1 - лог, дальше команда. PID кладётся в SPAWN_PID
spawn_bg() {
	_sl="$1"
	shift
	if command -v setsid >/dev/null 2>&1; then
		nohup setsid "$@" >> "$_sl" 2>&1 < /dev/null &
	else
		nohup "$@" >> "$_sl" 2>&1 < /dev/null &
	fi
	SPAWN_PID=$!
}

# Совместимость со скриптами 0.0.2
detach() {
	spawn_bg "$@"
}

fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -sfL --connect-timeout 10 --retry 2 "$1"
	else
		wget -qO- "$1"
	fi
}

download() {
	# $1 - url, $2 - файл назначения
	if command -v curl >/dev/null 2>&1; then
		curl -fL --connect-timeout 10 --retry 2 -o "$2" "$1"
	else
		wget -qO "$2" "$1"
	fi
}

latest_tag() {
	# $1 - owner/repo -> tag_name последнего стабильного релиза
	fetch "https://api.github.com/repos/$1/releases/latest" 2>/dev/null |
		sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

mihomo_arch() {
	# Архитектура бинарника mihomo. Entware: aarch64-3.10, armv7sf-k3.2, mipselsf-3.4, mipssf-3.4, x64-3.2
	_pa=""
	if command -v opkg >/dev/null 2>&1; then
		_pa="$(opkg print-architecture 2>/dev/null | awk '$2 != "all" && $2 != "noarch" { a = $2 } END { print a }')"
	fi
	case "$_pa" in
	x64* | x86_64*) echo "amd64-compatible"; return ;;
	x86* | i386* | i686*) echo "386"; return ;;
	aarch64* | arm64*) echo "arm64"; return ;;
	armv7*) echo "armv7"; return ;;
	armv5*) echo "armv5"; return ;;
	mips64el*) echo "mips64le"; return ;;
	mips64*) echo "mips64"; return ;;
	mipsel*) echo "mipsle-softfloat"; return ;;
	mips*) echo "mips-softfloat"; return ;;
	riscv64*) echo "riscv64"; return ;;
	esac
	case "$(uname -m)" in
	x86_64) echo "amd64-compatible" ;;
	i386 | i686) echo "386" ;;
	aarch64) echo "arm64" ;;
	armv7*) echo "armv7" ;;
	armv6*) echo "armv6" ;;
	armv5*) echo "armv5" ;;
	mips64) echo "mips64" ;;
	mipsel) echo "mipsle-softfloat" ;;
	mips) echo "mips-softfloat" ;;
	riscv64) echo "riscv64" ;;
	*) echo "" ;;
	esac
}
