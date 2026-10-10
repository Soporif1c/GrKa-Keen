# shellcheck shell=sh
# Сторож (спека §6): приводит систему к желаемому состоянию и пишет статус и журнал.
# Зависит от: common.sh, settings.sh, rci.sh, routing.sh, dnsredir.sh, core.sh.
# Состояние между проходами — в $GRKA_RUN/wd.env (только безопасные значения: числа, метки, IP, слова).

WD_ENV="$GRKA_RUN/wd.env"

wd_load() {
	WD_MARK=""
	WD_POLICY_ID=""
	WD_RCI_STATE=init
	WD_RCI_TRIES=0
	WD_LAST_RCI=0
	WD_NOPOLICY_SINCE=0
	WD_GAMING_IPS=""
	WD_CORE_FAILS=0
	WD_CORE_FIRST_FAIL=0
	WD_CORE_NEXT=0
	WD_CORE_UP_SINCE=""
	WD_CORE_CFG_SIG=""
	WD_CORE_ERROR_KIND=""
	WD_CORE_ERROR_TS=0
	WD_APPLIED=""
	WD_RULES_OK=false
	WD_TUN_UP=false
	WD_DNS_PORT=""
	# shellcheck disable=SC1090
	[ ! -f "$WD_ENV" ] || . "$WD_ENV"
	WD_CORE_ERROR="$(cat "$GRKA_RUN/core.error.title" 2>/dev/null)"
	return 0
}

wd_save() {
	{
		echo "WD_MARK='$WD_MARK'"
		echo "WD_POLICY_ID='$WD_POLICY_ID'"
		echo "WD_RCI_STATE='$WD_RCI_STATE'"
		echo "WD_RCI_TRIES='$WD_RCI_TRIES'"
		echo "WD_LAST_RCI='$WD_LAST_RCI'"
		echo "WD_NOPOLICY_SINCE='$WD_NOPOLICY_SINCE'"
		echo "WD_GAMING_IPS='$WD_GAMING_IPS'"
		echo "WD_CORE_FAILS='$WD_CORE_FAILS'"
		echo "WD_CORE_FIRST_FAIL='$WD_CORE_FIRST_FAIL'"
		echo "WD_CORE_NEXT='$WD_CORE_NEXT'"
		echo "WD_CORE_UP_SINCE='$WD_CORE_UP_SINCE'"
		echo "WD_CORE_CFG_SIG='$WD_CORE_CFG_SIG'"
		echo "WD_CORE_ERROR_KIND='$WD_CORE_ERROR_KIND'"
		echo "WD_CORE_ERROR_TS='$WD_CORE_ERROR_TS'"
		echo "WD_APPLIED='$WD_APPLIED'"
		echo "WD_RULES_OK='$WD_RULES_OK'"
		echo "WD_TUN_UP='$WD_TUN_UP'"
	} | write_atomic "$WD_ENV"
	if [ -n "$WD_CORE_ERROR" ]; then
		printf '%s\n' "$WD_CORE_ERROR" | write_atomic "$GRKA_RUN/core.error.title"
	else
		rm -f "$GRKA_RUN/core.error.title" "$GRKA_RUN/core.error"
	fi
}

wd_mark_from_cache() {
	_cl="$(cat "$CACHE_DIR/policy_mark" 2>/dev/null)"
	[ -n "$_cl" ] || return 1
	WD_POLICY_ID="$(printf '%s' "${_cl%% *}" | tr -cd 'A-Za-z0-9_-')"
	WD_MARK="$(mark_normalize "${_cl#* }")" || WD_MARK=""
	[ -n "$WD_MARK" ]
}

# $1 - имя политики
wd_rci_refresh() {
	_prev="$WD_RCI_STATE"
	_rnow="$(now_ts)"
	_res="$(rci_policy_lookup "$1")"
	_rc=$?
	case $_rc in
	0)
		_id="$(printf '%s' "${_res%% *}" | tr -cd 'A-Za-z0-9_-')"
		_mk="${_res#* }"
		WD_NOPOLICY_SINCE=0
		if [ -n "$WD_MARK" ] && [ "$WD_MARK" != "$_mk" ]; then
			journal info "Метка политики «$1» сменилась: $WD_MARK → $_mk"
		elif [ "$_prev" != ok ] && [ "$_prev" != recheck ]; then
			if [ "$WD_RCI_TRIES" -gt 0 ]; then
				journal info "Политика «$1» найдена (метка $_mk), попыток: $((WD_RCI_TRIES + 1))"
			else
				journal info "Политика «$1» найдена (метка $_mk)"
			fi
		fi
		WD_MARK="$_mk"
		WD_POLICY_ID="$_id"
		WD_RCI_STATE=ok
		WD_RCI_TRIES=0
		printf '%s %s\n' "$_id" "$_mk" | write_atomic "$CACHE_DIR/policy_mark"
		if _hj="$(rci_policy_hosts "$_id")"; then
			printf '%s\n' "$_hj" | write_atomic "$HOSTS_FILE"
		fi
		;;
	2)
		[ "$_prev" = auth ] || journal error "RCI требует токен доступа (KeeneticOS 5.2 и новее). Укажите его в настройках панели"
		WD_RCI_STATE=auth
		WD_RCI_TRIES=$((WD_RCI_TRIES + 1))
		wd_mark_from_cache
		;;
	3)
		WD_RCI_TRIES=$((WD_RCI_TRIES + 1))
		[ "${WD_NOPOLICY_SINCE:-0}" -gt 0 ] || WD_NOPOLICY_SINCE="$_rnow"
		if [ -n "$WD_MARK" ] && [ $((_rnow - WD_NOPOLICY_SINCE)) -lt 30 ]; then
			# NDM может на миг отдать список без политики, пока перенастраивает политики.
			# Правила держим 30 секунд: пока политики нет, её метку никто не ставит, правила ничему не мешают.
			# Состояние recheck не равно ok, поэтому RCI спросим снова на следующем проходе
			WD_RCI_STATE=recheck
		else
			[ "$_prev" = nopolicy ] || journal warn "Политика «$1» не найдена в Keenetic"
			WD_RCI_STATE=nopolicy
			WD_MARK=""
			WD_POLICY_ID=""
			rm -f "$CACHE_DIR/policy_mark"
		fi
		;;
	*)
		if wd_mark_from_cache; then
			[ "$_prev" = down ] || journal warn "RCI не отвечает, использую сохранённую метку политики $WD_MARK"
		else
			[ "$_prev" = down ] || journal warn "RCI не отвечает, жду"
		fi
		WD_RCI_STATE=down
		WD_RCI_TRIES=$((WD_RCI_TRIES + 1))
		;;
	esac
	WD_LAST_RCI="$_rnow"
}

# IP игровых устройств политики (из последнего ответа RCI), только правильные IPv4
wd_gaming_ips() {
	[ -s "$HOSTS_FILE" ] || return 0
	jqc -r --slurpfile st "$STATE_FILE" '
		($st[0].devices // {}) as $d
		| .[] | select(($d[.mac].type // "") == "gaming") | .ip
		| select(test("\\A[0-9]{1,3}(\\.[0-9]{1,3}){3}\\z"))' "$HOSTS_FILE" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

wd_wait_tun() {
	_wi=0
	while [ "$_wi" -lt "$1" ]; do
		ip link show "$RT_TUN" >/dev/null 2>&1 && return 0
		sleep 1
		_wi=$((_wi + 1))
	done
	return 1
}

# Падение ядра. $1 - время, $2 - текст. Паузы 5, 15, 60 с; четвёртое падение за 5 минут — стоп
wd_core_failed() {
	if [ $(($1 - ${WD_CORE_FIRST_FAIL:-0})) -gt 300 ]; then
		WD_CORE_FAILS=0
		WD_CORE_FIRST_FAIL="$1"
	fi
	WD_CORE_FAILS=$((${WD_CORE_FAILS:-0} + 1))
	case "$WD_CORE_FAILS" in
	1) _wd=5 ;;
	2) _wd=15 ;;
	3) _wd=60 ;;
	*)
		WD_CORE_ERROR="Ядро $(core_name) падает раз за разом"
		WD_CORE_ERROR_KIND=crash
		WD_CORE_ERROR_TS="$1"
		WD_CORE_CFG_SIG="$(core_config_sig)"
		tail -n 5 "$CORE_LOG" 2>/dev/null | write_atomic "$GRKA_RUN/core.error"
		journal error "Ядро упало $WD_CORE_FAILS раза за 5 минут, повторы остановлены. Смотрите лог ядра"
		return 0
		;;
	esac
	WD_CORE_NEXT=$(($1 + _wd))
	journal warn "$2, перезапуск через $_wd с"
}

# $1 - должно ли ядро работать (true/false), $2 - текущее время
wd_core() {
	if [ "$1" != true ]; then
		if core_running; then
			core_stop
			journal info "Ядро $(core_name) остановлено"
		fi
		WD_CORE_UP_SINCE=""
		WD_CORE_FAILS=0
		WD_CORE_ERROR=""
		WD_CORE_NEXT=0
		return 0
	fi
	if flag_take restart-core; then
		if core_running; then
			core_stop
		fi
		WD_CORE_UP_SINCE=""
		WD_CORE_FAILS=0
		WD_CORE_ERROR=""
		WD_CORE_NEXT=0
		journal info "Перезапуск ядра по запросу"
	fi
	if core_running; then
		[ -n "$WD_CORE_UP_SINCE" ] || WD_CORE_UP_SINCE="$2"
		return 0
	fi
	if [ -n "$WD_CORE_UP_SINCE" ]; then
		WD_CORE_UP_SINCE=""
		wd_core_failed "$2" "Ядро $(core_name) упало"
	fi
	if [ -n "$WD_CORE_ERROR" ]; then
		if [ "$(core_config_sig)" != "$WD_CORE_CFG_SIG" ]; then
			journal info "Конфиг изменился, пробую запустить ядро снова"
			WD_CORE_ERROR=""
			WD_CORE_FAILS=0
			WD_CORE_NEXT=0
		elif [ "$WD_CORE_ERROR_KIND" != crash ] && [ $(($2 - ${WD_CORE_ERROR_TS:-0})) -ge 300 ]; then
			# раз в 5 минут перепроверяем: при загрузке проверка может не пройти из-за временного сбоя
			:
		else
			return 0
		fi
	fi
	[ "$2" -ge "${WD_CORE_NEXT:-0}" ] || return 0
	_vo="$(core_validate "$(core_config)")"
	_vr=$?
	if [ $_vr -ne 0 ]; then
		if [ $_vr -eq 3 ]; then
			wd_core_error "$2" missing "Ядро $(core_name) не установлено"
		else
			wd_core_error "$2" validate "Конфиг ядра не прошёл проверку"
		fi
		printf '%s\n' "$_vo" | tail -n 5 | write_atomic "$GRKA_RUN/core.error"
		return 0
	fi
	WD_CORE_ERROR=""
	core_start
	case $? in
	0)
		WD_CORE_UP_SINCE="$2"
		if wd_wait_tun 30; then
			journal info "Ядро $(core_name) запущено"
		else
			journal warn "Ядро $(core_name) запущено, но TUN $RT_TUN не появился за 30 секунд"
		fi
		;;
	3) wd_core_error "$2" missing "Ядро $(core_name) не установлено" ;;
	*) wd_core_error "$2" noconfig "Нет конфига ядра: $(core_config)" ;;
	esac
}

# Ошибка запуска ядра. $1 - время, $2 - вид (validate|missing|noconfig), $3 - текст.
# Повтор той же ошибки при перепроверке в журнал не пишется
wd_core_error() {
	[ "$3" = "$WD_CORE_ERROR" ] || journal error "$3"
	WD_CORE_ERROR="$3"
	WD_CORE_ERROR_KIND="$2"
	WD_CORE_ERROR_TS="$1"
	WD_CORE_CFG_SIG="$(core_config_sig)"
}

# $1 - пауза (true/false), $2 - работает ли ядро (true/false)
wd_routes() {
	if [ -z "$WD_MARK" ]; then
		if [ -n "$(rt_current_rules)" ]; then
			rt_clear
			journal info "Правила маршрутизации сняты: политика не найдена"
		fi
		dns_clear >/dev/null
		WD_RULES_OK=false
		WD_TUN_UP=false
		return 0
	fi
	WD_TUN_UP=false
	if [ "$2" = true ] && ip link show "$RT_TUN" >/dev/null 2>&1; then
		WD_TUN_UP=true
	fi
	_v6="$(settings_get ipv6_block)"
	[ "$_v6" = false ] || _v6=true
	_rch="$(rt_rules_apply "$WD_MARK" "$1" "$WD_GAMING_IPS")$(rt_tables_apply "$WD_TUN_UP")$(rt6_apply "$WD_MARK" "$_v6")"
	rt_rpfilter
	# порт берём из конфига ядра: если DNS-слушателя нет, перенаправление оставило бы игровые устройства без DNS
	WD_DNS_PORT="$(core_dns_port)"
	case "$WD_DNS_PORT" in *[!0-9]*) WD_DNS_PORT="" ;; esac
	if [ "$WD_TUN_UP" = true ] && [ "$1" != true ] && [ -n "$WD_DNS_PORT" ]; then
		_dch="$(dns_apply "$WD_GAMING_IPS" "$WD_DNS_PORT")"
	else
		_dch="$(dns_clear)"
	fi
	if [ -n "$_rch" ]; then
		if [ -n "$WD_APPLIED" ]; then
			journal info "Правила маршрутизации восстановлены"
		else
			journal info "Правила маршрутизации применены"
		fi
	fi
	[ -z "$_dch" ] || journal info "Перенаправление DNS игровых устройств обновлено"
	WD_APPLIED=1
	WD_RULES_OK=true
}

# $1 - enabled, $2 - paused, $3 - ядро работает
wd_state_word() {
	if [ -n "$WD_CORE_ERROR" ]; then
		echo error
	elif [ "$1" != true ]; then
		echo stopped
	elif [ "$2" = true ]; then
		echo paused
	elif [ -z "$WD_MARK" ]; then
		echo waiting_policy
	elif [ "$3" != true ] || [ "$WD_TUN_UP" != true ]; then
		echo starting
	else
		echo ok
	fi
}

wd_warnings() {
	{
		[ "$WD_RCI_STATE" != auth ] || echo "Нужен токен RCI: KeeneticOS 5.2 и новее не отвечают без него. Создайте токен в Keenetic (Пользователи и доступ) и укажите его в настройках панели"
		[ "$WD_RCI_STATE" != nopolicy ] || echo "Политика «$(settings_get policy_name)» не найдена. Создайте её в Keenetic: Приоритеты подключений, Политики доступа в интернет"
		[ "$WD_RCI_STATE" != down ] || echo "RCI роутера не отвечает"
		if [ -n "$WD_GAMING_IPS" ] && [ -n "$WD_MARK" ] && [ -z "${WD_DNS_PORT:-}" ]; then
			echo "У игровых устройств VPN по доменам не работает: в конфиге ядра нет DNS-слушателя (dns.listen). Их DNS идёт через роутер напрямую"
		fi
		if ls "$GRKA_INITD"/S*xkeen* >/dev/null 2>&1; then
			echo "Установлен XKeen. Он конфликтует с GrKa Keen: остановите или удалите его"
		fi
	} | jqc -R -s -c 'split("\n") | map(select(. != ""))'
}

# $1 - время, $2 - enabled, $3 - paused, $4 - ядро работает
wd_status_write() {
	_pid="$(core_pid)"
	_mem=""
	[ "$4" != true ] || _mem="$(awk '/VmRSS/ {print $2}' "$GRKA_PROC/$_pid/status" 2>/dev/null)"
	_hosts="$(cat "$HOSTS_FILE" 2>/dev/null)"
	[ -n "$_hosts" ] || _hosts='[]'
	_devs="$(jqc -c '.devices // {}' "$STATE_FILE" 2>/dev/null)"
	[ -n "$_devs" ] || _devs='{}'
	jqc -n \
		--argjson ts "$1" \
		--arg state "$(wd_state_word "$2" "$3" "$4")" \
		--argjson warnings "$(wd_warnings)" \
		--arg core_name "$(core_name)" \
		--argjson running "$4" \
		--argjson enabled "$2" \
		--arg pid "$_pid" \
		--arg mem "$_mem" \
		--arg core_error "$WD_CORE_ERROR" \
		--arg core_error_log "$(cat "$GRKA_RUN/core.error" 2>/dev/null)" \
		--arg policy "$(settings_get policy_name)" \
		--arg policy_id "$WD_POLICY_ID" \
		--arg mark "$WD_MARK" \
		--arg rci "$WD_RCI_STATE" \
		--argjson hosts "$_hosts" \
		--argjson devices "$_devs" \
		--argjson rules_ok "$WD_RULES_OK" \
		--arg tun "$RT_TUN" \
		--argjson tun_up "$WD_TUN_UP" \
		--arg gaming "$WD_GAMING_IPS" \
		--argjson paused "$3" \
		'{ts: $ts, state: $state, warnings: $warnings,
		  core: {name: $core_name, running: $running, enabled: $enabled, pid: $pid, memory_kb: $mem,
		         error: $core_error, error_log: $core_error_log},
		  policy: {name: $policy, id: $policy_id, mark: $mark, found: ($mark != ""), rci: $rci,
		           hosts: [$hosts[] | . + {type: ($devices[.mac].type // "regular")}]},
		  routing: {rules_ok: $rules_ok, tun: $tun, tun_up: $tun_up,
		            gaming_ips: ($gaming | split(" ") | map(select(. != "")))},
		  paused: $paused}' | write_atomic "$STATUS_FILE"
}

# Один проход сторожа
wd_tick() {
	wd_load
	_now="$(now_ts)"
	RT_TUN="$(core_tun)"
	_policy="$(settings_get policy_name)"
	[ -n "$_policy" ] || _policy=GrKa
	_en="$(state_get enabled)"
	[ "$_en" = false ] || _en=true
	_pa="$(state_get paused)"
	[ "$_pa" = true ] || _pa=false
	[ ! -e "$GRKA_RUN/hold" ] || _en=false
	if [ "$WD_RCI_STATE" != ok ] || flag_take rci-refresh || [ $((_now - ${WD_LAST_RCI:-0})) -ge 60 ]; then
		wd_rci_refresh "$_policy"
	fi
	_prev_ips="$WD_GAMING_IPS"
	WD_GAMING_IPS="$(wd_gaming_ips)"
	if [ "$_prev_ips" != "$WD_GAMING_IPS" ] && [ -n "$WD_APPLIED" ]; then
		journal info "Адреса игровых устройств: ${WD_GAMING_IPS:-нет}"
	fi
	wd_core "$_en" "$_now"
	core_log_rotate
	_run=false
	if core_running; then _run=true; fi
	wd_routes "$_pa" "$_run"
	wd_status_write "$_now" "$_en" "$_pa" "$_run"
	wd_save
}

# Ожидание до $1 секунд с проверкой флага dirty каждую секунду
wd_sleep() {
	_wsi=0
	while [ "$_wsi" -lt "$1" ]; do
		if flag_take dirty; then
			return 0
		fi
		sleep 1
		_wsi=$((_wsi + 1))
	done
}

wd_main() {
	mkdir -p "$GRKA_RUN" "$CACHE_DIR"
	_wpf="$GRKA_RUN/watchdog.pid"
	if pid_alive "$(cat "$_wpf" 2>/dev/null)" grka-watchdog; then
		echo "Сторож уже запущен"
		return 0
	fi
	echo $$ > "$_wpf"
	trap 'rm -f "$GRKA_RUN/watchdog.pid"; exit 0' TERM INT
	settings_init
	state_init
	rm -f "$WD_ENV"
	[ "$(settings_get autostart)" != false ] || flag_set hold
	_wstart="$(now_ts)"
	journal info "Сторож запущен"
	while :; do
		wd_tick
		_wwait=10
		if [ "$WD_RCI_STATE" != ok ] && [ $(($(now_ts) - _wstart)) -lt 60 ]; then
			_wwait=2
		fi
		wd_sleep "$_wwait"
	done
}
