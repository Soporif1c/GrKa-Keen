# shellcheck shell=sh
# Клиент RCI Keenetic (локальный API NDM).
# На KeeneticOS 5.2 и новее нужен токен в заголовке X-Ndma-Tkn (настройка rci_token).

RCI_URL="${RCI_URL:-http://127.0.0.1:79/rci}"

# Печатает ответ. Код: 0 - ок, 2 - нужен или неверный токен, 1 - RCI недоступен
rci_get() {
	mkdir -p "$GRKA_RUN"
	_ro="$GRKA_RUN/rci.$$.out"
	_rt="$(settings_get rci_token)"
	if [ -n "$_rt" ]; then
		_rc="$(curl -s -m 5 --connect-timeout 2 -o "$_ro" -w '%{http_code}' -H "X-Ndma-Tkn: $_rt" "$RCI_URL/$1")"
	else
		_rc="$(curl -s -m 5 --connect-timeout 2 -o "$_ro" -w '%{http_code}' "$RCI_URL/$1")"
	fi
	case "$_rc" in
	200)
		cat "$_ro"
		rm -f "$_ro"
		return 0
		;;
	401 | 403)
		rm -f "$_ro"
		return 2
		;;
	*)
		rm -f "$_ro"
		return 1
		;;
	esac
}

# ffffaab | 0xFFFFAAB | 268434091 -> 0xffffaab. Формат проверяется до арифметики:
# ошибка в $((...)) завершила бы весь процесс сторожа
mark_normalize() {
	_mv="$1"
	_mh=""
	case "$_mv" in
	0x* | 0X*)
		_mv="${_mv#0[xX]}"
		_mh=1
		;;
	esac
	case "$_mv" in
	"" | *[!0-9a-fA-F]*) return 1 ;;
	esac
	if [ -z "$_mh" ]; then
		case "$_mv" in *[!0-9]*) _mh=1 ;; esac
	fi
	if [ -n "$_mh" ]; then
		[ "${#_mv}" -le 8 ] || return 1
		printf '0x%x\n' "$((0x$_mv))"
	else
		[ "${#_mv}" -le 10 ] || return 1
		printf '0x%x\n' "$_mv"
	fi
}

# $1 - имя политики (регистр латиницы не важен). Печатает "<id> <метка>"
# Коды: как у rci_get; 3 - такой политики нет
rci_policy_lookup() {
	_rj="$(rci_get show/ip/policy)" || return $?
	_rl="$(printf '%s' "$_rj" | jqc -r --arg n "$1" '
		if type == "object" then to_entries[] else empty end
		| select((.value.description // "") | ascii_downcase == ($n | ascii_downcase))
		| "\(.key) \(.value.mark // "")"' 2>/dev/null | head -n 1)"
	[ -n "$_rl" ] || return 3
	_rm="$(mark_normalize "${_rl#* }")" || return 3
	printf '%s %s\n' "${_rl%% *}" "$_rm"
}

# $1 - id политики (Policy0). Печатает JSON-массив [{mac, ip, name, active}]; битый IP становится ""
rci_policy_hosts() {
	_rj="$(rci_get show/ip/hotspot)" || return $?
	printf '%s' "$_rj" | jqc -c --arg p "$1" '
		[(.host // [])[]
		 | select((.policy // "") == $p)
		 | {mac: ((.mac // "") | ascii_downcase),
		    ip: ((.ip // "") | if test("\\A[0-9]{1,3}(\\.[0-9]{1,3}){3}\\z") then . else "" end),
		    name: (([.name, .hostname, .mac] | map(select(. != null and . != "")) | first) // ""),
		    active: (if has("active") then ((.active | tostring) as $a | $a == "true" or $a == "yes" or $a == "1")
		             else ((.link // "") == "up") end)}]'
}
