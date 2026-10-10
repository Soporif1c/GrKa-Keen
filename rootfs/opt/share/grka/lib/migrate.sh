# shellcheck shell=sh
# Переход с GrKa Keen 0.0.2 (спека §14). Выполняется один раз, повторный вызов ничего не делает.

MIGRATE_MARK="$GRKA_ETC/.migrated-1.0"

# Останавливает mihomo, запущенный старым S97mihomo (командная строка содержит -d $MIHOMO_DIR)
migrate_kill_old_mihomo() {
	for _cf in "$GRKA_PROC"/[0-9]*/cmdline; do
		[ -f "$_cf" ] || continue
		_ct="$(tr '\000' ' ' < "$_cf" 2>/dev/null)"
		case "$_ct" in
		*mihomo*" -d $MIHOMO_DIR "* | *mihomo*" -d $MIHOMO_DIR")
			_kp="${_cf%/cmdline}"
			kill "${_kp##*/}" 2>/dev/null
			;;
		esac
	done
}

migrate_run() {
	settings_init
	state_init
	[ ! -e "$MIGRATE_MARK" ] || return 0
	if [ -f "$GRKA_ETC/grka.conf" ]; then
		_pn="$(sed -n "s/^POLICY_NAME='\(.*\)'[[:space:]]*$/\1/p" "$GRKA_ETC/grka.conf" | head -n 1)"
		if [ -n "$_pn" ] && policy_name_valid "$_pn"; then
			settings_set policy_name "$(json_str "$_pn")"
		fi
		mv -f "$GRKA_ETC/grka.conf" "$GRKA_ETC/grka.conf.0.0.2"
	fi
	_s97="$GRKA_INITD/S97mihomo"
	if [ -f "$_s97" ] && grep -q "GrKa Keen" "$_s97"; then
		if grep -q '^ENABLED=no' "$_s97"; then
			settings_set autostart false
		fi
		migrate_kill_old_mihomo
		mv -f "$_s97" "$_s97.grka-disabled"
		journal info "Старый сервис S97mihomo отключён: ядром теперь управляет сторож"
	fi
	if [ -f "$MIHOMO_DIR/config.yaml" ] && [ -z "$(settings_get expert.mihomo)" ]; then
		settings_set expert.mihomo "$(json_str "$MIHOMO_DIR/config.yaml")"
	fi
	rm -f "$GRKA_LOGDIR/mihomo.log" "$GRKA_LOGDIR/mihomo.log.old"
	mkdir -p "$GRKA_ETC"
	: > "$MIGRATE_MARK"
	journal info "Переход на GrKa Keen 1.0 выполнен"
}
