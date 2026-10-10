# shellcheck shell=sh
# Адаптер ядра mihomo. Набор функций core_* одинаков для всех ядер (спека §7.1).
# На этапе 1 бинарник и конфиг лежат там же, где в 0.0.2: /opt/sbin/mihomo, /opt/etc/mihomo.

MIHOMO_BIN="${MIHOMO_BIN:-/opt/sbin/mihomo}"
MIHOMO_GZ="${MIHOMO_GZ:-$GRKA_SHARE/mihomo.gz}"
MIHOMO_TMP="${MIHOMO_TMP:-$GRKA_RUN/mihomo}"
COMPACT_FLAG="$MIHOMO_DIR/.compact"
CORE_PIDFILE="$GRKA_RUN/core.pid"

core_name() {
	echo mihomo
}

# Конфиг: свой (режим эксперта, путь в настройках) или стандартный
core_config() {
	_cc="$(settings_get expert.mihomo)"
	echo "${_cc:-$MIHOMO_DIR/config.yaml}"
}

# Подпись конфига: по ней сторож понимает, что конфиг поменяли после ошибки
core_config_sig() {
	md5sum < "$(core_config)" 2>/dev/null | cut -c1-32
}

compact_on() {
	[ -f "$COMPACT_FLAG" ]
}

core_ready() {
	[ -x "$MIHOMO_BIN" ] || [ -x "$MIHOMO_TMP" ] || [ -f "$MIHOMO_GZ" ]
}

core_bin() {
	if [ -x "$MIHOMO_BIN" ]; then
		echo "$MIHOMO_BIN"
	elif [ -x "$MIHOMO_TMP" ]; then
		echo "$MIHOMO_TMP"
	fi
}

# Путь к бинарнику; в компактном режиме распаковывает ядро в RAM
ensure_core() {
	_eb="$(core_bin)"
	if [ -z "$_eb" ] && [ -f "$MIHOMO_GZ" ]; then
		mkdir -p "$(dirname "$MIHOMO_TMP")"
		if gunzip -c "$MIHOMO_GZ" > "$MIHOMO_TMP" 2>/dev/null; then
			chmod +x "$MIHOMO_TMP"
			_eb="$MIHOMO_TMP"
		else
			rm -f "$MIHOMO_TMP"
		fi
	fi
	echo "$_eb"
}

core_version() {
	_vb="$(core_bin)"
	[ -n "$_vb" ] || return 0
	"$_vb" -v 2>/dev/null | head -n 1 | awk '{print $3}'
}

# Проверка конфига $1 самим ядром. Код: 0 - верный, 3 - ядро не установлено, другое - ошибка
core_validate() {
	_vb="$(ensure_core)"
	if [ -z "$_vb" ]; then
		echo "Ядро mihomo не установлено"
		return 3
	fi
	"$_vb" -t -d "$MIHOMO_DIR" -f "$1" 2>&1
}

core_pid() {
	cat "$CORE_PIDFILE" 2>/dev/null
}

# PID нашего mihomo по /proc: командная строка содержит "mihomo" и "-d $MIHOMO_DIR".
# Кандидатов отбирает один grep: tr на каждый из сотен процессов роутера слишком дорог для прохода раз в 10 секунд
core_find_pid() {
	for _cf in $(grep -l -F -- "$MIHOMO_DIR" "$GRKA_PROC"/[0-9]*/cmdline 2>/dev/null); do
		_ct="$(tr '\000' ' ' < "$_cf" 2>/dev/null)"
		case "$_ct" in
		*mihomo*" -d $MIHOMO_DIR "* | *mihomo*" -d $MIHOMO_DIR")
			_cp="${_cf%/cmdline}"
			echo "${_cp##*/}"
			return 0
			;;
		esac
	done
	return 1
}

# Работает ли ядро. Потерянный PID-файл восстанавливается по /proc
core_running() {
	pid_alive "$(core_pid)" mihomo && return 0
	_fp="$(core_find_pid)" || return 1
	pid_alive "$_fp" mihomo || return 1
	mkdir -p "$GRKA_RUN"
	echo "$_fp" > "$CORE_PIDFILE"
}

# Код: 0 - запущено, 3 - ядро не установлено, 4 - нет конфига
core_start() {
	_sb="$(ensure_core)"
	[ -n "$_sb" ] || return 3
	_sc="$(core_config)"
	[ -f "$_sc" ] || return 4
	mkdir -p "$GRKA_RUN"
	core_log_rotate
	# shellcheck disable=SC3045
	ulimit -n 65536 2>/dev/null
	echo "$(date '+%Y-%m-%d %H:%M:%S') [grka] запуск mihomo" >> "$CORE_LOG"
	spawn_bg "$CORE_LOG" "$_sb" -d "$MIHOMO_DIR" -f "$_sc"
	echo "$SPAWN_PID" > "$CORE_PIDFILE"
	return 0
}

# Остановка по PID (не killall: рядом может работать чужой mihomo). 10 секунд на TERM, потом KILL.
# Без PID-файла ядро ищется по /proc, иначе оно осталось бы работать после «Стоп»
core_stop() {
	_kp="$(core_pid)"
	pid_alive "$_kp" mihomo || _kp="$(core_find_pid)"
	if pid_alive "$_kp" mihomo; then
		kill "$_kp" 2>/dev/null
		_ki=0
		while pid_alive "$_kp" mihomo && [ "$_ki" -lt 10 ]; do
			sleep 1
			_ki=$((_ki + 1))
		done
		if pid_alive "$_kp" mihomo; then
			kill -9 "$_kp" 2>/dev/null
		fi
	fi
	rm -f "$CORE_PIDFILE"
}

# Имя TUN из конфига (tun.device, блочный или inline-стиль). Без него mihomo называет TUN «Meta»
core_tun() {
	_td=""
	_tcf="$(core_config)"
	if [ -f "$_tcf" ]; then
		_td="$(awk '
			/^tun:[[:space:]]*\{/ {
				if (match($0, /device:[[:space:]]*[^,}[:space:]]+/)) {
					v = substr($0, RSTART, RLENGTH); sub(/device:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); print v; exit
				}
			}
			/^tun:/ { intun = 1; next }
			intun && /^[^[:space:]#]/ { intun = 0 }
			intun && /^[[:space:]]+device:/ { v = $2; gsub(/["\047]/, "", v); print v; exit }
		' "$_tcf")"
	fi
	echo "${_td:-Meta}"
}

# Порт DNS-слушателя ядра (dns.listen) или пусто, если слушателя нет.
# Без слушателя DNS игровых устройств перенаправлять нельзя: они останутся без DNS.
# Слушателя нет, если DNS ядра не включён явно (enable: true, по умолчанию в mihomo он выключен)
# или слушает только loopback: REDIRECT отправляет запрос на адрес входящего интерфейса
core_dns_port() {
	_dcf="$(core_config)"
	[ -f "$_dcf" ] || return 0
	awk '
		function listen_at(v,   n, a, host) {
			gsub(/["\047]/, "", v)
			n = split(v, a, ":")
			port = a[n]
			host = substr(v, 1, length(v) - length(a[n]) - 1)
			loop = (host ~ /^(127\.|localhost$|\[::1\]$|::1$)/)
		}
		/^dns:[[:space:]]*\{/ {
			if ($0 ~ /enable:[[:space:]]*true/) on = 1
			if (match($0, /listen:[[:space:]]*[^,}[:space:]]+/)) {
				v = substr($0, RSTART, RLENGTH); sub(/listen:[[:space:]]*/, "", v); listen_at(v)
			}
			exit
		}
		/^dns:/ { indns = 1; next }
		indns && /^[^[:space:]#]/ { exit }
		indns && /^[[:space:]]+enable:[[:space:]]*true/ { on = 1 }
		indns && /^[[:space:]]+listen:/ { listen_at($2) }
		END { if (on && !loop && port ~ /^[0-9]+$/) print port }
	' "$_dcf"
}

# Ротация лога ядра: копия + обнуление. Ядро пишет с O_APPEND и продолжит писать в тот же файл
core_log_rotate() {
	[ -f "$CORE_LOG" ] || return 0
	[ "$(wc -c < "$CORE_LOG")" -gt "$CORE_LOG_MAX" ] || return 0
	cp -f "$CORE_LOG" "$CORE_LOG.old" && : > "$CORE_LOG"
}

core_api_port() {
	sed -n "s/^external-controller:.*:\([0-9]\{1,\}\).*/\1/p" "$(core_config)" 2>/dev/null | head -n 1
}

core_api_secret() {
	sed -n "s/^secret:[[:space:]]*[\"']\{0,1\}\([^\"']*\)[\"']\{0,1\}[[:space:]]*$/\1/p" "$(core_config)" 2>/dev/null | head -n 1
}
