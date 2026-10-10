# GrKa Keen 1.0, этап 1 «Фундамент» — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сторож, который сам держит правила маршрутизации политики Keenetic и ядро mihomo после перезагрузок, переподключений и перестроек файрвола; защищённый от CSRF бэкенд; переход с 0.0.2 без поломок.

**Architecture:** Логика разложена по библиотекам `rootfs/opt/share/grka/lib/*.sh` (busybox ash + jq), каждую можно подключить и протестировать отдельно. Единственный процесс, который меняет `ip rule`, таблицы и iptables, — сторож `bin/grka-watchdog`; CGI, CLI и хуки NDM только пишут настройки и ставят флаги. Ядро на этом этапе — mihomo с конфигом пользователя (режим эксперта); генератор конфигов и Xray появятся на этапах 2–3.

**Tech Stack:** POSIX sh (busybox ash 1.3x на роутере), jq 1.8.1, iproute2 4.4 (`ip-full`), iptables 1.4.21, lighttpd 1.4 + mod_cgi, ванильный JS (старый интерфейс, минимальные правки). Тесты: busybox-w32 `sh`, jq 1.8.1 для Windows, shellcheck 0.10.0.

**Spec:** `docs/superpowers/specs/2026-10-10-grka-keen-1.0-design.md` (разделы 3, 5, 6, 10–14; этап 1 из раздела 16).

## Global Constraints

- Только POSIX sh, без bash-измов и без `local`; `shellcheck -s sh -S warning -e SC1090,SC1091` без замечаний.
- Зависимости на роутере: `jq`, `curl`, `ip-full`, `iptables`, `unzip`, `lighttpd`, `lighttpd-mod-cgi` (спека §2). Разрешены только возможности iproute2 4.4 и iptables 1.4.21.
- Имя политики по умолчанию `GrKa`; TUN `grka-tun` (для mihomo без `tun.device` — `Meta`); таблицы `1001` и `1002`; наши `ip rule` — pref 96–99; порт DNS ядра `1053`; диапазон fake-IP `198.18.0.0/15` (спека §5.2–5.3).
- RCI: `http://127.0.0.1:79/rci/<путь>`, токен в заголовке `X-Ndma-Tkn` (спека §6.1).
- Сторож: шаг 1 с, полная проверка раз в 10 с; RCI раз в 60 с; пока RCI не в порядке — каждый проход (2 с в первую минуту после старта); паузы перезапуска ядра 5, 15, 60 с; четвёртое падение за 5 минут останавливает повторы (спека §6.2).
- Лог ядра `/tmp/grka/core.log`, ротация при 1 МБ (копия + обнуление); журнал `/opt/var/log/grka/journal.log`, ротация при 256 КБ (спека §13).
- Все JSON-файлы пишутся через jq во временный файл и `mv`; пустой результат не записывается.
- CGI: только `POST`, `Content-Type: application/json`, заголовок `X-GrKa-Request: 1`; при наличии `Origin` его хост равен `Host` или `X-Forwarded-Host`; иначе `403` (спека §12).
- Init-скрипт называется `S99grka-keen` (его перезапускает самообновление 0.0.2); `stop` — полная остановка, `restart` — только панель и сторож.
- Тексты для пользователя — по-русски, простыми словами, без технических терминов там, где можно обойтись.
- Все пути библиотек переопределяются переменными окружения (`GRKA_SHARE`, `GRKA_ETC`, `GRKA_RUN`, `GRKA_LOGDIR`, `GRKA_INITD`, `GRKA_PROC`, `MIHOMO_DIR`, `MIHOMO_BIN`, `MIHOMO_GZ`, `MIHOMO_TMP`) — на этом держатся тесты.

Сознательно отложено на следующие этапы: разрешающие правила `FORWARD` для `grka-tun` (0.0.2 работает без них; `grka diag` собирает `FORWARD` для проверки на стенде), пароль панели (этап 5, вместе с новым интерфейсом), IP-списки сервисов в таблице 1002 (этап 3).

## Review Focus

1. **RCI отвечает `{}` или без нашей политики сразу после загрузки** — сторож не делает вывод «политики нет навсегда», а повторяет запрос и ставит правила, как только политика появилась. Тест: Task 8, `test_tick_policy_appears_after_boot`.
2. **NDM запускает хуки пачкой (десятки вызовов за секунду)** — хуки только ставят флаг, правила не дублируются. Тесты: Task 10, `test_netfilter_hook_*`; Task 5, `test_rules_apply_twice_is_noop`; Task 6, `test_dns_apply_twice_noop`.
3. **Имя политики с кириллицей, пробелами, кавычками, `/` и `&`** — сохраняется и находится в RCI без искажений. Тесты: Task 3, `test_settings_set_cyrillic_name_with_quotes`; Task 4, `test_policy_lookup_cyrillic_name`.
4. **Игровое устройство без IP, с битым IP или из другой политики** — пропускается, в `ip rule` не попадает мусор. Тест: Task 8, `test_tick_gaming_ips_skip_offline_and_broken`.
5. **Нет бинарника ядра или битый конфиг** — сторож показывает ошибку один раз, не крутит перезапуски и сам восстанавливается после правки конфига. Тесты: Task 8, `test_tick_bad_config_no_loop_until_changed`, `test_tick_core_not_installed_reports_once`.

---

## Структура файлов

| Файл | Ответственность |
|---|---|
| `dev/get-tools.sh` | Скачивает busybox-w32, jq, shellcheck в `.tools/` |
| `tests/run.sh` | Запуск всех `tests/*_test.sh` |
| `tests/lib/assert.sh` | Проверки и раннер тестов |
| `tests/lib/env.sh` | Пути, временные каталоги, подключение заглушек |
| `tests/lib/stubs.sh` | Заглушки `ip`, `iptables`, `curl` с состоянием в файлах |
| `tests/fixtures/*.json` | Ответы RCI |
| `rootfs/opt/share/grka/lib/common.sh` | Пути, jq, журнал, атомарная запись, флаги, блокировки, процессы, загрузки |
| `rootfs/opt/share/grka/lib/settings.sh` | `settings.json`, `state.json`, проверка ввода |
| `rootfs/opt/share/grka/lib/rci.sh` | Клиент RCI с токеном, поиск политики и её хостов |
| `rootfs/opt/share/grka/lib/routing.sh` | `ip rule` pref 96–99, таблицы 1001/1002, IPv6, rp_filter |
| `rootfs/opt/share/grka/lib/dnsredir.sh` | iptables-цепочка `GRKA_DNS` для игровых устройств |
| `rootfs/opt/share/grka/lib/core-mihomo.sh` | Адаптер mihomo: запуск, остановка, проверка конфига, TUN |
| `rootfs/opt/share/grka/lib/core.sh` | Выбор адаптера (пока только mihomo) |
| `rootfs/opt/share/grka/lib/watchdog.sh` | Проход сторожа, статус, журнал |
| `rootfs/opt/share/grka/lib/migrate.sh` | Переход с 0.0.2 |
| `rootfs/opt/share/grka/bin/grka-watchdog` | Процесс сторожа |
| `rootfs/opt/share/grka/bin/grka` | Команда для SSH |
| `rootfs/opt/share/grka/www/cgi-bin/api` | CGI с защитой от CSRF |
| `rootfs/opt/etc/init.d/S99grka-keen` | Панель + сторож |
| `rootfs/opt/etc/ndm/*/50-grka.sh` | Хуки NDM: только флаг `dirty` |
| Удаляются | `scripts/policy-route.sh`, `init.d/S97mihomo`, `etc/grka/lighttpd.conf` (теперь генерируется) |

---

### Task 1: Инструменты и тестовый каркас

**Files:**
- Create: `dev/get-tools.sh`
- Create: `tests/run.sh`, `tests/lib/assert.sh`, `tests/lib/env.sh`, `tests/lib/stubs.sh`
- Create: `tests/harness_test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `run_tests <файл>`, `assert_eq ожидаемое фактическое [описание]`, `assert_contains строка подстрока`, `assert_not_contains`, `assert_file_exists`, `assert_file_missing`, `fail текст`, `jqt` (jq с флагами окружения), переменные `T`, `REPO_DIR`, `GRKA_SRC`, `FIXTURES`, `STUB`; заглушки `ip`, `iptables`, `curl`; помощники `stub_link_up имя`, `stub_link_down имя`, `stub_rci путь код [файл_тела]`, `stub_rci_seq путь "код [файл]"...`.

- [ ] **Step 1: Скрипт загрузки инструментов**

`dev/get-tools.sh`:

```sh
#!/bin/sh
# Скачивает инструменты для тестов на Windows в .tools/: busybox-w32 (оболочка), jq 1.8.1, shellcheck 0.10.0
set -e
cd "$(dirname "$0")/.."
mkdir -p .tools
dl() {
	[ -s "$2" ] || curl -fL --retry 2 -o "$2" "$1"
}
dl https://frippery.org/files/busybox/busybox64.exe .tools/busybox.exe
dl https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-windows-amd64.exe .tools/jq.exe
if [ ! -s .tools/shellcheck.exe ]; then
	dl https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.zip .tools/shellcheck.zip
	unzip -o -q .tools/shellcheck.zip shellcheck.exe -d .tools
	rm -f .tools/shellcheck.zip
fi
.tools/busybox.exe | head -n 1
.tools/jq.exe --version
.tools/shellcheck.exe --version | sed -n 2p
```

`.gitignore` — добавить строки:

```
.tools/
```

Run (Git Bash): `sh dev/get-tools.sh`
Expected: три строки версий, среди них `jq-1.8.1` и `version: 0.10.0`.

- [ ] **Step 2: Проверки и раннер**

`tests/lib/assert.sh`:

```sh
# shellcheck shell=sh
# Мини-фреймворк: каждая функция test_* в файле — отдельный тест в своей подоболочке.
# Тест провален, если была неудачная проверка или не было ни одной проверки.

_assert_hit() {
	printf . >> "$T_ROOT/asserts"
}

fail() {
	_assert_hit
	printf '%s\n' "$*" >> "$T_ROOT/failed"
	return 1
}

assert_eq() {
	_assert_hit
	[ "$1" = "$2" ] && return 0
	fail "${3:-assert_eq}: ожидалось [$1], получено [$2]"
}

assert_contains() {
	_assert_hit
	case "$1" in *"$2"*) return 0 ;; esac
	fail "${3:-assert_contains}: нет [$2] в [$1]"
}

assert_not_contains() {
	_assert_hit
	case "$1" in *"$2"*) fail "${3:-assert_not_contains}: есть [$2] в [$1]" ;; esac
	return 0
}

assert_file_exists() {
	_assert_hit
	[ -e "$1" ] || fail "${2:-assert_file_exists}: нет файла $1"
}

assert_file_missing() {
	_assert_hit
	[ ! -e "$1" ] || fail "${2:-assert_file_missing}: файл $1 есть, а не должен"
}

run_tests() {
	_pass=0
	_failn=0
	for _t in $(sed -n 's/^\(test_[A-Za-z0-9_]*\)() *{.*$/\1/p' "$1"); do
		env_setup
		: > "$T_ROOT/failed"
		: > "$T_ROOT/asserts"
		("$_t") > "$T_ROOT/out" 2>&1
		if [ -s "$T_ROOT/failed" ] || [ ! -s "$T_ROOT/asserts" ]; then
			_failn=$((_failn + 1))
			echo "FAIL $_t"
			[ -s "$T_ROOT/asserts" ] || echo "    в тесте не было ни одной проверки (упал раньше?)"
			sed 's/^/    /' "$T_ROOT/failed" "$T_ROOT/out"
		else
			_pass=$((_pass + 1))
			echo "ok   $_t"
		fi
	done
	echo "$_pass passed, $_failn failed"
	[ "$_failn" -eq 0 ]
}
```

`tests/lib/env.sh`:

```sh
# shellcheck shell=sh
# Окружение тестов. Первая строка каждого теста: . "$(dirname "$0")/lib/env.sh"
# Библиотеки подключаются после этого файла, поэтому их пути сразу указывают во временный каталог.

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
GRKA_SRC="$REPO_DIR/rootfs/opt/share/grka"
FIXTURES="$TESTS_DIR/fixtures"
export GRKA_TEST=1

case "$(uname -s 2>/dev/null)" in
*_NT* | Windows*)
	PATH="$REPO_DIR/.tools;$PATH"
	export GRKA_JQ_FLAGS="-b"
	;;
*)
	PATH="$REPO_DIR/.tools:$PATH"
	;;
esac
export PATH

jqt() {
	# shellcheck disable=SC2086
	jq ${GRKA_JQ_FLAGS:-} "$@"
}

T_ROOT="$(mktemp -d)"
trap 'rm -rf "$T_ROOT"' EXIT
T="$T_ROOT/t"

export GRKA_SHARE="$GRKA_SRC"
export GRKA_ETC="$T/etc/grka"
export GRKA_RUN="$T/run"
export GRKA_LOGDIR="$T/log"
export GRKA_INITD="$T/initd"
export GRKA_PROC="$T/proc"
export MIHOMO_DIR="$T/etc/mihomo"
export MIHOMO_BIN="$T/bin/mihomo"
export MIHOMO_GZ="$T/share/mihomo.gz"
export MIHOMO_TMP="$T/run/mihomo"

env_setup() {
	rm -rf "$T"
	mkdir -p "$GRKA_ETC" "$GRKA_RUN" "$GRKA_LOGDIR" "$GRKA_INITD" "$GRKA_PROC" "$MIHOMO_DIR"
	stubs_reset
}

. "$TESTS_DIR/lib/assert.sh"
. "$TESTS_DIR/lib/stubs.sh"
```

`tests/run.sh`:

```sh
#!/bin/sh
# Запуск тестов: .tools/busybox.exe sh tests/run.sh [tests/x_test.sh ...]
cd "$(dirname "$0")/.." || exit 1
rc=0
files="$*"
[ -n "$files" ] || files="$(ls tests/*_test.sh)"
for f in $files; do
	echo "== $f"
	sh "$f" || rc=1
done
[ $rc -eq 0 ] && echo "ВСЕ ТЕСТЫ ПРОШЛИ" || echo "ЕСТЬ ПРОВАЛЕННЫЕ ТЕСТЫ"
exit $rc
```

- [ ] **Step 3: Заглушки с состоянием**

`tests/lib/stubs.sh`:

```sh
# shellcheck shell=sh
# Заглушки системных команд. Состояние хранится в файлах $STUB, все вызовы пишутся в $STUB/calls.
# Формат вывода повторяет iproute2 4.4 и iptables 1.4: "99:<TAB>from all fwmark 0x1 lookup 1001".

stubs_reset() {
	STUB="$T/stub"
	rm -rf "$STUB"
	mkdir -p "$STUB/links" "$STUB/curl"
	: > "$STUB/calls"
	: > "$STUB/rules4"
	: > "$STUB/rules6"
	echo "PREROUTING INPUT OUTPUT POSTROUTING" > "$STUB/ipt.nat.builtin"
	echo "INPUT FORWARD OUTPUT" > "$STUB/ipt.filter.builtin"
	echo "PREROUTING INPUT FORWARD OUTPUT POSTROUTING" > "$STUB/ipt.mangle.builtin"
	for _sc in PREROUTING INPUT OUTPUT POSTROUTING; do : > "$STUB/ipt.nat.$_sc"; done
	for _sc in INPUT FORWARD OUTPUT; do : > "$STUB/ipt.filter.$_sc"; done
}

# ---------- ip ----------

stub_rule_text() {
	# $1 from, $2 to, $3 mark, $4 table, $5 действие (prohibit и т.п.)
	_st="from $1"
	[ -z "$2" ] || _st="$_st to $2"
	[ -z "$3" ] || _st="$_st fwmark $3"
	if [ -n "$5" ]; then _st="$_st $5"; else _st="$_st lookup $4"; fi
	printf '%s' "$_st"
}

ip() {
	echo "ip $*" >> "$STUB/calls"
	_fam=4
	if [ "$1" = "-6" ]; then
		_fam=6
		shift
	fi
	_obj="$1"
	shift
	case "$_obj" in
	rule) stub_ip_rule "$_fam" "$@" ;;
	route) stub_ip_route "$@" ;;
	link)
		if [ "$1" = show ] && [ -e "$STUB/links/$2" ]; then
			echo "7: $2: <POINTOPOINT,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN"
			return 0
		fi
		return 1
		;;
	*) return 1 ;;
	esac
}

stub_ip_rule() {
	_rf="$STUB/rules$1"
	shift
	_cmd="${1:-show}"
	[ $# -gt 0 ] && shift
	_from=all _to="" _mark="" _table="" _pref="" _act=""
	while [ $# -gt 0 ]; do
		case "$1" in
		from) _from="$2"; shift ;;
		to) _to="$2"; shift ;;
		fwmark) _mark="$2"; shift ;;
		lookup | table) _table="$2"; shift ;;
		pref | priority) _pref="$2"; shift ;;
		prohibit | unreachable | blackhole) _act="$1" ;;
		esac
		shift
	done
	case "$_cmd" in
	show | list)
		sort -s -n -k1,1 "$_rf" | awk -F '\t' '{ print $1 ":\t" $2 }'
		;;
	add)
		printf '%s\t%s\n' "${_pref:-32000}" "$(stub_rule_text "$_from" "$_to" "$_mark" "$_table" "$_act")" >> "$_rf"
		;;
	del)
		_full=""
		[ -z "$_table$_act" ] || _full="$(stub_rule_text "$_from" "$_to" "$_mark" "$_table" "$_act")"
		awk -F '\t' -v p="$_pref" -v w="$_full" '
			!done && (p == "" || $1 == p) && (w == "" || $2 == w) { done = 1; next }
			{ print }
			END { exit(done ? 0 : 1) }' "$_rf" > "$_rf.n"
		_dr=$?
		mv -f "$_rf.n" "$_rf"
		[ $_dr -eq 0 ] || return 2
		;;
	esac
}

stub_ip_route() {
	_cmd="$1"
	shift
	_type="" _dst="" _dev="" _metric="" _table="main"
	while [ $# -gt 0 ]; do
		case "$1" in
		unreachable | blackhole | prohibit | throw) _type="$1" ;;
		dev) _dev="$2"; shift ;;
		metric) _metric="$2"; shift ;;
		table) _table="$2"; shift ;;
		*) [ -n "$_dst" ] || _dst="$1" ;;
		esac
		shift
	done
	_rtf="$STUB/route.$_table"
	touch "$_rtf"
	case "$_cmd" in
	show) cat "$_rtf" ;;
	flush) : > "$_rtf" ;;
	replace | add)
		if [ -n "$_type" ]; then
			_line="$_type $_dst"
		else
			[ -e "$STUB/links/$_dev" ] || return 2
			_line="$_dst dev $_dev scope link"
		fi
		[ -z "$_metric" ] || _line="$_line metric $_metric"
		awk -v k="$_dst|${_metric:-0}" '{
			d = ($1 ~ /^(unreachable|blackhole|prohibit|throw)$/) ? $2 : $1
			m = 0
			for (i = 1; i <= NF; i++) if ($i == "metric") m = $(i + 1)
			if (d "|" m != k) print
		}' "$_rtf" > "$_rtf.n"
		echo "$_line" >> "$_rtf.n"
		mv -f "$_rtf.n" "$_rtf"
		;;
	esac
}

stub_link_up() {
	: > "$STUB/links/$1"
}

# Как в ядре: при удалении интерфейса пропадают все маршруты через него
stub_link_down() {
	rm -f "$STUB/links/$1"
	for _lf in "$STUB"/route.*; do
		[ -f "$_lf" ] || continue
		grep -v " dev $1 " "$_lf" > "$_lf.n"
		mv -f "$_lf.n" "$_lf"
	done
}

# ---------- iptables ----------

iptables() {
	echo "iptables $*" >> "$STUB/calls"
	_it=filter
	while [ $# -gt 0 ]; do
		case "$1" in
		-w) shift ;;
		-t) _it="$2"; shift 2 ;;
		*) break ;;
		esac
	done
	_op="$1"
	_ch="${2:-}"
	shift
	[ $# -gt 0 ] && shift
	_if="$STUB/ipt.$_it.$_ch"
	case "$_op" in
	-N)
		[ ! -e "$_if" ] || return 1
		: > "$_if"
		;;
	-F)
		[ -e "$_if" ] || return 1
		: > "$_if"
		;;
	-X)
		[ -e "$_if" ] || return 1
		grep -qw -- "$_ch" "$STUB/ipt.$_it.builtin" && return 1
		rm -f "$_if"
		;;
	-A)
		[ -e "$_if" ] || return 1
		echo "-A $_ch $*" >> "$_if"
		;;
	-I)
		[ -e "$_if" ] || return 1
		_pos=1
		case "${1:-}" in [0-9]*) _pos="$1"; shift ;; esac
		awk -v p="$_pos" -v l="-A $_ch $*" 'NR == p { print l; ins = 1 } { print } END { if (!ins) print l }' "$_if" > "$_if.n"
		mv -f "$_if.n" "$_if"
		;;
	-D)
		[ -e "$_if" ] || return 1
		grep -qxF -- "-A $_ch $*" "$_if" || return 1
		awk -v l="-A $_ch $*" '!d && $0 == l { d = 1; next } { print }' "$_if" > "$_if.n"
		mv -f "$_if.n" "$_if"
		;;
	-C)
		[ -e "$_if" ] || return 1
		grep -qxF -- "-A $_ch $*" "$_if"
		;;
	-S)
		[ -e "$_if" ] || return 1
		if grep -qw -- "$_ch" "$STUB/ipt.$_it.builtin"; then echo "-P $_ch ACCEPT"; else echo "-N $_ch"; fi
		cat "$_if"
		;;
	*) return 1 ;;
	esac
}

# ---------- curl ----------
# Ответ задаётся по пути URL после хоста: rci/show/ip/policy -> $STUB/curl/rci_show_ip_policy.{code,body,seq}
# .seq — построчно "код [файл_тела]" на каждый вызов; код 000 — нет соединения

stub_curl_key() {
	printf '%s' "$1" | tr '/?&=' '____'
}

curl() {
	echo "curl $*" >> "$STUB/calls"
	_co="" _cw="" _cu=""
	while [ $# -gt 0 ]; do
		case "$1" in
		-o) _co="$2"; shift ;;
		-w) _cw="$2"; shift ;;
		-H | -m | --connect-timeout | -A | --retry) shift ;;
		-*) ;;
		*) _cu="$1" ;;
		esac
		shift
	done
	_ck="$(stub_curl_key "${_cu#*://*/}")"
	_code=000
	_cb="$STUB/curl/$_ck.body"
	if [ -s "$STUB/curl/$_ck.seq" ]; then
		_cl="$(head -n 1 "$STUB/curl/$_ck.seq")"
		sed -i 1d "$STUB/curl/$_ck.seq"
		_code="${_cl%% *}"
		[ "$_cl" = "$_code" ] || _cb="${_cl#* }"
	elif [ -f "$STUB/curl/$_ck.code" ]; then
		_code="$(cat "$STUB/curl/$_ck.code")"
	fi
	if [ "$_code" != 000 ] && [ -f "$_cb" ]; then
		if [ -n "$_co" ]; then cat "$_cb" > "$_co"; else cat "$_cb"; fi
	fi
	[ -z "$_cw" ] || printf '%s' "$_code"
	[ "$_code" != 000 ]
}

stub_rci() {
	# $1 - путь RCI (show/ip/policy), $2 - HTTP-код, $3 - файл тела (необязательно)
	_ck="$(stub_curl_key "rci/$1")"
	echo "$2" > "$STUB/curl/$_ck.code"
	[ -z "${3:-}" ] || cp "$3" "$STUB/curl/$_ck.body"
}

stub_rci_seq() {
	# $1 - путь RCI, дальше по одному аргументу на вызов: "код [файл_тела]"
	_ck="$(stub_curl_key "rci/$1")"
	shift
	printf '%s\n' "$@" > "$STUB/curl/$_ck.seq"
}
```

- [ ] **Step 4: Тест каркаса**

`tests/harness_test.sh`:

```sh
#!/bin/sh
# Проверка тестового каркаса, заглушек и инструментов
. "$(dirname "$0")/lib/env.sh"

test_jq_keeps_quotes_slashes_and_cyrillic() {
	_out="$(jqt -n -r --arg s 'Мой "VPN" / & x' '$s | ascii_downcase')"
	assert_eq 'Мой "vpn" / & x' "$_out"
}

test_kill_0_on_self_works() {
	kill -0 $$ || fail "kill -0 \$\$ не работает в этой оболочке"
	assert_eq 1 1
}

test_ip_stub_add_show_del() {
	ip rule add pref 99 fwmark 0xffffaab lookup 1001
	assert_eq "$(printf '99:\tfrom all fwmark 0xffffaab lookup 1001')" "$(ip rule show)"
	ip rule del pref 99 fwmark 0xffffaab lookup 1001 || fail "del вернул ошибку"
	assert_eq "" "$(ip rule show)"
	if ip rule del pref 99; then fail "повторный del должен вернуть ошибку"; fi
}

test_ip_stub_routes_follow_link() {
	ip route replace unreachable default metric 4294967295 table 1001
	if ip route replace default dev grka-tun table 1001; then fail "маршрут через несуществующий интерфейс"; fi
	stub_link_up grka-tun
	ip route replace default dev grka-tun table 1001
	assert_eq "$(printf 'unreachable default metric 4294967295\ndefault dev grka-tun scope link')" "$(ip route show table 1001)"
	stub_link_down grka-tun
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
}

test_iptables_stub_chain_ops() {
	iptables -w -t nat -N GRKA_DNS
	iptables -w -t nat -A GRKA_DNS -s 1.2.3.4/32 -p udp --dport 53 -j REDIRECT --to-ports 1053
	iptables -w -t nat -I PREROUTING 1 -j GRKA_DNS
	assert_eq "$(printf '%s\n%s' '-N GRKA_DNS' '-A GRKA_DNS -s 1.2.3.4/32 -p udp --dport 53 -j REDIRECT --to-ports 1053')" "$(iptables -t nat -S GRKA_DNS)"
	iptables -t nat -C PREROUTING -j GRKA_DNS || fail "-C не нашёл правило"
	assert_eq "-P PREROUTING ACCEPT" "$(iptables -t nat -S PREROUTING | head -n 1)"
}

test_curl_stub_codes_and_seq() {
	echo '{"a":1}' > "$T/body.json"
	stub_rci show/version 200 "$T/body.json"
	assert_eq 200 "$(curl -s -o "$T/out" -w '%{http_code}' http://127.0.0.1:79/rci/show/version)"
	assert_eq '{"a":1}' "$(cat "$T/out")"
	stub_rci_seq show/ip/policy 000 "200 $T/body.json"
	assert_eq 000 "$(curl -s -o "$T/o2" -w '%{http_code}' http://127.0.0.1:79/rci/show/ip/policy)"
	assert_eq 200 "$(curl -s -o "$T/o3" -w '%{http_code}' http://127.0.0.1:79/rci/show/ip/policy)"
}

run_tests "$0"
```

- [ ] **Step 5: Запустить**

Run: `.tools/busybox.exe sh tests/run.sh`
Expected: `6 passed, 0 failed`, `ВСЕ ТЕСТЫ ПРОШЛИ`. Если `test_kill_0_on_self_works` падает — в busybox-w32 нет `kill -0` для своих процессов; тогда в Task 11 вместо `$$` использовать подменённую `pid_alive` (см. там же).

- [ ] **Step 6: Commit**

```bash
git add dev/get-tools.sh tests/ .gitignore
git commit -m "Тестовый каркас: busybox-w32, jq, shellcheck, заглушки ip/iptables/curl"
```

---

### Task 2: Общая библиотека `lib/common.sh`

**Files:**
- Create: `rootfs/opt/share/grka/lib/common.sh`
- Modify: `rootfs/opt/share/grka/scripts/common.sh` (становится прокладкой)
- Test: `tests/common_test.sh`

**Interfaces:**
- Produces: переменные путей (`GRKA_SHARE`, `GRKA_ETC`, `GRKA_RUN`, `GRKA_LOGDIR`, `GRKA_INITD`, `GRKA_PROC`, `MIHOMO_DIR`, `SETTINGS_FILE`, `STATE_FILE`, `CACHE_DIR`, `JOURNAL_FILE`, `STATUS_FILE`, `HOSTS_FILE`, `DIRTY_FLAG`, `CORE_LOG`, `TASK_LOG`, `TASK_LOCK`, `JOURNAL_MAX`, `CORE_LOG_MAX`, `GRKA_REPO`, `MIHOMO_REPO`, `DASHBOARD_URL`); функции `jqc`, `now_ts`, `journal уровень текст`, `write_atomic файл` (stdin), `flag_set имя`, `flag_take имя`, `lock_acquire имя`, `lock_release имя`, `pid_alive pid [шаблон]`, `spawn_bg лог команда...` (→ `SPAWN_PID`), `detach` (= spawn_bg), `fetch url`, `download url файл`, `latest_tag repo`, `mihomo_arch`.

- [ ] **Step 1: Тест**

`tests/common_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"

test_paths_follow_environment() {
	assert_eq "$T/etc/grka/settings.json" "$SETTINGS_FILE"
	assert_eq "$T/run/status.json" "$STATUS_FILE"
	assert_eq "$T/log/journal.log" "$JOURNAL_FILE"
}

test_write_atomic_replaces_content() {
	echo old > "$T/f"
	echo new | write_atomic "$T/f"
	assert_eq new "$(cat "$T/f")"
	assert_eq "" "$(ls "$T" | grep tmp)"
}

test_write_atomic_refuses_empty_input() {
	echo old > "$T/f"
	if printf '' | write_atomic "$T/f"; then fail "пустой ввод должен вернуть ошибку"; fi
	assert_eq old "$(cat "$T/f")"
}

test_journal_line_format() {
	journal info "Политика найдена"
	assert_contains "$(cat "$JOURNAL_FILE")" "|info|Политика найдена"
}

test_journal_flattens_newlines_and_pipes() {
	journal warn "$(printf 'a|b\nc')"
	assert_eq 1 "$(wc -l < "$JOURNAL_FILE" | tr -d ' ')"
	assert_contains "$(cat "$JOURNAL_FILE")" "|warn|a b c"
}

test_journal_rotates_over_limit() {
	JOURNAL_MAX=50
	journal info "1234567890123456789012345678901234567890"
	journal info "второй"
	journal info "третий"
	assert_file_exists "$JOURNAL_FILE.old"
	assert_contains "$(cat "$JOURNAL_FILE")" "третий"
}

test_flags() {
	if flag_take dirty; then fail "флага ещё нет"; fi
	flag_set dirty
	flag_take dirty || fail "флаг должен быть"
	assert_file_missing "$GRKA_RUN/dirty"
}

test_lock_twice_fails_then_release() {
	lock_acquire config || fail "первый захват"
	if lock_acquire config; then fail "второй захват должен провалиться"; fi
	lock_release config
	lock_acquire config || fail "захват после освобождения"
	assert_file_exists "$GRKA_RUN/config.lock/pid"
}

test_stale_lock_is_taken() {
	mkdir -p "$GRKA_RUN/config.lock"
	echo 99999999 > "$GRKA_RUN/config.lock/pid"
	lock_acquire config || fail "протухшая блокировка не снята"
	assert_eq "$$" "$(cat "$GRKA_RUN/config.lock/pid")"
}

test_pid_alive_checks_cmdline() {
	mkdir -p "$GRKA_PROC/$$"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/$$/cmdline"
	pid_alive $$ grka-watchdog || fail "свой процесс с подходящей строкой"
	if pid_alive $$ mihomo; then fail "строка не совпадает"; fi
	if pid_alive ""; then fail "пустой PID"; fi
	assert_eq 1 1
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/common_test.sh`
Expected: FAIL — `lib/common.sh: not found`.

- [ ] **Step 3: Implementation**

`rootfs/opt/share/grka/lib/common.sh`:

```sh
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

# Событие в журнал. $1 - info|warn|error, $2 - текст (переводы строк и | заменяются пробелами)
journal() {
	mkdir -p "$GRKA_LOGDIR"
	if [ -f "$JOURNAL_FILE" ] && [ "$(wc -c < "$JOURNAL_FILE")" -gt "$JOURNAL_MAX" ]; then
		mv -f "$JOURNAL_FILE" "$JOURNAL_FILE.old"
	fi
	printf '%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$(printf '%s' "$2" | tr '\n|' '  ')" >> "$JOURNAL_FILE"
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
```

`rootfs/opt/share/grka/scripts/common.sh` (полностью заменить):

```sh
# shellcheck shell=sh
# Совместимость: общие функции переехали в lib/common.sh
. "${GRKA_SHARE:-/opt/share/grka}/lib/common.sh"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/common_test.sh`
Expected: `10 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/share/grka/lib/common.sh rootfs/opt/share/grka/scripts/common.sh tests/common_test.sh
git commit -m "lib/common.sh: пути с переопределением, журнал, атомарная запись, флаги, блокировки"
```

---

### Task 3: Настройки и состояние `lib/settings.sh`

**Files:**
- Create: `rootfs/opt/share/grka/lib/settings.sh`
- Test: `tests/settings_test.sh`

**Interfaces:**
- Consumes: `jqc`, `write_atomic`, `lock_acquire`, `lock_release` (Task 2).
- Produces: `SETTINGS_DEFAULTS`, `STATE_DEFAULTS`, `json_init файл json`, `settings_init`, `state_init`, `json_get файл путь_jq`, `settings_get ключ`, `state_get ключ`, `json_set файл путь_jq значение_json`, `settings_set ключ значение_json`, `state_set ключ значение_json`, `json_str строка`, `policy_name_valid имя`, `mac_normalize mac`, `state_set_device mac gaming|regular`. Ключи — путь без точки впереди: `policy_name`, `expert.mihomo`.

- [ ] **Step 1: Тест**

`tests/settings_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"

test_settings_init_creates_defaults() {
	settings_init
	assert_eq GrKa "$(settings_get policy_name)"
	assert_eq 1100 "$(settings_get panel_port)"
	assert_eq true "$(settings_get autostart)"
	assert_eq 1053 "$(settings_get dns_port)"
}

test_settings_init_keeps_values_and_adds_missing() {
	echo '{"policy_name":"Дом","panel_port":2000}' > "$SETTINGS_FILE"
	settings_init
	assert_eq "Дом" "$(settings_get policy_name)"
	assert_eq 2000 "$(settings_get panel_port)"
	assert_eq true "$(settings_get ipv6_block)"
}

test_settings_init_moves_broken_file() {
	echo 'это не json' > "$SETTINGS_FILE"
	settings_init
	assert_file_exists "$SETTINGS_FILE.broken"
	assert_eq GrKa "$(settings_get policy_name)"
}

test_settings_set_cyrillic_name_with_quotes() {
	settings_init
	_name='Мой "VPN" / & '\''дом'\'''
	settings_set policy_name "$(json_str "$_name")"
	assert_eq "$_name" "$(settings_get policy_name)"
}

test_json_get_prints_false() {
	state_init
	assert_eq false "$(state_get paused)"
	state_set paused true
	assert_eq true "$(state_get paused)"
}

test_json_get_missing_key_is_empty() {
	settings_init
	assert_eq "" "$(settings_get nonexistent)"
}

test_state_set_device_gaming_and_back() {
	state_init
	state_set_device AA:BB:CC:00:00:01 gaming || fail "gaming"
	assert_eq gaming "$(state_get 'devices["aa:bb:cc:00:00:01"].type')"
	state_set_device aa:bb:cc:00:00:01 regular || fail "regular"
	assert_eq "{}" "$(jqt -c .devices "$STATE_FILE")"
}

test_state_set_device_rejects_garbage() {
	state_init
	if state_set_device 'aa:bb"; rm -rf /' gaming; then fail "мусорный MAC принят"; fi
	if state_set_device aa:bb:cc:00:00:01 weird; then fail "неизвестный тип принят"; fi
	assert_eq "{}" "$(jqt -c .devices "$STATE_FILE")"
}

test_policy_name_valid() {
	policy_name_valid "GrKa" || fail "GrKa"
	policy_name_valid "Мой VPN" || fail "кириллица"
	if policy_name_valid ""; then fail "пустое"; fi
	if policy_name_valid "$(printf 'a\tb')"; then fail "управляющий символ"; fi
	if policy_name_valid "$(printf '%065d' 0)"; then fail "65 символов"; fi
	assert_eq 1 1
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/settings_test.sh`
Expected: FAIL — `lib/settings.sh: not found`.

- [ ] **Step 3: Implementation**

`rootfs/opt/share/grka/lib/settings.sh`:

```sh
# shellcheck shell=sh
# Настройки панели (settings.json) и выбор пользователя (state.json).
# Запись атомарная и под блокировкой "config": CGI, CLI и сторож могут писать одновременно.

SETTINGS_DEFAULTS='{"schema":1,"policy_name":"GrKa","rci_token":"","panel_port":1100,"autostart":true,"core":"mihomo","expert":{"mihomo":"","xray":""},"log_level":"warning","ipv6_block":true,"dns_port":1053}'
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

# MAC -> нижний регистр. Неверный MAC -> код 1
mac_normalize() {
	_mn="$(printf '%s' "$1" | tr 'A-F' 'a-f')"
	printf '%s' "$_mn" | grep -qE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || return 1
	printf '%s\n' "$_mn"
}

# Тип устройства. $1 - MAC, $2 - gaming|regular (regular удаляет запись)
state_set_device() {
	_dm="$(mac_normalize "$1")" || return 1
	case "$2" in
	gaming)
		json_set "$STATE_FILE" ".devices[\"$_dm\"]" '{"type":"gaming"}'
		;;
	regular)
		lock_acquire config || { sleep 1; lock_acquire config; } || return 1
		jqc --arg m "$_dm" 'del(.devices[$m])' "$STATE_FILE" | write_atomic "$STATE_FILE"
		_jr=$?
		lock_release config
		return $_jr
		;;
	*)
		return 1
		;;
	esac
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/settings_test.sh`
Expected: `9 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/share/grka/lib/settings.sh tests/settings_test.sh
git commit -m "lib/settings.sh: settings.json и state.json с атомарной записью и проверкой ввода"
```

---

### Task 4: Клиент RCI `lib/rci.sh`

**Files:**
- Create: `rootfs/opt/share/grka/lib/rci.sh`
- Create: `tests/fixtures/policy.json`, `tests/fixtures/hotspot.json`
- Test: `tests/rci_test.sh`

**Interfaces:**
- Consumes: `settings_get` (Task 3), `jqc` (Task 2).
- Produces: `RCI_URL`, `rci_get путь` (stdout — ответ; код 0 — ок, 2 — нужен токен, 1 — недоступен), `mark_normalize значение` (→ `0x…`, код 1 при мусоре), `rci_policy_lookup имя` (→ `"<id> <метка>"`; коды как у `rci_get`, плюс 3 — нет политики), `rci_policy_hosts id` (→ JSON-массив `[{mac, ip, name, active}]`).

- [ ] **Step 1: Фикстуры**

`tests/fixtures/policy.json`:

```json
{"Policy0":{"description":"GrKa","mark":"ffffaab","table":42},"Policy1":{"description":"Дети","mark":"0xffffaac","table":43}}
```

`tests/fixtures/hotspot.json`:

```json
{"host":[
 {"mac":"AA:BB:CC:00:00:01","ip":"192.168.1.90","name":"PlayStation 5","policy":"Policy0","active":true},
 {"mac":"aa:bb:cc:00:00:02","ip":"192.168.1.37","name":"","hostname":"macbook","policy":"Policy0","link":"up"},
 {"mac":"aa:bb:cc:00:00:03","ip":"","name":"Телевизор","policy":"Policy0","active":false},
 {"mac":"aa:bb:cc:00:00:04","ip":"192.168.1.50","name":"Чужой","policy":"Policy1","active":true},
 {"mac":"aa:bb:cc:00:00:05","ip":"999.1.1.1x","name":"Битый","policy":"Policy0","active":true}
]}
```

- [ ] **Step 2: Тест**

`tests/rci_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"
. "$GRKA_SRC/lib/rci.sh"

test_rci_get_ok_returns_body() {
	settings_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	_out="$(rci_get show/ip/policy)"
	assert_eq 0 "$?"
	assert_contains "$_out" '"Policy0"'
}

test_rci_get_sends_token_only_when_set() {
	settings_init
	stub_rci show/version 200 "$FIXTURES/policy.json"
	rci_get show/version >/dev/null
	assert_not_contains "$(cat "$STUB/calls")" "X-Ndma-Tkn"
	settings_set rci_token '"abc123"'
	rci_get show/version >/dev/null
	assert_contains "$(cat "$STUB/calls")" "-H X-Ndma-Tkn: abc123"
}

test_rci_get_401_returns_2() {
	settings_init
	stub_rci show/ip/policy 401
	rci_get show/ip/policy >/dev/null
	assert_eq 2 "$?"
}

test_rci_get_unreachable_returns_1() {
	settings_init
	rci_get show/ip/policy >/dev/null
	assert_eq 1 "$?"
}

test_mark_normalize_variants() {
	assert_eq 0xffffaab "$(mark_normalize ffffaab)"
	assert_eq 0xffffaab "$(mark_normalize 0xFFFFAAB)"
	assert_eq 0xffffaab "$(mark_normalize 268434091)"
	if mark_normalize "0xZZ" >/dev/null; then fail "мусор принят"; fi
	if mark_normalize "" >/dev/null; then fail "пусто принято"; fi
	if mark_normalize "null" >/dev/null; then fail "null принят"; fi
}

test_policy_lookup_found_case_insensitive() {
	settings_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	assert_eq "Policy0 0xffffaab" "$(rci_policy_lookup grka)"
}

test_policy_lookup_cyrillic_name() {
	settings_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	assert_eq "Policy1 0xffffaac" "$(rci_policy_lookup "Дети")"
}

test_policy_lookup_missing_returns_3() {
	settings_init
	echo '{}' > "$T/empty.json"
	stub_rci show/ip/policy 200 "$T/empty.json"
	rci_policy_lookup GrKa >/dev/null
	assert_eq 3 "$?"
}

test_policy_lookup_passes_auth_code() {
	settings_init
	stub_rci show/ip/policy 403
	rci_policy_lookup GrKa >/dev/null
	assert_eq 2 "$?"
}

test_policy_hosts_filters_and_normalizes() {
	settings_init
	stub_rci show/ip/hotspot 200 "$FIXTURES/hotspot.json"
	_h="$(rci_policy_hosts Policy0)"
	assert_eq 4 "$(printf '%s' "$_h" | jqt 'length')"
	assert_eq "aa:bb:cc:00:00:01" "$(printf '%s' "$_h" | jqt -r '.[0].mac')"
	assert_eq "macbook" "$(printf '%s' "$_h" | jqt -r '.[1].name')"
	assert_eq true "$(printf '%s' "$_h" | jqt -r '.[1].active')"
	assert_eq "" "$(printf '%s' "$_h" | jqt -r '.[3].ip')"
}

run_tests "$0"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/rci_test.sh`
Expected: FAIL — `lib/rci.sh: not found`.

- [ ] **Step 4: Implementation**

`rootfs/opt/share/grka/lib/rci.sh`:

```sh
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
		    ip: ((.ip // "") | if test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$") then . else "" end),
		    name: (([.name, .hostname, .mac] | map(select(. != null and . != "")) | first) // ""),
		    active: (if has("active") then ((.active | tostring) as $a | $a == "true" or $a == "yes" or $a == "1")
		             else ((.link // "") == "up") end)}]'
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/rci_test.sh`
Expected: `10 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add rootfs/opt/share/grka/lib/rci.sh tests/rci_test.sh tests/fixtures/
git commit -m "lib/rci.sh: RCI с токеном KeeneticOS 5.2, поиск политики и её устройств"
```

---

### Task 5: Маршрутизация `lib/routing.sh`

**Files:**
- Create: `rootfs/opt/share/grka/lib/routing.sh`
- Test: `tests/routing_test.sh`

**Interfaces:**
- Consumes: команда `ip` (в тестах — заглушка), `GRKA_PROC` (Task 2).
- Produces: `RT_TABLE_CAPTURE=1001`, `RT_TABLE_GAME=1002`, `RT_TUN` (задаёт вызывающий, по умолчанию `grka-tun`), `RT_FAKE_RANGE`, `RT_PRIVATE`; `rt_desired_rules метка пауза "ip ip"` (строки `pref|from|to|mark|table`), `rt_current_rules`, `rt_rules_apply метка пауза "ip ip"` (печатает `changed`, если менял), `rt_rules_flush`, `rt_tables_apply true|false` (печатает `changed`), `rt6_apply метка true|false` (печатает `changed`), `rt6_flush`, `rt_rpfilter`, `rt_clear`.

- [ ] **Step 1: Тест**

`tests/routing_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/routing.sh"

test_desired_rules_normal() {
	_w="$(rt_desired_rules 0xffffaab false "192.168.1.90 192.168.1.91")"
	assert_eq 5 "$(printf '%s\n' "$_w" | grep -c '^96|')"
	assert_contains "$_w" "96|all|192.168.0.0/16|0xffffaab|main"
	assert_contains "$_w" "97|192.168.1.90|all|0xffffaab|1002"
	assert_contains "$_w" "98|192.168.1.91|all|0xffffaab|main"
	assert_contains "$_w" "99|all|all|0xffffaab|1001"
}

test_desired_rules_paused() {
	_w="$(rt_desired_rules 0xffffaab true "192.168.1.90")"
	assert_not_contains "$_w" "|1002"
	assert_not_contains "$_w" "|1001"
	assert_contains "$_w" "99|all|all|0xffffaab|main"
}

test_current_rules_parses_real_output_and_ignores_foreign() {
	ip() {
		printf '0:\tfrom all lookup local\n96:\tfrom all to 10.0.0.0/8 fwmark 0xffffaab lookup main\n97:\tfrom 192.168.1.90 fwmark 0xffffaab lookup 1002\n98:\tfrom all fwmark 0x5 lookup 200\n99:\tfrom all fwmark 0xffffaab lookup 1001\n100:\tfrom all fwmark 0xffffaaa lookup 42\n32766:\tfrom all lookup main\n'
	}
	_c="$(rt_current_rules)"
	assert_eq "$(printf '%s\n%s\n%s' '96|all|10.0.0.0/8|0xffffaab|main' '97|192.168.1.90|all|0xffffaab|1002' '99|all|all|0xffffaab|1001')" "$_c"
}

test_rules_apply_from_empty() {
	assert_eq changed "$(rt_rules_apply 0xffffaab false "192.168.1.90")"
	assert_eq 8 "$(ip rule show | grep -c 'fwmark 0xffffaab')"
	assert_contains "$(ip rule show)" "$(printf '96:\tfrom all to 10.0.0.0/8 fwmark 0xffffaab lookup main')"
	assert_contains "$(ip rule show)" "$(printf '97:\tfrom 192.168.1.90 fwmark 0xffffaab lookup 1002')"
	assert_contains "$(ip rule show)" "$(printf '99:\tfrom all fwmark 0xffffaab lookup 1001')"
}

test_rules_apply_twice_is_noop() {
	rt_rules_apply 0xffffaab false "192.168.1.90" >/dev/null
	: > "$STUB/calls"
	assert_eq "" "$(rt_rules_apply 0xffffaab false "192.168.1.90")"
	assert_eq 0 "$(grep -cE 'rule (add|del)' "$STUB/calls")"
}

test_rules_apply_replaces_stale_mark_and_keeps_foreign() {
	ip rule add pref 99 fwmark 0xdead lookup 1001
	ip rule add pref 98 fwmark 0x5 lookup 200
	rt_rules_apply 0xffffaab false "" >/dev/null
	assert_not_contains "$(ip rule show)" "0xdead"
	assert_contains "$(ip rule show)" "fwmark 0x5 lookup 200"
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001"
}

test_rules_apply_removes_duplicates() {
	rt_rules_apply 0xffffaab false "" >/dev/null
	ip rule add pref 99 fwmark 0xffffaab lookup 1001
	rt_rules_apply 0xffffaab false "" >/dev/null
	assert_eq 1 "$(ip rule show | grep -c 'lookup 1001')"
}

test_tables_apply() {
	RT_TUN=grka-tun
	assert_eq changed "$(rt_tables_apply false)"
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
	stub_link_up grka-tun
	rt_tables_apply true >/dev/null
	assert_contains "$(ip route show table 1001)" "default dev grka-tun"
	assert_contains "$(ip route show table 1002)" "198.18.0.0/15 dev grka-tun"
	assert_eq "" "$(rt_tables_apply true)"
	stub_link_down grka-tun
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
}

test_rt6_apply_and_disable() {
	assert_eq changed "$(rt6_apply 0xffffaab true)"
	assert_eq "$(printf '99:\tfrom all fwmark 0xffffaab prohibit')" "$(ip -6 rule show)"
	assert_eq "" "$(rt6_apply 0xffffaab true)"
	assert_eq changed "$(rt6_apply 0xffffaac true)"
	assert_eq 1 "$(ip -6 rule show | grep -c prohibit)"
	assert_eq changed "$(rt6_apply 0xffffaac false)"
	assert_eq "" "$(ip -6 rule show)"
}

test_rt_clear_removes_ours_keeps_foreign() {
	RT_TUN=grka-tun
	stub_link_up grka-tun
	ip rule add pref 100 fwmark 0xffffaaa lookup 42
	rt_rules_apply 0xffffaab false "192.168.1.90" >/dev/null
	rt_tables_apply true >/dev/null
	rt6_apply 0xffffaab true >/dev/null
	rt_clear
	assert_eq "$(printf '100:\tfrom all fwmark 0xffffaaa lookup 42')" "$(ip rule show)"
	assert_eq "" "$(ip -6 rule show)"
	assert_eq "" "$(ip route show table 1001)"
	assert_eq "" "$(ip route show table 1002)"
}

test_rpfilter_sets_loose() {
	RT_TUN=grka-tun
	mkdir -p "$GRKA_PROC/sys/net/ipv4/conf/grka-tun"
	echo 1 > "$GRKA_PROC/sys/net/ipv4/conf/grka-tun/rp_filter"
	rt_rpfilter
	assert_eq 2 "$(cat "$GRKA_PROC/sys/net/ipv4/conf/grka-tun/rp_filter")"
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/routing_test.sh`
Expected: FAIL — `lib/routing.sh: not found`.

- [ ] **Step 3: Implementation**

`rootfs/opt/share/grka/lib/routing.sh`:

```sh
# shellcheck shell=sh
# Маршрутизация политики (спека §5.2). Только идемпотентные операции: сначала читаем, потом меняем.
#   pref 96: метка политики + частные сети -> main (локальные адреса не уходят в ядро)
#   pref 97: игровое устройство -> таблица 1002 (там только VPN-направления)
#   pref 98: игровое устройство -> main (всё остальное мимо ядра)
#   pref 99: метка политики -> таблица 1001 (всё в ядро); на паузе -> main
# Наши правила — pref 96–99 с lookup 1001/1002 или lookup main с fwmark. Чужие правила не трогаем.

RT_TABLE_CAPTURE=1001
RT_TABLE_GAME=1002
RT_TUN="${RT_TUN:-grka-tun}"
RT_FAKE_RANGE="198.18.0.0/15"
RT_PRIVATE="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10"

# $1 - метка, $2 - пауза (true/false), $3 - IP игровых устройств через пробел
rt_desired_rules() {
	for _rn in $RT_PRIVATE; do
		echo "96|all|$_rn|$1|main"
	done
	if [ "$2" = true ]; then
		echo "99|all|all|$1|main"
		return 0
	fi
	for _ri in $3; do
		echo "97|$_ri|all|$1|$RT_TABLE_GAME"
	done
	for _ri in $3; do
		echo "98|$_ri|all|$1|main"
	done
	echo "99|all|all|$1|$RT_TABLE_CAPTURE"
}

# Наши текущие правила в том же виде: pref|from|to|mark|table
rt_current_rules() {
	ip rule show 2>/dev/null | awk '
	{
		pref = $1
		sub(":", "", pref)
		if (pref < 96 || pref > 99) next
		from = "all"; to = "all"; mark = ""; table = ""
		for (i = 2; i <= NF; i++) {
			if ($i == "from") from = $(i + 1)
			else if ($i == "to") to = $(i + 1)
			else if ($i == "fwmark") { mark = $(i + 1); sub("/0xffffffff$", "", mark) }
			else if ($i == "lookup" || $i == "table") table = $(i + 1)
		}
		if (table == "1001" || table == "1002" || (table == "main" && mark != ""))
			print pref "|" from "|" to "|" mark "|" table
	}'
}

rt_rules_flush() {
	rt_current_rules | while IFS='|' read -r _p _f _t _m _tb; do
		set -- del pref "$_p"
		[ "$_f" = all ] || set -- "$@" from "$_f"
		[ "$_t" = all ] || set -- "$@" to "$_t"
		[ -z "$_m" ] || set -- "$@" fwmark "$_m"
		set -- "$@" lookup "$_tb"
		ip rule "$@" 2>/dev/null
	done
}

# Приводит правила к желаемым. При любом расхождении удаляет все наши и ставит заново (доли секунды)
rt_rules_apply() {
	_want="$(rt_desired_rules "$1" "$2" "$3")"
	_have="$(rt_current_rules)"
	if [ "$(printf '%s\n' "$_want" | sort)" = "$(printf '%s\n' "$_have" | sort)" ]; then
		return 0
	fi
	rt_rules_flush
	printf '%s\n' "$_want" | while IFS='|' read -r _p _f _t _m _tb; do
		[ -n "$_p" ] || continue
		set -- add pref "$_p"
		[ "$_f" = all ] || set -- "$@" from "$_f"
		[ "$_t" = all ] || set -- "$@" to "$_t"
		set -- "$@" fwmark "$_m" lookup "$_tb"
		ip rule "$@" 2>/dev/null
	done
	echo changed
}

# $1 - поднят ли TUN (true/false). unreachable в 1001 стоит всегда: без ядра нет утечки мимо VPN
rt_tables_apply() {
	_tc=""
	if ! ip route show table "$RT_TABLE_CAPTURE" 2>/dev/null | grep -q '^unreachable default'; then
		ip route replace unreachable default metric 4294967295 table "$RT_TABLE_CAPTURE" 2>/dev/null
		_tc=1
	fi
	if [ "$1" = true ]; then
		if ! ip route show table "$RT_TABLE_CAPTURE" 2>/dev/null | grep -q "^default dev $RT_TUN"; then
			ip route replace default dev "$RT_TUN" table "$RT_TABLE_CAPTURE" 2>/dev/null
			_tc=1
		fi
		if ! ip route show table "$RT_TABLE_GAME" 2>/dev/null | grep -q "^$RT_FAKE_RANGE dev $RT_TUN"; then
			ip route replace "$RT_FAKE_RANGE" dev "$RT_TUN" table "$RT_TABLE_GAME" 2>/dev/null
			_tc=1
		fi
	fi
	[ -z "$_tc" ] || echo changed
}

rt6_current_marks() {
	ip -6 rule show 2>/dev/null | awk '$1 == "99:" && /prohibit/ { for (i = 2; i <= NF; i++) if ($i == "fwmark") print $(i + 1) }'
}

rt6_flush() {
	rt6_current_marks | while read -r _m6; do
		ip -6 rule del pref 99 fwmark "$_m6" prohibit 2>/dev/null
	done
}

# IPv6 для меченого трафика запрещён: устройства политики переходят на IPv4 (спека §5.5)
# $1 - метка, $2 - блокировать ли (true/false)
rt6_apply() {
	_h6="$(rt6_current_marks)"
	if [ "$2" = true ]; then
		[ "$_h6" != "$1" ] || return 0
		rt6_flush
		ip -6 rule add pref 99 fwmark "$1" prohibit 2>/dev/null
		echo changed
	elif [ -n "$_h6" ]; then
		rt6_flush
		echo changed
	fi
}

# loose rp_filter на TUN: ответы из ядра не отбрасываются как «марсианские»
rt_rpfilter() {
	_rpf="$GRKA_PROC/sys/net/ipv4/conf/$RT_TUN/rp_filter"
	[ -w "$_rpf" ] || return 0
	[ "$(cat "$_rpf" 2>/dev/null)" = 2 ] || echo 2 > "$_rpf"
}

rt_clear() {
	rt_rules_flush
	rt6_flush
	ip route flush table "$RT_TABLE_CAPTURE" 2>/dev/null
	ip route flush table "$RT_TABLE_GAME" 2>/dev/null
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/routing_test.sh`
Expected: `11 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/share/grka/lib/routing.sh tests/routing_test.sh
git commit -m "lib/routing.sh: ip rule pref 96–99, таблицы 1001/1002, IPv6 и rp_filter идемпотентно"
```

---

### Task 6: Перенаправление DNS игровых устройств `lib/dnsredir.sh`

**Files:**
- Create: `rootfs/opt/share/grka/lib/dnsredir.sh`
- Test: `tests/dnsredir_test.sh`

**Interfaces:**
- Consumes: команда `iptables` (в тестах — заглушка).
- Produces: `DNS_CHAIN=GRKA_DNS`, `ipt` (= `iptables -w`), `dns_desired_lines "ip ip" порт`, `dns_current_lines`, `dns_apply "ip ip" порт` (печатает `changed`; пустой список снимает всё), `dns_unjump`, `dns_clear` (печатает `changed`, если было что снимать).

- [ ] **Step 1: Тест**

`tests/dnsredir_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/dnsredir.sh"

test_dns_apply_creates_chain_and_one_jump() {
	assert_eq changed "$(dns_apply "192.168.1.90" 1053)"
	assert_eq 2 "$(iptables -t nat -S GRKA_DNS | grep -c -- '^-A')"
	assert_eq 1 "$(iptables -t nat -S PREROUTING | grep -c -- '-j GRKA_DNS$')"
	assert_eq "-A PREROUTING -j GRKA_DNS" "$(iptables -t nat -S PREROUTING | sed -n 2p)"
}

test_dns_apply_twice_noop() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	: > "$STUB/calls"
	assert_eq "" "$(dns_apply "192.168.1.90" 1053)"
	assert_eq 0 "$(grep -cE -- ' -(A|I|D|F|X) ' "$STUB/calls")"
}

test_dns_apply_rebuilds_on_ip_change() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_eq changed "$(dns_apply "192.168.1.91" 1053)"
	assert_not_contains "$(iptables -t nat -S GRKA_DNS)" "192.168.1.90"
	assert_contains "$(iptables -t nat -S GRKA_DNS)" "-s 192.168.1.91/32 -p tcp --dport 53"
}

test_dns_apply_rebuilds_on_port_change() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_eq changed "$(dns_apply "192.168.1.90" 5353)"
	assert_contains "$(iptables -t nat -S GRKA_DNS)" "--to-ports 5353"
	assert_not_contains "$(iptables -t nat -S GRKA_DNS)" "--to-ports 1053"
}

test_dns_apply_replaces_0_0_2_marked_jump() {
	iptables -t nat -N GRKA_DNS
	iptables -t nat -I PREROUTING 1 -m mark --mark 0xffffaab -j GRKA_DNS
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_not_contains "$(iptables -t nat -S PREROUTING)" "--mark"
	assert_eq 1 "$(iptables -t nat -S PREROUTING | grep -c -- '-j GRKA_DNS$')"
}

test_dns_apply_empty_clears() {
	dns_apply "192.168.1.90" 1053 >/dev/null
	assert_eq changed "$(dns_apply "" 1053)"
	assert_eq "" "$(iptables -t nat -S GRKA_DNS 2>/dev/null)"
	assert_eq 0 "$(iptables -t nat -S PREROUTING | grep -c GRKA_DNS)"
	assert_eq "" "$(dns_clear)"
}

test_dns_current_lines_strips_match_modules() {
	iptables() {
		[ "$*" = "-w -t nat -S GRKA_DNS" ] || return 1
		printf '%s\n' '-N GRKA_DNS' '-A GRKA_DNS -s 192.168.1.90/32 -p udp -m udp --dport 53 -j REDIRECT --to-ports 1053'
	}
	assert_eq "-A GRKA_DNS -s 192.168.1.90/32 -p udp --dport 53 -j REDIRECT --to-ports 1053" "$(dns_current_lines)"
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/dnsredir_test.sh`
Expected: FAIL — `lib/dnsredir.sh: not found`.

- [ ] **Step 3: Implementation**

`rootfs/opt/share/grka/lib/dnsredir.sh`:

```sh
# shellcheck shell=sh
# DNS игровых устройств -> DNS ядра (спека §5.3). Обычные устройства не трогаем: их DNS идёт через DoT/DoH роутера.
# Цепочка nat GRKA_DNS: по два правила (udp и tcp) на IP; один переход из PREROUTING, первым.

DNS_CHAIN="GRKA_DNS"

ipt() {
	iptables -w "$@"
}

# $1 - IP через пробел, $2 - порт DNS ядра
dns_desired_lines() {
	for _di in $1; do
		printf '%s\n' "-A $DNS_CHAIN -s $_di/32 -p udp --dport 53 -j REDIRECT --to-ports $2"
		printf '%s\n' "-A $DNS_CHAIN -s $_di/32 -p tcp --dport 53 -j REDIRECT --to-ports $2"
	done
}

# Текущие правила цепочки; настоящий iptables -S добавляет "-m udp"/"-m tcp", их убираем
dns_current_lines() {
	ipt -t nat -S "$DNS_CHAIN" 2>/dev/null | grep -- '^-A ' | sed 's/ -m udp//; s/ -m tcp//'
}

# Убирает все переходы в GRKA_DNS из PREROUTING (включая старый вариант 0.0.2 с -m mark)
dns_unjump() {
	ipt -t nat -S PREROUTING 2>/dev/null | grep -- "-j $DNS_CHAIN\$" | sed 's/^-A PREROUTING //' | while read -r _dr; do
		# shellcheck disable=SC2086
		ipt -t nat -D PREROUTING $_dr 2>/dev/null
	done
}

dns_clear() {
	_dhad="$(ipt -t nat -S "$DNS_CHAIN" 2>/dev/null)$(ipt -t nat -S PREROUTING 2>/dev/null | grep -- "-j $DNS_CHAIN\$")"
	dns_unjump
	ipt -t nat -F "$DNS_CHAIN" 2>/dev/null
	ipt -t nat -X "$DNS_CHAIN" 2>/dev/null
	[ -z "$_dhad" ] || echo changed
}

# $1 - IP через пробел (пусто — снять перенаправление), $2 - порт DNS ядра
dns_apply() {
	_dips="$(for _di in $1; do echo "$_di"; done | sort -u | tr '\n' ' ')"
	if [ -z "$_dips" ]; then
		dns_clear
		return 0
	fi
	_dch=""
	ipt -t nat -N "$DNS_CHAIN" 2>/dev/null
	if [ "$(dns_desired_lines "$_dips" "$2" | sort)" != "$(dns_current_lines | sort)" ]; then
		ipt -t nat -F "$DNS_CHAIN"
		dns_desired_lines "$_dips" "$2" | sed "s/^-A $DNS_CHAIN //" | while read -r _dr; do
			# shellcheck disable=SC2086
			ipt -t nat -A "$DNS_CHAIN" $_dr
		done
		_dch=1
	fi
	_djumps="$(ipt -t nat -S PREROUTING 2>/dev/null | grep -c -- "-j $DNS_CHAIN\$")"
	if [ "$_djumps" -ne 1 ] || ! ipt -t nat -C PREROUTING -j "$DNS_CHAIN" 2>/dev/null; then
		dns_unjump
		ipt -t nat -I PREROUTING 1 -j "$DNS_CHAIN"
		_dch=1
	fi
	[ -z "$_dch" ] || echo changed
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/dnsredir_test.sh`
Expected: `7 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/share/grka/lib/dnsredir.sh tests/dnsredir_test.sh
git commit -m "lib/dnsredir.sh: перенаправление DNS игровых устройств в ядро, идемпотентно"
```

---

### Task 7: Адаптер mihomo `lib/core-mihomo.sh` и `lib/core.sh`

**Files:**
- Create: `rootfs/opt/share/grka/lib/core-mihomo.sh`, `rootfs/opt/share/grka/lib/core.sh`
- Test: `tests/core_mihomo_test.sh`

**Interfaces:**
- Consumes: `settings_get` (Task 3), `pid_alive`, `spawn_bg`, `GRKA_PROC`, `CORE_LOG`, `CORE_LOG_MAX` (Task 2).
- Produces (одинаково для будущего адаптера Xray): `MIHOMO_BIN`, `MIHOMO_GZ`, `MIHOMO_TMP`, `COMPACT_FLAG`, `CORE_PIDFILE`; `core_name`, `core_config`, `core_config_sig`, `compact_on`, `core_ready`, `core_bin`, `ensure_core`, `core_version`, `core_validate файл` (печатает вывод; код 0 — верно, 3 — ядро не установлено, иначе — ошибка конфига), `core_pid`, `core_find_pid`, `core_running`, `core_start` (0 — запущено, 3 — нет ядра, 4 — нет конфига), `core_stop`, `core_tun`, `core_log_rotate`, `core_api_port`, `core_api_secret`.

- [ ] **Step 1: Тест**

`tests/core_mihomo_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"
. "$GRKA_SRC/lib/core.sh"

test_core_config_default_and_expert() {
	settings_init
	assert_eq "$MIHOMO_DIR/config.yaml" "$(core_config)"
	settings_set expert.mihomo '"/x/my.yaml"'
	assert_eq "/x/my.yaml" "$(core_config)"
}

test_core_tun_block_flow_and_default() {
	settings_init
	printf 'mixed-port: 7890\ntun:\n  enable: true\n  device: grka-tun\n  stack: system\ndns:\n  device: wrong\n' > "$MIHOMO_DIR/config.yaml"
	assert_eq grka-tun "$(core_tun)"
	printf 'tun: { enable: true, device: "my-tun", stack: system }\n' > "$MIHOMO_DIR/config.yaml"
	assert_eq my-tun "$(core_tun)"
	printf 'tun:\n  enable: true\nproxies: []\n' > "$MIHOMO_DIR/config.yaml"
	assert_eq Meta "$(core_tun)"
}

test_core_start_missing_binary_returns_3() {
	settings_init
	ensure_core() { echo ""; }
	core_start
	assert_eq 3 "$?"
}

test_core_start_missing_config_returns_4() {
	settings_init
	ensure_core() { echo /fake/mihomo; }
	core_start
	assert_eq 4 "$?"
}

test_core_start_spawns_with_args_and_writes_pid() {
	settings_init
	ensure_core() { echo /fake/mihomo; }
	echo 'tun: {device: grka-tun}' > "$MIHOMO_DIR/config.yaml"
	spawn_bg() { echo "$*" > "$T/spawn"; SPAWN_PID=777; }
	core_start
	assert_eq 0 "$?"
	assert_eq "$CORE_LOG /fake/mihomo -d $MIHOMO_DIR -f $MIHOMO_DIR/config.yaml" "$(cat "$T/spawn")"
	assert_eq 777 "$(cat "$CORE_PIDFILE")"
	assert_contains "$(cat "$CORE_LOG")" "[grka] запуск mihomo"
}

test_core_stop_terminates_then_kills() {
	echo 555 > "$CORE_PIDFILE"
	pid_alive() { [ "$1" = 555 ] && [ ! -f "$T/dead" ]; }
	kill() { echo "kill $*" >> "$T/kills"; [ "$1" != "-9" ] || : > "$T/dead"; return 0; }
	sleep() { :; }
	core_stop
	assert_eq "kill 555 kill -9 555" "$(tr '\n' ' ' < "$T/kills" | sed 's/ $//')"
	assert_file_missing "$CORE_PIDFILE"
}

test_core_log_rotate_copytruncate() {
	CORE_LOG_MAX=10
	printf '0123456789abcdef' > "$CORE_LOG"
	core_log_rotate
	assert_eq 0123456789abcdef "$(cat "$CORE_LOG.old")"
	assert_eq "" "$(cat "$CORE_LOG")"
}

test_core_find_pid_in_proc() {
	mkdir -p "$GRKA_PROC/1234" "$GRKA_PROC/99"
	printf '/opt/sbin/mihomo\000-d\000%s\000-f\000x.yaml\000' "$MIHOMO_DIR" > "$GRKA_PROC/1234/cmdline"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/99/cmdline"
	assert_eq 1234 "$(core_find_pid)"
}

test_core_validate_reports_not_installed() {
	ensure_core() { echo ""; }
	_o="$(core_validate x.yaml)"
	_r=$?
	assert_eq 3 "$_r"
	assert_contains "$_o" "не установлено"
}

test_core_api_port_and_secret() {
	settings_init
	printf "external-controller: 0.0.0.0:9191\nsecret: 'abc'\n" > "$MIHOMO_DIR/config.yaml"
	assert_eq 9191 "$(core_api_port)"
	assert_eq abc "$(core_api_secret)"
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/core_mihomo_test.sh`
Expected: FAIL — `lib/core.sh: not found`.

- [ ] **Step 3: Implementation**

`rootfs/opt/share/grka/lib/core-mihomo.sh`:

```sh
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

# PID нашего mihomo по /proc: командная строка содержит "mihomo" и "-d $MIHOMO_DIR"
core_find_pid() {
	for _cf in "$GRKA_PROC"/[0-9]*/cmdline; do
		[ -f "$_cf" ] || continue
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
	ulimit -n 65536 2>/dev/null
	echo "$(date '+%Y-%m-%d %H:%M:%S') [grka] запуск mihomo" >> "$CORE_LOG"
	spawn_bg "$CORE_LOG" "$_sb" -d "$MIHOMO_DIR" -f "$_sc"
	echo "$SPAWN_PID" > "$CORE_PIDFILE"
	return 0
}

# Остановка по PID (не killall: рядом может работать чужой mihomo). 10 секунд на TERM, потом KILL
core_stop() {
	_kp="$(core_pid)"
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
```

`rootfs/opt/share/grka/lib/core.sh`:

```sh
# shellcheck shell=sh
# Выбор адаптера ядра. На этапе 1 есть только mihomo; Xray добавится на этапе 2 (спека §7)
. "$GRKA_SHARE/lib/core-mihomo.sh"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/core_mihomo_test.sh`
Expected: `10 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/share/grka/lib/core-mihomo.sh rootfs/opt/share/grka/lib/core.sh tests/core_mihomo_test.sh
git commit -m "Адаптер ядра mihomo: запуск по PID-файлу, проверка конфига, TUN, ротация лога"
```

---

### Task 8: Сторож `lib/watchdog.sh` и `bin/grka-watchdog`

**Files:**
- Create: `rootfs/opt/share/grka/lib/watchdog.sh`, `rootfs/opt/share/grka/bin/grka-watchdog`
- Test: `tests/watchdog_test.sh`

**Interfaces:**
- Consumes: всё из Task 2–7.
- Produces: `wd_tick` (один проход: RCI → ядро → правила → статус), `wd_main` (бесконечный цикл с проверкой единственного экземпляра), `wd_gaming_ips`, `wd_status_write`; файлы `$STATUS_FILE` (формат ниже), `$GRKA_RUN/wd.env`, `$HOSTS_FILE`, `$CACHE_DIR/policy_mark`, `$GRKA_RUN/core.error`; флаги, которые читает: `dirty`, `rci-refresh`, `restart-core`, `hold`.

Формат `status.json` (его читают CGI и `grka status`):

```json
{"ts":1000,"state":"ok|starting|waiting_policy|paused|stopped|error","warnings":["…"],
 "core":{"name":"mihomo","running":true,"enabled":true,"pid":"123","memory_kb":"48000","error":"","error_log":""},
 "policy":{"name":"GrKa","id":"Policy0","mark":"0xffffaab","found":true,"rci":"ok|auth|nopolicy|down|init",
           "hosts":[{"mac":"…","ip":"…","name":"…","active":true,"type":"regular|gaming"}]},
 "routing":{"rules_ok":true,"tun":"grka-tun","tun_up":true,"gaming_ips":["192.168.1.90"]},
 "paused":false}
```

- [ ] **Step 1: Тест**

`tests/watchdog_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"
. "$GRKA_SRC/lib/rci.sh"
. "$GRKA_SRC/lib/routing.sh"
. "$GRKA_SRC/lib/dnsredir.sh"
. "$GRKA_SRC/lib/core.sh"
. "$GRKA_SRC/lib/watchdog.sh"

# Ядро-подделка: состояние в файлах $T, TUN появляется при старте
fake_core() {
	core_running() { [ -f "$T/core.up" ]; }
	core_start() { echo start >> "$T/core.calls"; : > "$T/core.up"; stub_link_up grka-tun; return 0; }
	core_stop() { echo stop >> "$T/core.calls"; rm -f "$T/core.up"; stub_link_down grka-tun; }
	core_validate() { if [ -f "$T/core.badcfg" ]; then echo "bad config line 3"; return 1; fi; return 0; }
	core_config_sig() { cat "$T/core.sig" 2>/dev/null; }
	core_tun() { echo grka-tun; }
	core_pid() { echo 4242; }
	sleep() { :; }
	NOW=1000
	now_ts() { echo "$NOW"; }
}

base_rci_ok() {
	settings_init
	state_init
	stub_rci show/ip/policy 200 "$FIXTURES/policy.json"
	stub_rci show/ip/hotspot 200 "$FIXTURES/hotspot.json"
}

st() {
	jqt -r "$1" "$STATUS_FILE"
}

test_tick_starts_core_and_applies_full_rules() {
	fake_core
	base_rci_ok
	wd_tick
	assert_eq start "$(cat "$T/core.calls")"
	assert_contains "$(ip route show table 1001)" "default dev grka-tun"
	assert_contains "$(ip route show table 1002)" "198.18.0.0/15 dev grka-tun"
	assert_contains "$(ip rule show)" "$(printf '99:\tfrom all fwmark 0xffffaab lookup 1001')"
	assert_eq ok "$(st .state)"
	assert_eq true "$(st .routing.tun_up)"
	assert_contains "$(cat "$JOURNAL_FILE")" "Ядро mihomo запущено"
	assert_contains "$(cat "$JOURNAL_FILE")" "Правила маршрутизации применены"
}

test_tick_policy_appears_after_boot() {
	fake_core
	settings_init
	state_init
	echo '{}' > "$T/empty.json"
	stub_rci_seq show/ip/policy "200 $T/empty.json" "200 $FIXTURES/policy.json"
	stub_rci show/ip/hotspot 200 "$FIXTURES/hotspot.json"
	wd_tick
	assert_eq waiting_policy "$(st .state)"
	assert_eq "" "$(ip rule show)"
	NOW=1002
	wd_tick
	assert_eq ok "$(st .state)"
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001"
	assert_contains "$(cat "$JOURNAL_FILE")" "попыток: 2"
}

test_tick_rci_down_uses_cached_mark() {
	fake_core
	settings_init
	state_init
	mkdir -p "$CACHE_DIR"
	echo "Policy0 0xffffaab" > "$CACHE_DIR/policy_mark"
	stub_rci show/ip/policy 000
	wd_tick
	assert_contains "$(ip rule show)" "fwmark 0xffffaab lookup 1001"
	assert_eq down "$(st .policy.rci)"
	assert_contains "$(cat "$JOURNAL_FILE")" "сохранённую метку"
}

test_tick_rci_auth_warns_about_token() {
	fake_core
	settings_init
	state_init
	stub_rci show/ip/policy 401
	wd_tick
	assert_eq auth "$(st .policy.rci)"
	assert_contains "$(st '.warnings | join(" ")')" "токен RCI"
}

test_tick_mark_change_replaces_rules() {
	fake_core
	base_rci_ok
	wd_tick
	printf '%s' '{"Policy0":{"description":"GrKa","mark":"ffffaad"}}' > "$T/policy2.json"
	stub_rci show/ip/policy 200 "$T/policy2.json"
	NOW=1061
	wd_tick
	assert_not_contains "$(ip rule show)" "0xffffaab"
	assert_contains "$(ip rule show)" "fwmark 0xffffaad lookup 1001"
	assert_contains "$(cat "$JOURNAL_FILE")" "сменилась"
}

test_tick_core_crash_backoff_and_stop() {
	fake_core
	base_rci_ok
	wd_tick
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1010; wd_tick
	assert_eq 1 "$(grep -c start "$T/core.calls")"
	NOW=1016; wd_tick
	assert_eq 2 "$(grep -c start "$T/core.calls")"
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1020; wd_tick
	NOW=1036; wd_tick
	assert_eq 3 "$(grep -c start "$T/core.calls")"
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1040; wd_tick
	NOW=1101; wd_tick
	assert_eq 4 "$(grep -c start "$T/core.calls")"
	rm -f "$T/core.up"; stub_link_down grka-tun
	NOW=1110; wd_tick
	NOW=1500; wd_tick
	assert_eq 4 "$(grep -c start "$T/core.calls")"
	assert_eq error "$(st .state)"
	assert_contains "$(cat "$JOURNAL_FILE")" "повторы остановлены"
	assert_contains "$(ip route show table 1001)" "unreachable default"
	assert_not_contains "$(ip route show table 1001)" "dev grka-tun"
}

test_tick_bad_config_no_loop_until_changed() {
	fake_core
	base_rci_ok
	: > "$T/core.badcfg"
	echo sig1 > "$T/core.sig"
	wd_tick
	NOW=1010; wd_tick
	NOW=1500; wd_tick
	assert_file_missing "$T/core.calls" "ядро не должно запускаться с битым конфигом"
	assert_eq error "$(st .state)"
	assert_contains "$(st .core.error_log)" "bad config"
	assert_eq 1 "$(grep -c 'не прошёл проверку' "$JOURNAL_FILE")"
	rm -f "$T/core.badcfg"
	echo sig2 > "$T/core.sig"
	NOW=1510; wd_tick
	assert_eq start "$(cat "$T/core.calls")"
	assert_eq ok "$(st .state)"
}

test_tick_core_not_installed_reports_once() {
	fake_core
	base_rci_ok
	core_validate() { echo "Ядро mihomo не установлено"; return 3; }
	wd_tick
	NOW=1010; wd_tick
	assert_eq error "$(st .state)"
	assert_contains "$(st .core.error)" "не установлено"
	assert_eq 1 "$(grep -c 'не установлено' "$JOURNAL_FILE")"
}

test_tick_restart_flag_restarts_core() {
	fake_core
	base_rci_ok
	wd_tick
	flag_set restart-core
	NOW=1005
	wd_tick
	assert_eq "start stop start" "$(tr '\n' ' ' < "$T/core.calls" | sed 's/ $//')"
}

test_tick_paused_routes_main_without_dns() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	state_set paused true
	wd_tick
	assert_contains "$(ip rule show)" "$(printf '99:\tfrom all fwmark 0xffffaab lookup main')"
	assert_not_contains "$(ip rule show)" "lookup 1002"
	assert_eq "" "$(iptables -t nat -S GRKA_DNS 2>/dev/null)"
	assert_eq paused "$(st .state)"
}

test_tick_gaming_ips_skip_offline_and_broken() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	state_set_device aa:bb:cc:00:00:03 gaming
	state_set_device aa:bb:cc:00:00:05 gaming
	state_set_device aa:bb:cc:00:00:04 gaming
	wd_tick
	assert_eq "192.168.1.90" "$(st '.routing.gaming_ips | join(" ")')"
	assert_contains "$(ip rule show)" "$(printf '97:\tfrom 192.168.1.90 fwmark 0xffffaab lookup 1002')"
	assert_contains "$(ip rule show)" "$(printf '98:\tfrom 192.168.1.90 fwmark 0xffffaab lookup main')"
	assert_eq 2 "$(iptables -t nat -S GRKA_DNS | grep -c -- '^-A')"
}

test_tick_disabled_stops_core_keeps_capture() {
	fake_core
	base_rci_ok
	wd_tick
	state_set enabled false
	NOW=1010
	wd_tick
	assert_contains "$(cat "$T/core.calls")" stop
	assert_contains "$(ip rule show)" "lookup 1001"
	assert_eq "unreachable default metric 4294967295" "$(ip route show table 1001)"
	assert_eq stopped "$(st .state)"
}

test_tick_hold_flag_keeps_core_off() {
	fake_core
	base_rci_ok
	flag_set hold
	wd_tick
	assert_file_missing "$T/core.calls"
	assert_eq stopped "$(st .state)"
}

test_status_hosts_have_types() {
	fake_core
	base_rci_ok
	state_set_device aa:bb:cc:00:00:01 gaming
	wd_tick
	assert_eq gaming "$(st '.policy.hosts[] | select(.mac == "aa:bb:cc:00:00:01") | .type')"
	assert_eq regular "$(st '.policy.hosts[] | select(.mac == "aa:bb:cc:00:00:02") | .type')"
	assert_eq GrKa "$(st .policy.name)"
}

test_xkeen_detected_warning() {
	fake_core
	base_rci_ok
	: > "$GRKA_INITD/S05xkeen"
	wd_tick
	assert_contains "$(st '.warnings | join(" ")')" "XKeen"
}

test_wd_main_second_instance_exits() {
	mkdir -p "$GRKA_PROC/$$"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/$$/cmdline"
	echo $$ > "$GRKA_RUN/watchdog.pid"
	assert_contains "$(wd_main)" "уже запущен"
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/watchdog_test.sh`
Expected: FAIL — `lib/watchdog.sh: not found`.

- [ ] **Step 3: Implementation**

`rootfs/opt/share/grka/lib/watchdog.sh`:

```sh
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
	WD_GAMING_IPS=""
	WD_CORE_FAILS=0
	WD_CORE_FIRST_FAIL=0
	WD_CORE_NEXT=0
	WD_CORE_UP_SINCE=""
	WD_CORE_CFG_SIG=""
	WD_APPLIED=""
	WD_RULES_OK=false
	WD_TUN_UP=false
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
		echo "WD_GAMING_IPS='$WD_GAMING_IPS'"
		echo "WD_CORE_FAILS='$WD_CORE_FAILS'"
		echo "WD_CORE_FIRST_FAIL='$WD_CORE_FIRST_FAIL'"
		echo "WD_CORE_NEXT='$WD_CORE_NEXT'"
		echo "WD_CORE_UP_SINCE='$WD_CORE_UP_SINCE'"
		echo "WD_CORE_CFG_SIG='$WD_CORE_CFG_SIG'"
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
	_res="$(rci_policy_lookup "$1")"
	_rc=$?
	case $_rc in
	0)
		_id="$(printf '%s' "${_res%% *}" | tr -cd 'A-Za-z0-9_-')"
		_mk="${_res#* }"
		if [ -n "$WD_MARK" ] && [ "$WD_MARK" != "$_mk" ]; then
			journal info "Метка политики «$1» сменилась: $WD_MARK → $_mk"
		elif [ "$_prev" != ok ]; then
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
		[ "$_prev" = nopolicy ] || journal warn "Политика «$1» не найдена в Keenetic"
		WD_RCI_STATE=nopolicy
		WD_RCI_TRIES=$((WD_RCI_TRIES + 1))
		WD_MARK=""
		WD_POLICY_ID=""
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
	WD_LAST_RCI="$(now_ts)"
}

# IP игровых устройств политики (из последнего ответа RCI), только правильные IPv4
wd_gaming_ips() {
	[ -s "$HOSTS_FILE" ] || return 0
	jqc -r --slurpfile st "$STATE_FILE" '
		($st[0].devices // {}) as $d
		| .[] | select(($d[.mac].type // "") == "gaming") | .ip
		| select(test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$"))' "$HOSTS_FILE" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ *$//'
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
		[ "$(core_config_sig)" != "$WD_CORE_CFG_SIG" ] || return 0
		journal info "Конфиг изменился, пробую запустить ядро снова"
		WD_CORE_ERROR=""
		WD_CORE_FAILS=0
		WD_CORE_NEXT=0
	fi
	[ "$2" -ge "${WD_CORE_NEXT:-0}" ] || return 0
	_vo="$(core_validate "$(core_config)")"
	_vr=$?
	if [ $_vr -ne 0 ]; then
		WD_CORE_CFG_SIG="$(core_config_sig)"
		if [ $_vr -eq 3 ]; then
			WD_CORE_ERROR="Ядро $(core_name) не установлено"
		else
			WD_CORE_ERROR="Конфиг ядра не прошёл проверку"
		fi
		printf '%s\n' "$_vo" | tail -n 5 | write_atomic "$GRKA_RUN/core.error"
		journal error "$WD_CORE_ERROR"
		return 0
	fi
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
	3)
		WD_CORE_ERROR="Ядро $(core_name) не установлено"
		WD_CORE_CFG_SIG="$(core_config_sig)"
		journal error "$WD_CORE_ERROR"
		;;
	*)
		WD_CORE_ERROR="Нет конфига ядра: $(core_config)"
		WD_CORE_CFG_SIG="$(core_config_sig)"
		journal error "$WD_CORE_ERROR"
		;;
	esac
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
	_dport="$(settings_get dns_port)"
	case "$_dport" in "" | *[!0-9]*) _dport=1053 ;; esac
	if [ "$WD_TUN_UP" = true ] && [ "$1" != true ]; then
		_dch="$(dns_apply "$WD_GAMING_IPS" "$_dport")"
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
```

`rootfs/opt/share/grka/bin/grka-watchdog`:

```sh
#!/bin/sh
# GrKa Keen — сторож. Запускается из /opt/etc/init.d/S99grka-keen и работает постоянно
GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"
. "$GRKA_SHARE/lib/settings.sh"
. "$GRKA_SHARE/lib/rci.sh"
. "$GRKA_SHARE/lib/routing.sh"
. "$GRKA_SHARE/lib/dnsredir.sh"
. "$GRKA_SHARE/lib/core.sh"
. "$GRKA_SHARE/lib/watchdog.sh"
wd_main
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/watchdog_test.sh`
Expected: `16 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/share/grka/lib/watchdog.sh rootfs/opt/share/grka/bin/grka-watchdog tests/watchdog_test.sh
git commit -m "Сторож: ядро с паузами перезапуска, правила и DNS по состоянию, статус и журнал"
```

---

### Task 9: Команда `grka` и переход с 0.0.2

**Files:**
- Create: `rootfs/opt/share/grka/bin/grka`, `rootfs/opt/share/grka/lib/migrate.sh`
- Test: `tests/cli_test.sh`, `tests/migrate_test.sh`

**Interfaces:**
- Consumes: всё из Task 2–8.
- Produces: `grka_main команда [аргументы]` (при `GRKA_CLI_NO_MAIN=1` файл только определяет функции), `grka_status`, `grka_device mac тип`, `grka_logs [core|journal] [N]`, `grka_diag` (печатает путь к файлу; каталог `DIAG_DIR`, по умолчанию `/tmp`), `grka_shutdown`; `migrate_run`, `migrate_kill_old_mihomo`, файл-отметка `$GRKA_ETC/.migrated-1.0`.

- [ ] **Step 1: Тест миграции**

`tests/migrate_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"
. "$GRKA_SRC/lib/migrate.sh"

old_install() {
	printf "# GrKa Keen - настройки\nPOLICY_NAME='Мой VPN'\n" > "$GRKA_ETC/grka.conf"
	printf '#!/bin/sh\n# GrKa Keen - сервис mihomo (Entware / Keenetic)\nENABLED=no\n' > "$GRKA_INITD/S97mihomo"
	echo 'mixed-port: 7890' > "$MIHOMO_DIR/config.yaml"
	echo big > "$GRKA_LOGDIR/mihomo.log"
	mkdir -p "$GRKA_PROC/321" "$GRKA_PROC/322"
	printf '/opt/sbin/mihomo\000-d\000%s\000' "$MIHOMO_DIR" > "$GRKA_PROC/321/cmdline"
	printf '/opt/sbin/xray\000run\000' > "$GRKA_PROC/322/cmdline"
	kill() { echo "$*" >> "$T/kills"; }
}

test_migrate_from_0_0_2() {
	old_install
	migrate_run
	assert_eq "Мой VPN" "$(settings_get policy_name)"
	assert_eq false "$(settings_get autostart)"
	assert_eq "$MIHOMO_DIR/config.yaml" "$(settings_get expert.mihomo)"
	assert_file_missing "$GRKA_INITD/S97mihomo"
	assert_file_exists "$GRKA_INITD/S97mihomo.grka-disabled"
	assert_file_missing "$GRKA_LOGDIR/mihomo.log"
	assert_file_exists "$GRKA_ETC/grka.conf.0.0.2"
	assert_eq 321 "$(cat "$T/kills")"
	assert_file_exists "$GRKA_ETC/.migrated-1.0"
}

test_migrate_is_idempotent() {
	old_install
	migrate_run
	settings_set policy_name '"Другое"'
	printf "POLICY_NAME='Снова'\n" > "$GRKA_ETC/grka.conf"
	migrate_run
	assert_eq "Другое" "$(settings_get policy_name)"
}

test_migrate_fresh_install() {
	migrate_run
	assert_eq GrKa "$(settings_get policy_name)"
	assert_eq true "$(settings_get autostart)"
	assert_eq false "$(state_get paused)"
	assert_file_exists "$GRKA_ETC/.migrated-1.0"
}

test_migrate_ignores_foreign_s97() {
	printf '#!/bin/sh\n# чужой сервис mihomo\n' > "$GRKA_INITD/S97mihomo"
	migrate_run
	assert_file_exists "$GRKA_INITD/S97mihomo"
}

run_tests "$0"
```

- [ ] **Step 2: Тест команды**

`tests/cli_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
GRKA_CLI_NO_MAIN=1
. "$GRKA_SRC/bin/grka"

test_device_command_sets_type_and_kicks() {
	settings_init
	state_init
	assert_contains "$(grka_main device AA:BB:CC:00:00:01 gaming)" "игровое"
	assert_eq gaming "$(jqt -r '.devices["aa:bb:cc:00:00:01"].type' "$STATE_FILE")"
	assert_file_exists "$DIRTY_FLAG"
}

test_device_command_rejects_bad_input() {
	settings_init
	state_init
	assert_contains "$(grka_main device zz gaming)" "Неверный MAC"
	assert_contains "$(grka_main device aa:bb:cc:00:00:01 weird)" "Использование"
}

test_pause_resume() {
	settings_init
	state_init
	grka_main pause >/dev/null
	assert_eq true "$(state_get paused)"
	assert_contains "$(cat "$JOURNAL_FILE")" "на паузу"
	grka_main resume >/dev/null
	assert_eq false "$(state_get paused)"
}

test_start_stop_restart() {
	settings_init
	state_init
	flag_set hold
	grka_main start >/dev/null
	assert_file_missing "$GRKA_RUN/hold"
	assert_eq true "$(state_get enabled)"
	grka_main stop >/dev/null
	assert_eq false "$(state_get enabled)"
	grka_main restart >/dev/null
	assert_file_exists "$GRKA_RUN/restart-core"
}

test_diag_redacts_token_and_masks_macs() {
	settings_init
	state_init
	settings_set rci_token '"secret-token-123"'
	printf '%s' '{"policy":{"hosts":[{"mac":"aa:bb:cc:dd:ee:ff"}]}}' > "$STATUS_FILE"
	DIAG_DIR="$T"
	_f="$(grka_diag)"
	assert_file_exists "$_f"
	assert_not_contains "$(cat "$_f")" "secret-token-123"
	assert_contains "$(cat "$_f")" "aa:bb:cc:**:**:**"
	assert_not_contains "$(cat "$_f")" "dd:ee:ff"
}

test_status_without_watchdog() {
	assert_contains "$(grka_main status)" "Сторож не запущен"
}

run_tests "$0"
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `.tools/busybox.exe sh tests/run.sh tests/migrate_test.sh tests/cli_test.sh`
Expected: FAIL — `lib/migrate.sh: not found`, `bin/grka: not found`.

- [ ] **Step 4: Implementation**

`rootfs/opt/share/grka/lib/migrate.sh`:

```sh
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
```

`rootfs/opt/share/grka/bin/grka`:

```sh
#!/bin/sh
# GrKa Keen — команда для SSH.
#   grka status | apply | pause | resume | start | stop | restart
#   grka device <MAC> gaming|regular | logs [journal|core] [N] | diag | migrate | tick | shutdown
GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"
. "$GRKA_SHARE/lib/settings.sh"
. "$GRKA_SHARE/lib/rci.sh"
. "$GRKA_SHARE/lib/routing.sh"
. "$GRKA_SHARE/lib/dnsredir.sh"
. "$GRKA_SHARE/lib/core.sh"
. "$GRKA_SHARE/lib/watchdog.sh"
. "$GRKA_SHARE/lib/migrate.sh"

DIAG_DIR="${DIAG_DIR:-/tmp}"

grka_usage() {
	cat <<'EOF'
GrKa Keen — управление из SSH
  grka status                      состояние сторожа, ядра и правил
  grka apply                       попросить сторожа проверить правила сейчас
  grka pause | resume              поставить VPN на паузу / снять паузу
  grka start | stop | restart      запустить / остановить / перезапустить ядро
  grka device <MAC> gaming|regular тип устройства
  grka logs [journal|core] [N]     журнал сторожа или лог ядра
  grka diag                        собрать файл для разбора проблемы
EOF
}

grka_kick() {
	flag_set dirty
}

grka_status() {
	if [ ! -s "$STATUS_FILE" ]; then
		echo "Сторож не запущен (нет $STATUS_FILE)"
		return 1
	fi
	jqc -r '
		"Состояние: \(.state // "?")",
		"Ядро: \(.core.name // "?"), " + (if .core.running then "запущено (PID \(.core.pid))" else "не запущено" end)
			+ (if (.core.error // "") != "" then ". Ошибка: \(.core.error)" else "" end),
		"Политика «\(.policy.name // "?")»: " + (if .policy.found then "найдена, метка \(.policy.mark)" else "не найдена" end)
			+ " (RCI: \(.policy.rci // "?"))",
		"Правила: " + (if .routing.rules_ok then "на месте" else "не применены" end)
			+ ", TUN \(.routing.tun // "?") " + (if .routing.tun_up then "поднят" else "не поднят" end),
		"Игровые устройства: " + ([(.policy.hosts // [])[] | select(.type == "gaming") | "\(.name) (\(.ip))"]
			| if length == 0 then "нет" else join(", ") end),
		"Пауза: " + (if .paused then "да" else "нет" end),
		((.warnings // [])[] | "Внимание: \(.)")' "$STATUS_FILE"
}

grka_device() {
	case "${2:-}" in
	gaming | regular) ;;
	*)
		echo "Использование: grka device <MAC> gaming|regular"
		return 1
		;;
	esac
	if ! state_set_device "$1" "$2"; then
		echo "Неверный MAC: $1"
		return 1
	fi
	grka_kick
	if [ "$2" = gaming ]; then echo "Готово: $1 — игровое"; else echo "Готово: $1 — обычное"; fi
}

grka_logs() {
	_ln="${2:-100}"
	case "$_ln" in "" | *[!0-9]*) _ln=100 ;; esac
	case "${1:-journal}" in
	core) tail -n "$_ln" "$CORE_LOG" 2>/dev/null ;;
	*) tail -n "$_ln" "$JOURNAL_FILE" 2>/dev/null ;;
	esac
}

# Файл для разбора проблемы. Токен скрыт, у MAC видны только первые три байта
grka_diag() {
	_df="$DIAG_DIR/grka-diag-$(date +%Y%m%d-%H%M%S).txt"
	{
		echo "== версия"; cat "$GRKA_SHARE/version" 2>/dev/null; echo; uname -a 2>/dev/null
		echo "== статус"; cat "$STATUS_FILE" 2>/dev/null; echo
		echo "== настройки"; jqc '.rci_token |= (if . == "" then "" else "***" end)' "$SETTINGS_FILE" 2>/dev/null
		echo "== state"; cat "$STATE_FILE" 2>/dev/null
		echo "== ip rule"; ip rule show 2>&1
		echo "== ip -6 rule"; ip -6 rule show 2>&1
		echo "== таблица 1001"; ip route show table 1001 2>&1
		echo "== таблица 1002"; ip route show table 1002 2>&1
		echo "== iptables nat"; iptables -t nat -S 2>&1
		echo "== iptables mangle"; iptables -t mangle -S 2>&1
		echo "== iptables FORWARD"; iptables -S FORWARD 2>&1
		echo "== ip6tables mangle"; ip6tables -t mangle -S 2>&1
		echo "== rp_filter"
		for _rp in "$GRKA_PROC"/sys/net/ipv4/conf/*/rp_filter; do
			[ -f "$_rp" ] && echo "$_rp: $(cat "$_rp")"
		done
		echo "== RCI show/ip/policy"; rci_get show/ip/policy 2>&1
		echo; echo "== журнал"; tail -n 200 "$JOURNAL_FILE" 2>/dev/null
		echo "== лог ядра"; tail -n 200 "$CORE_LOG" 2>/dev/null
	} 2>&1 | sed -E 's/(([0-9a-fA-F]{2}:){3})([0-9a-fA-F]{2}:){2}[0-9a-fA-F]{2}/\1**:**:**/g' > "$_df"
	echo "$_df"
}

# Полная остановка: ядро выключено, все правила сняты
grka_shutdown() {
	core_stop
	RT_TUN="$(core_tun)"
	rt_clear
	dns_clear >/dev/null
	journal info "GrKa Keen остановлен: ядро выключено, правила сняты"
}

grka_main() {
	_cmd="${1:-help}"
	[ $# -gt 0 ] && shift
	case "$_cmd" in
	status) grka_status ;;
	apply)
		flag_set rci-refresh
		grka_kick
		echo "Сторож проверит правила в течение секунды"
		;;
	pause)
		state_set paused true && journal info "VPN поставлен на паузу" && grka_kick && echo "VPN на паузе"
		;;
	resume)
		state_set paused false && journal info "Пауза снята" && grka_kick && echo "Пауза снята"
		;;
	start)
		rm -f "$GRKA_RUN/hold"
		state_set enabled true && grka_kick && echo "Ядро будет запущено"
		;;
	stop)
		state_set enabled false && grka_kick && echo "Ядро будет остановлено"
		;;
	restart)
		flag_set restart-core
		grka_kick
		echo "Ядро будет перезапущено"
		;;
	device) grka_device "$@" ;;
	logs) grka_logs "$@" ;;
	diag) grka_diag ;;
	migrate) migrate_run ;;
	tick)
		settings_init
		state_init
		wd_tick
		grka_status
		;;
	shutdown) grka_shutdown ;;
	*) grka_usage ;;
	esac
}

[ -n "${GRKA_CLI_NO_MAIN:-}" ] || grka_main "$@"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `.tools/busybox.exe sh tests/run.sh tests/migrate_test.sh tests/cli_test.sh`
Expected: `4 passed, 0 failed` и `6 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add rootfs/opt/share/grka/bin/grka rootfs/opt/share/grka/lib/migrate.sh tests/cli_test.sh tests/migrate_test.sh
git commit -m "Команда grka (status, pause, device, diag) и переход с 0.0.2"
```

---

### Task 10: Init-скрипт и хуки NDM

**Files:**
- Modify (переписать целиком): `rootfs/opt/etc/init.d/S99grka-keen`, `rootfs/opt/etc/ndm/netfilter.d/50-grka.sh`, `rootfs/opt/etc/ndm/ifstatechanged.d/50-grka.sh`
- Delete: `rootfs/opt/etc/init.d/S97mihomo`, `rootfs/opt/etc/grka/lighttpd.conf`, `rootfs/opt/share/grka/scripts/policy-route.sh`
- Test: `tests/init_test.sh`

**Interfaces:**
- Consumes: `settings_get`, `write_atomic`, `pid_alive`, `spawn_bg` (Task 2–3), `bin/grka`, `bin/grka-watchdog` (Task 8–9).
- Produces: `gen_lighttpd_conf`, `init_main start|stop|restart|status` (при `GRKA_INIT_NO_MAIN=1` только функции); путь PID-файла lighttpd — `GRKA_LPID` (по умолчанию `/opt/var/run/grka-lighttpd.pid`).

- [ ] **Step 1: Тест**

`tests/init_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
export GRKA_LPID="$T/lighttpd.pid"
GRKA_INIT_NO_MAIN=1
. "$REPO_DIR/rootfs/opt/etc/init.d/S99grka-keen"

HOOK_NF="$REPO_DIR/rootfs/opt/etc/ndm/netfilter.d/50-grka.sh"
HOOK_IF="$REPO_DIR/rootfs/opt/etc/ndm/ifstatechanged.d/50-grka.sh"

test_lighttpd_conf_uses_port_from_settings() {
	settings_init
	settings_set panel_port 1234
	gen_lighttpd_conf
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.port          = 1234"
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.document-root = \"$GRKA_SHARE/www\""
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.pid-file      = \"$T/lighttpd.pid\""
}

test_lighttpd_conf_bad_port_falls_back() {
	settings_init
	settings_set panel_port '"80; rm -rf /"'
	gen_lighttpd_conf
	assert_contains "$(cat "$GRKA_ETC/lighttpd.conf")" "server.port          = 1100"
}

test_netfilter_hook_ipv4_tables_set_flag() {
	type=iptables table=mangle sh "$HOOK_NF"
	assert_file_exists "$GRKA_RUN/dirty"
	rm -f "$GRKA_RUN/dirty"
	type=iptables table=nat sh "$HOOK_NF"
	assert_file_exists "$GRKA_RUN/dirty"
}

test_netfilter_hook_ignores_ipv6_and_raw() {
	type=ip6tables table=mangle sh "$HOOK_NF"
	assert_file_missing "$GRKA_RUN/dirty"
	type=iptables table=raw sh "$HOOK_NF"
	assert_file_missing "$GRKA_RUN/dirty"
}

test_netfilter_hook_burst_only_sets_flag() {
	_i=0
	while [ $_i -lt 20 ]; do
		type=iptables table=nat sh "$HOOK_NF"
		_i=$((_i + 1))
	done
	assert_eq "dirty" "$(ls "$GRKA_RUN")"
	assert_eq "" "$(cat "$STUB/calls")"
}

test_ifstate_hook_sets_flag() {
	sh "$HOOK_IF"
	assert_file_exists "$GRKA_RUN/dirty"
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/init_test.sh`
Expected: FAIL — `gen_lighttpd_conf: not found` (старый init-скрипт без функций).

- [ ] **Step 3: Implementation**

`rootfs/opt/etc/init.d/S99grka-keen`:

```sh
#!/bin/sh
# GrKa Keen — веб-панель и сторож.
#   start   — запустить (при первом запуске выполняет переход с 0.0.2)
#   stop    — полная остановка: панель, сторож, ядро, правила маршрутизации
#   restart — перезапуск только панели и сторожа; ядро продолжает работать (так обновляется панель)

ENABLED=yes

GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"
. "$GRKA_SHARE/lib/settings.sh"

LCONF="$GRKA_ETC/lighttpd.conf"
LPID="${GRKA_LPID:-/opt/var/run/grka-lighttpd.pid}"
WD_PIDFILE="$GRKA_RUN/watchdog.pid"

# Конфиг lighttpd создаётся из settings.json при каждом запуске: порт переживает обновления
gen_lighttpd_conf() {
	_lp="$(settings_get panel_port)"
	case "$_lp" in "" | *[!0-9]*) _lp=1100 ;; esac
	if [ "$_lp" -lt 1 ] || [ "$_lp" -gt 65535 ]; then
		_lp=1100
	fi
	write_atomic "$LCONF" <<EOF
# GrKa Keen — файл создаётся автоматически из $SETTINGS_FILE при запуске, ручные правки пропадут
server.port          = $_lp
server.document-root = "$GRKA_SHARE/www"
server.upload-dirs   = ( "/opt/tmp" )
server.errorlog      = "$GRKA_LOGDIR/lighttpd.log"
server.pid-file      = "$LPID"
server.modules       = ( "mod_cgi" )
index-file.names     = ( "index.html" )
mimetype.assign = (
  ".html"  => "text/html; charset=utf-8",
  ".js"    => "application/javascript; charset=utf-8",
  ".css"   => "text/css; charset=utf-8",
  ".json"  => "application/json; charset=utf-8",
  ".png"   => "image/png",
  ".svg"   => "image/svg+xml",
  ".woff2" => "font/woff2",
  ".ico"   => "image/x-icon"
)
\$HTTP["url"] =~ "^/cgi-bin/" {
  cgi.assign = ( "" => "" )
}
EOF
}

wd_running() {
	pid_alive "$(cat "$WD_PIDFILE" 2>/dev/null)" grka-watchdog
}

lighttpd_running() {
	pid_alive "$(cat "$LPID" 2>/dev/null)" lighttpd
}

# $1 - PID, $2 - шаблон командной строки. TERM, 5 секунд, KILL
stop_pid() {
	pid_alive "$1" "$2" || return 0
	kill "$1" 2>/dev/null
	_si=0
	while pid_alive "$1" "$2" && [ "$_si" -lt 5 ]; do
		sleep 1
		_si=$((_si + 1))
	done
	if pid_alive "$1" "$2"; then
		kill -9 "$1" 2>/dev/null
	fi
	return 0
}

do_start() {
	if [ "$ENABLED" != yes ] && [ "${1:-}" != force ]; then
		echo "grka-keen: автозапуск отключён (ENABLED=no)"
		return 0
	fi
	mkdir -p /opt/var/run "$GRKA_LOGDIR" /opt/tmp "$GRKA_RUN" "$GRKA_ETC"
	sh "$GRKA_SHARE/bin/grka" migrate >/dev/null 2>&1
	gen_lighttpd_conf
	if ! lighttpd_running; then
		if ! command -v lighttpd >/dev/null 2>&1; then
			echo "lighttpd не найден. Установите: opkg install lighttpd lighttpd-mod-cgi"
			return 1
		fi
		lighttpd -f "$LCONF" || return 1
	fi
	if ! wd_running; then
		spawn_bg /dev/null sh "$GRKA_SHARE/bin/grka-watchdog"
	fi
	echo "GrKa Keen запущен, панель на порту $(settings_get panel_port)"
}

do_stop_soft() {
	stop_pid "$(cat "$WD_PIDFILE" 2>/dev/null)" grka-watchdog
	rm -f "$WD_PIDFILE"
	stop_pid "$(cat "$LPID" 2>/dev/null)" lighttpd
	rm -f "$LPID"
}

do_stop() {
	do_stop_soft
	sh "$GRKA_SHARE/bin/grka" shutdown >/dev/null 2>&1
	echo "GrKa Keen остановлен"
}

init_main() {
	case "${1:-}" in
	start) do_start "${2:-}" ;;
	stop) do_stop ;;
	restart)
		do_stop_soft
		sleep 1
		do_start force
		;;
	status)
		if wd_running; then
			echo alive
			exit 0
		fi
		echo dead
		exit 1
		;;
	*)
		echo "Использование: $0 start | stop | restart | status"
		exit 1
		;;
	esac
}

[ -n "${GRKA_INIT_NO_MAIN:-}" ] || init_main "$@"
```

`rootfs/opt/etc/ndm/netfilter.d/50-grka.sh`:

```sh
#!/bin/sh
# GrKa Keen — NDM пересобрал таблицу netfilter. Сам хук ничего не меняет:
# ставит флаг, сторож в течение секунды проверит и починит правила (без гонок параллельных хуков).
# shellcheck disable=SC2154
[ "${type:-}" = "ip6tables" ] && exit 0
case "${table:-}" in
nat | mangle | filter) ;;
*) exit 0 ;;
esac
_run="${GRKA_RUN:-/tmp/grka}"
mkdir -p "$_run" && : > "$_run/dirty"
exit 0
```

`rootfs/opt/etc/ndm/ifstatechanged.d/50-grka.sh`:

```sh
#!/bin/sh
# GrKa Keen — изменилось состояние интерфейса. Флаг для сторожа, правила он проверит сам.
_run="${GRKA_RUN:-/tmp/grka}"
mkdir -p "$_run" && : > "$_run/dirty"
exit 0
```

Удалить файлы:

```bash
git rm rootfs/opt/etc/init.d/S97mihomo rootfs/opt/etc/grka/lighttpd.conf rootfs/opt/share/grka/scripts/policy-route.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/init_test.sh`
Expected: `6 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/etc/init.d/S99grka-keen rootfs/opt/etc/ndm tests/init_test.sh
git commit -m "S99grka-keen: панель + сторож, lighttpd.conf из настроек; хуки NDM только ставят флаг"
```

---

### Task 11: CGI с защитой от CSRF

**Files:**
- Modify (переписать целиком): `rootfs/opt/share/grka/www/cgi-bin/api`
- Test: `tests/cgi_test.sh`

**Interfaces:**
- Consumes: Task 2, 3, 7; файлы сторожа `status.json`, `hosts.json`, журнал.
- Produces (методы; старые имена сохранены для текущего интерфейса): `status`, `service` (`start|stop|restart|enable|disable`), `service.pause`, `service.resume`, `get_config`, `set_config` (`content`, `force`), `check_config`, `get_log` (`lines`, `source: core|journal`), `journal`, `list_backups`, `restore_backup`, `check_updates`, `update_core`, `update_panel`, `install_dashboard`, `set_compact`, `list_templates`, `get_template`, `task_status`, `policy_apply`, `set_policy`, `settings.get`, `settings.set`, `devices.get`, `devices.set_type`, `expert.secure_api`.

Поля ответа `status`: `ok, watchdog{running,state}, state, warnings[], running, pid, memory, core_error, core_error_log, enabled, paused, core_installed, core_version, panel_version, autostart, config_exists, dashboard_installed, compact, api_port, api_secret, api_open, arch, policy{name, found, mark, rci, table, rule_ok, route_ok, tun, tun_up, hosts[], clients[]}`.

- [ ] **Step 1: Тест**

`tests/cgi_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"
. "$GRKA_SRC/lib/settings.sh"

API="$GRKA_SRC/www/cgi-bin/api"

# $1 - тело. Окружение запроса можно поменять переменными H_METHOD, H_CT, H_X, H_ORIGIN, H_HOST, H_FWD
cgi_call() {
	_len="$(printf '%s' "$1" | wc -c | tr -d ' ')"
	_resp="$(printf '%s' "$1" | REQUEST_METHOD="${H_METHOD:-POST}" CONTENT_TYPE="${H_CT-application/json}" \
		HTTP_X_GRKA_REQUEST="${H_X-1}" HTTP_ORIGIN="${H_ORIGIN:-}" HTTP_HOST="${H_HOST:-192.168.1.1:1100}" \
		HTTP_X_FORWARDED_HOST="${H_FWD:-}" CONTENT_LENGTH="$_len" sh "$API" | tr -d '\r')"
	CGI_STATUS="$(printf '%s\n' "$_resp" | sed -n '1s/^Status: \([0-9]*\).*/\1/p')"
	CGI_BODY="$(printf '%s\n' "$_resp" | sed '1,/^$/d')"
}

body() {
	printf '%s' "$CGI_BODY" | jqt -r "$1"
}

fake_watchdog_alive() {
	mkdir -p "$GRKA_PROC/$$"
	printf 'sh\000/opt/share/grka/bin/grka-watchdog\000' > "$GRKA_PROC/$$/cmdline"
	echo $$ > "$GRKA_RUN/watchdog.pid"
}

test_csrf_rejects_missing_header() {
	settings_init
	H_X="" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
	assert_eq forbidden "$(body .code)"
}

test_csrf_rejects_wrong_content_type() {
	settings_init
	H_CT="text/plain" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_rejects_get() {
	settings_init
	H_METHOD=GET cgi_call ''
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_rejects_foreign_origin() {
	settings_init
	H_ORIGIN="https://evil.example" cgi_call '{"method":"status"}'
	assert_eq 403 "$CGI_STATUS"
}

test_csrf_allows_same_origin_and_forwarded_host() {
	settings_init
	state_init
	H_ORIGIN="http://192.168.1.1:1100" cgi_call '{"method":"status"}'
	assert_eq 200 "$CGI_STATUS"
	H_ORIGIN="https://home.keenetic.pro" H_FWD="home.keenetic.pro" cgi_call '{"method":"status"}'
	assert_eq 200 "$CGI_STATUS"
}

test_status_without_watchdog_is_down() {
	settings_init
	state_init
	cgi_call '{"method":"status"}'
	assert_eq true "$(body .ok)"
	assert_eq down "$(body .state)"
	assert_eq false "$(body .running)"
}

test_status_merges_watchdog_file() {
	settings_init
	state_init
	fake_watchdog_alive
	printf '%s' '{"state":"ok","warnings":[],"core":{"running":true,"pid":"42","memory_kb":"48000","error":"","error_log":"","enabled":true},"policy":{"name":"GrKa","found":true,"mark":"0xffffaab","rci":"ok","hosts":[{"mac":"aa:bb:cc:00:00:01","ip":"192.168.1.90","name":"PS5","type":"gaming"}]},"routing":{"rules_ok":true,"tun":"grka-tun","tun_up":true},"paused":false}' > "$STATUS_FILE"
	cgi_call '{"method":"status"}'
	assert_eq ok "$(body .state)"
	assert_eq true "$(body .running)"
	assert_eq true "$(body .policy.rule_ok)"
	assert_eq "PS5 (игровое)" "$(body '.policy.clients[0]')"
}

test_status_warns_about_open_api() {
	settings_init
	state_init
	printf "external-controller: 0.0.0.0:9090\nsecret: ''\n" > "$MIHOMO_DIR/config.yaml"
	cgi_call '{"method":"status"}'
	assert_eq true "$(body .api_open)"
	assert_contains "$(body '.warnings | join(" ")')" "без пароля"
}

test_settings_get_hides_token() {
	settings_init
	settings_set rci_token '"tok123"'
	cgi_call '{"method":"settings.get"}'
	assert_eq true "$(body .settings.has_token)"
	assert_not_contains "$CGI_BODY" "tok123"
}

test_settings_set_validates() {
	settings_init
	cgi_call '{"method":"settings.set","params":{"panel_port":80}}'
	assert_eq false "$(body .ok)"
	assert_contains "$(body .error)" "Порт"
	cgi_call '{"method":"settings.set","params":{"rci_token":"a b"}}'
	assert_eq false "$(body .ok)"
	cgi_call '{"method":"settings.set","params":{"panel_port":2000,"rci_token":"Abc.123","evil":1}}'
	assert_eq true "$(body .ok)"
	assert_eq 2000 "$(settings_get panel_port)"
	assert_eq "Abc.123" "$(settings_get rci_token)"
	assert_eq "" "$(settings_get evil)"
	assert_file_exists "$GRKA_RUN/rci-refresh"
}

test_set_policy_updates_settings_and_flags() {
	settings_init
	cgi_call '{"method":"set_policy","params":{"name":"Мой VPN / & \"дом\""}}'
	assert_eq true "$(body .ok)"
	assert_eq 'Мой VPN / & "дом"' "$(settings_get policy_name)"
	assert_file_exists "$GRKA_RUN/dirty"
	cgi_call '{"method":"set_policy","params":{"name":""}}'
	assert_eq false "$(body .ok)"
}

test_devices_set_type_and_get() {
	settings_init
	state_init
	echo '[{"mac":"aa:bb:cc:00:00:01","ip":"192.168.1.90","name":"PS5","active":true}]' > "$HOSTS_FILE"
	cgi_call '{"method":"devices.set_type","params":{"mac":"AA:BB:CC:00:00:01","type":"gaming"}}'
	assert_eq true "$(body .ok)"
	cgi_call '{"method":"devices.get"}'
	assert_eq gaming "$(body '.devices[0].type')"
	cgi_call '{"method":"devices.set_type","params":{"mac":"bad","type":"gaming"}}'
	assert_eq false "$(body .ok)"
}

test_service_actions_map_to_state_and_flags() {
	settings_init
	state_init
	cgi_call '{"method":"service","params":{"action":"stop"}}'
	assert_eq false "$(state_get enabled)"
	cgi_call '{"method":"service","params":{"action":"start"}}'
	assert_eq true "$(state_get enabled)"
	cgi_call '{"method":"service","params":{"action":"restart"}}'
	assert_file_exists "$GRKA_RUN/restart-core"
	cgi_call '{"method":"service","params":{"action":"disable"}}'
	assert_eq false "$(settings_get autostart)"
	cgi_call '{"method":"service.pause"}'
	assert_eq true "$(state_get paused)"
}

test_journal_returns_newest_first() {
	settings_init
	journal info "первое"
	journal warn "второе"
	cgi_call '{"method":"journal"}'
	assert_eq "второе" "$(body '.entries[0].message')"
	assert_eq warn "$(body '.entries[0].level')"
}

test_set_config_without_core_saves_with_warning() {
	settings_init
	cgi_call '{"method":"set_config","params":{"content":"mixed-port: 7890\n"}}'
	assert_eq true "$(body .ok)"
	assert_contains "$(body .warning)" "без проверки"
	assert_eq "mixed-port: 7890" "$(cat "$MIHOMO_DIR/config.yaml")"
}

test_unknown_method() {
	settings_init
	cgi_call '{"method":"rm_rf"}'
	assert_eq false "$(body .ok)"
	assert_contains "$(body .error)" "Неизвестный метод"
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/cgi_test.sh`
Expected: FAIL — старый CGI не проверяет заголовки (`test_csrf_*` получают 200) и не знает новых методов.

- [ ] **Step 3: Implementation**

`rootfs/opt/share/grka/www/cgi-bin/api` (полностью):

```sh
#!/bin/sh
# GrKa Keen — CGI-бэкенд панели.
# Запрос: POST, Content-Type: application/json, заголовок X-GrKa-Request: 1,
# тело {"method": "...", "params": {...}}. Ответ — JSON.
# Маршрутами и ядром CGI не управляет: пишет настройки и ставит флаги, остальное делает сторож.

GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"
. "$GRKA_SHARE/lib/settings.sh"
. "$GRKA_SHARE/lib/core.sh"

SCRIPTS="$GRKA_SHARE/scripts"
TEMPLATE_DIR="$GRKA_SHARE/templates"
BACKUP_DIR="$MIHOMO_DIR/backups"
VERSION_FILE="$GRKA_SHARE/version"
MAX_BACKUPS=10

http_reply() {
	printf 'Status: %s\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\n\r\n' "$1"
}

deny() {
	http_reply "403 Forbidden"
	jqc -n --arg e "$1" '{ok: false, error: $e, code: "forbidden"}'
	exit 0
}

# Защита от CSRF: чужой сайт не может послать такой запрос без предварительной проверки CORS,
# а её lighttpd не пропускает. Origin сверяется дополнительно
csrf_check() {
	[ "${REQUEST_METHOD:-}" = POST ] || deny "Нужен POST-запрос"
	case "${CONTENT_TYPE:-}" in
	application/json*) ;;
	*) deny "Нужен Content-Type: application/json" ;;
	esac
	[ "${HTTP_X_GRKA_REQUEST:-}" = 1 ] || deny "Запрос пришёл не из панели GrKa Keen"
	if [ -n "${HTTP_ORIGIN:-}" ]; then
		_oh="${HTTP_ORIGIN#*://}"
		[ "$_oh" = "${HTTP_HOST:-}" ] || [ "$_oh" = "${HTTP_X_FORWARDED_HOST:-}" ] || deny "Запрос с чужого сайта отклонён"
	fi
}

csrf_check
mkdir -p "$GRKA_RUN"

BODY=""
case "${CONTENT_LENGTH:-}" in
"" | *[!0-9]*) ;;
*) [ "$CONTENT_LENGTH" -gt 0 ] && BODY="$(head -c "$CONTENT_LENGTH")" ;;
esac
[ -n "$BODY" ] || BODY='{}'

jq_body() {
	printf '%s' "$BODY" | jqc -r "$1" 2>/dev/null
}

METHOD="$(jq_body '.method // empty')"

http_reply "200 OK"

err() {
	jqc -n --arg e "$1" '{ok: false, error: $e}'
}

ok_msg() {
	jqc -n --arg m "${1:-}" '{ok: true, message: $m}'
}

bool() {
	if [ "$1" -eq 0 ] 2>/dev/null; then echo true; else echo false; fi
}

task_running() {
	[ -f "$TASK_LOCK" ] || return 1
	_tp="$(cat "$TASK_LOCK" 2>/dev/null)"
	[ -n "$_tp" ] && kill -0 "$_tp" 2>/dev/null
}

run_task() {
	if task_running; then
		jqc -n '{started: false, error: "Другая задача ещё выполняется, дождитесь её завершения"}'
		return
	fi
	: > "$TASK_LOG"
	spawn_bg "$TASK_LOG" sh "$@"
	echo "$SPAWN_PID" > "$TASK_LOCK"
	jqc -n '{started: true}'
}

make_backup() {
	_cfg="$(core_config)"
	[ -f "$_cfg" ] || return 0
	mkdir -p "$BACKUP_DIR"
	cp "$_cfg" "$BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S).yaml"
	ls -1t "$BACKUP_DIR"/config-*.yaml 2>/dev/null | tail -n +"$((MAX_BACKUPS + 1))" | while read -r _bf; do
		rm -f "$_bf"
	done
}

cached_arch() {
	_ca="$(cat "$GRKA_RUN/arch" 2>/dev/null)"
	if [ -z "$_ca" ]; then
		_ca="$(mihomo_arch)"
		echo "$_ca" > "$GRKA_RUN/arch"
	fi
	echo "$_ca"
}

m_status() {
	_st="$(cat "$STATUS_FILE" 2>/dev/null)"
	if [ -z "$_st" ] || ! printf '%s' "$_st" | jqc -e 'type == "object"' >/dev/null 2>&1; then
		_st='{}'
	fi
	_wd=false
	if pid_alive "$(cat "$GRKA_RUN/watchdog.pid" 2>/dev/null)" grka-watchdog; then _wd=true; fi
	_cfg="$(core_config)"
	core_ready
	_cok=$?
	compact_on
	_cmp=$?
	[ -f "$MIHOMO_DIR/ui/index.html" ]
	_dash=$?
	_sec="$(core_api_secret)"
	_port="$(core_api_port)"
	_open=false
	if grep -q '^external-controller:' "$_cfg" 2>/dev/null && [ -z "$_sec" ]; then _open=true; fi
	_auto=true
	[ "$(settings_get autostart)" != false ] || _auto=false
	_cex=false
	[ ! -f "$_cfg" ] || _cex=true
	printf '%s' "$_st" | jqc \
		--argjson watchdog "$_wd" \
		--argjson core_installed "$(bool $_cok)" \
		--arg core_version "$(core_version)" \
		--arg panel_version "$(cat "$VERSION_FILE" 2>/dev/null)" \
		--argjson autostart "$_auto" \
		--argjson config_exists "$_cex" \
		--argjson dashboard_installed "$(bool $_dash)" \
		--argjson compact "$(bool $_cmp)" \
		--arg api_port "${_port:-9090}" \
		--arg api_secret "$_sec" \
		--argjson api_open "$_open" \
		--arg arch "$(cached_arch)" \
		'. as $s
		| (if $watchdog then ($s.state // "starting") else "down" end) as $state
		| {ok: true,
		   watchdog: {running: $watchdog, state: $state},
		   state: $state,
		   warnings: (($s.warnings // []) + (if $api_open then ["API mihomo открыт без пароля (secret): любой сайт в браузере может переключать прокси. Нажмите «Защитить API паролем»"] else [] end)),
		   running: ($s.core.running // false), pid: ($s.core.pid // ""), memory: ($s.core.memory_kb // ""),
		   core_error: ($s.core.error // ""), core_error_log: ($s.core.error_log // ""),
		   enabled: ($s.core.enabled // true), paused: ($s.paused // false),
		   core_installed: $core_installed, core_version: $core_version, panel_version: $panel_version,
		   autostart: $autostart, config_exists: $config_exists, dashboard_installed: $dashboard_installed,
		   compact: $compact, api_port: $api_port, api_secret: $api_secret, api_open: $api_open, arch: $arch,
		   policy: {name: ($s.policy.name // ""), found: ($s.policy.found // false), mark: ($s.policy.mark // ""),
		            rci: ($s.policy.rci // ""), table: "1001",
		            rule_ok: ($s.routing.rules_ok // false), route_ok: ($s.routing.tun_up // false),
		            tun: ($s.routing.tun // ""), tun_up: ($s.routing.tun_up // false),
		            hosts: ($s.policy.hosts // []),
		            clients: [($s.policy.hosts // [])[] | .name + (if .type == "gaming" then " (игровое)" else "" end)]}}'
}

m_service() {
	case "$(jq_body '.params.action // empty')" in
	start)
		rm -f "$GRKA_RUN/hold"
		{ state_set enabled true && flag_set dirty && ok_msg "Ядро запускается"; } || err "Не удалось сохранить"
		;;
	stop)
		{ state_set enabled false && flag_set dirty && ok_msg "Ядро останавливается"; } || err "Не удалось сохранить"
		;;
	restart)
		flag_set restart-core
		flag_set dirty
		ok_msg "Ядро перезапускается"
		;;
	enable)
		{ settings_set autostart true && ok_msg "Автозапуск включён"; } || err "Не удалось сохранить"
		;;
	disable)
		{ settings_set autostart false && ok_msg "Автозапуск выключен"; } || err "Не удалось сохранить"
		;;
	*) err "Недопустимое действие" ;;
	esac
}

m_pause() {
	{ state_set paused true && journal info "VPN поставлен на паузу" && flag_set dirty && ok_msg "VPN на паузе"; } || err "Не удалось сохранить"
}

m_resume() {
	{ state_set paused false && journal info "Пауза снята" && flag_set dirty && ok_msg "Пауза снята"; } || err "Не удалось сохранить"
}

m_get_config() {
	_cfg="$(core_config)"
	if [ -f "$_cfg" ]; then
		jqc -Rs '{ok: true, exists: true, content: .}' < "$_cfg"
	else
		jqc -n '{ok: true, exists: false, content: ""}'
	fi
}

m_set_config() {
	_cfg="$(core_config)"
	_force="$(jq_body '.params.force // false')"
	_tmp="$GRKA_RUN/config.check.yaml"
	jq_body '.params.content // ""' > "$_tmp"
	if [ ! -s "$_tmp" ]; then
		rm -f "$_tmp"
		err "Пустой конфиг не сохранён"
		return
	fi
	_out="$(core_validate "$_tmp")"
	_rc=$?
	if [ $_rc -ne 0 ] && [ $_rc -ne 3 ] && [ "$_force" != true ]; then
		rm -f "$_tmp"
		printf '%s' "$_out" | jqc -Rs '{ok: false, error: "Конфиг не прошёл проверку, не сохранено", output: .}'
		return
	fi
	mkdir -p "$(dirname "$_cfg")"
	make_backup
	mv -f "$_tmp" "$_cfg"
	_warn=""
	[ $_rc -ne 3 ] || _warn="Ядро не установлено, конфиг сохранён без проверки"
	jqc -n --arg w "$_warn" '{ok: true, warning: $w}'
}

m_check_config() {
	_content="$(jq_body '.params.content // ""')"
	_target="$(core_config)"
	if [ -n "$_content" ]; then
		_target="$GRKA_RUN/config.check.yaml"
		printf '%s\n' "$_content" > "$_target"
	fi
	_out="$(core_validate "$_target")"
	_rc=$?
	rm -f "$GRKA_RUN/config.check.yaml"
	printf '%s' "$_out" | jqc -Rs --argjson ok "$(bool $_rc)" '{ok: $ok, output: .}'
}

m_get_log() {
	_n="$(jq_body '.params.lines // 200')"
	case "$_n" in "" | *[!0-9]*) _n=200 ;; esac
	case "$(jq_body '.params.source // "core"')" in
	journal) tail -n "$_n" "$JOURNAL_FILE" 2>/dev/null | jqc -Rs '{ok: true, log: .}' ;;
	*) tail -n "$_n" "$CORE_LOG" 2>/dev/null | jqc -Rs '{ok: true, log: .}' ;;
	esac
}

m_journal() {
	_n="$(jq_body '.params.lines // 100')"
	case "$_n" in "" | *[!0-9]*) _n=100 ;; esac
	tail -n "$_n" "$JOURNAL_FILE" 2>/dev/null | jqc -Rs '{ok: true, entries: (split("\n") | map(select(. != "") | split("|") | {time: .[0], level: .[1], message: (.[2:] | join("|"))}) | reverse)}'
}

m_list_backups() {
	if [ -d "$BACKUP_DIR" ]; then
		ls -1t "$BACKUP_DIR"/config-*.yaml 2>/dev/null | sed 's|.*/||' | jqc -Rn '{ok: true, backups: [inputs]}'
	else
		jqc -n '{ok: true, backups: []}'
	fi
}

m_restore_backup() {
	_name="$(jq_body '.params.name // empty')"
	_name="${_name##*/}"
	if [ -n "$_name" ] && [ -f "$BACKUP_DIR/$_name" ]; then
		make_backup
		cp "$BACKUP_DIR/$_name" "$(core_config)"
		ok_msg "Бэкап восстановлен"
	else
		err "Бэкап не найден"
	fi
}

m_check_updates() {
	jqc -n \
		--arg core_current "$(core_version)" \
		--arg core_latest "$(latest_tag "$MIHOMO_REPO")" \
		--arg panel_current "$(cat "$VERSION_FILE" 2>/dev/null)" \
		--arg panel_latest "$(latest_tag "$GRKA_REPO" | sed 's/^v//')" \
		'{ok: true, core_current: $core_current, core_latest: $core_latest,
		  panel_current: $panel_current, panel_latest: $panel_latest}'
}

m_update_core() {
	_v="$(jq_body '.params.version // empty')"
	case "$_v" in "" | v[0-9]*) ;; *) err "Неверная версия"; return ;; esac
	case "$_v" in *[!0-9A-Za-z.-]*) err "Неверная версия"; return ;; esac
	run_task "$SCRIPTS/core-update.sh" "$_v"
}

m_set_compact() {
	_en="$(jq_body '.params.enabled // empty')"
	if [ "$_en" = 1 ] || [ "$_en" = true ]; then
		run_task "$SCRIPTS/compact-toggle.sh" on
	else
		run_task "$SCRIPTS/compact-toggle.sh" off
	fi
}

m_list_templates() {
	{
		for _f in "$TEMPLATE_DIR"/*.yaml; do
			[ -f "$_f" ] || continue
			_id="${_f##*/}"
			_id="${_id%.yaml}"
			_title="$(sed -n '1s/^#[[:space:]]*title:[[:space:]]*//p' "$_f")"
			jqc -n --arg id "$_id" --arg title "${_title:-$_id}" '{id: $id, title: $title}'
		done
	} | jqc -s '{ok: true, templates: .}'
}

m_get_template() {
	_tid="$(jq_body '.params.id // empty')"
	_tid="${_tid##*/}"
	if [ -n "$_tid" ] && [ -f "$TEMPLATE_DIR/$_tid.yaml" ]; then
		jqc -Rs '{ok: true, content: .}' < "$TEMPLATE_DIR/$_tid.yaml"
	else
		err "Шаблон не найден"
	fi
}

m_task_status() {
	task_running
	_tr=$?
	tail -c 16384 "$TASK_LOG" 2>/dev/null | jqc -Rs --argjson running "$(bool $_tr)" '{ok: true, running: $running, log: .}'
}

m_policy_apply() {
	flag_set rci-refresh
	flag_set dirty
	jqc -n '{ok: true, output: "Сторож применит правила в течение секунды"}'
}

m_set_policy() {
	_nm="$(jq_body '.params.name // empty')"
	if ! policy_name_valid "$_nm"; then
		err "Имя политики: от 1 до 64 символов, без служебных символов"
		return
	fi
	settings_set policy_name "$(json_str "$_nm")" || { err "Не удалось сохранить"; return; }
	flag_set rci-refresh
	flag_set dirty
	jqc -n --arg n "$_nm" '{ok: true, name: $n}'
}

m_settings_get() {
	jqc '{ok: true, settings: (. + {has_token: ((.rci_token // "") != "")} | del(.rci_token, .password_hash))}' "$SETTINGS_FILE"
}

m_settings_set() {
	_p="$(printf '%s' "$BODY" | jqc -c '.params // {}')"
	_errs="$(printf '%s' "$_p" | jqc -r '
		[ (if has("policy_name") then (.policy_name | if type == "string" and length >= 1 and length <= 64 and (explode | all(. >= 32 and . != 127)) then empty else "Имя политики: от 1 до 64 символов" end) else empty end),
		  (if has("rci_token") then (.rci_token | if type == "string" and length <= 512 and test("^[A-Za-z0-9._~+/=-]*$") then empty else "Токен RCI: только латиница, цифры и символы ._~+/=-" end) else empty end),
		  (if has("panel_port") then (.panel_port | if type == "number" and . == floor and . >= 1024 and . <= 65535 then empty else "Порт панели: число от 1024 до 65535" end) else empty end),
		  (if has("autostart") then (.autostart | if type == "boolean" then empty else "Автозапуск: да или нет" end) else empty end),
		  (if has("ipv6_block") then (.ipv6_block | if type == "boolean" then empty else "Блокировка IPv6: да или нет" end) else empty end)
		] | join("; ")')"
	if [ -n "$_errs" ]; then
		err "$_errs"
		return
	fi
	lock_acquire config || { sleep 1; lock_acquire config; } || { err "Настройки заняты, повторите"; return; }
	jqc --argjson p "$_p" '. + ($p | with_entries(select(.key | IN("policy_name", "rci_token", "panel_port", "autostart", "ipv6_block"))))' "$SETTINGS_FILE" | write_atomic "$SETTINGS_FILE"
	_r=$?
	lock_release config
	if [ $_r -ne 0 ]; then
		err "Не удалось сохранить настройки"
		return
	fi
	flag_set rci-refresh
	flag_set dirty
	_restart=false
	if printf '%s' "$_p" | jqc -e 'has("panel_port")' >/dev/null 2>&1; then _restart=true; fi
	jqc -n --argjson r "$_restart" '{ok: true, panel_restart_needed: $r}'
}

m_devices_get() {
	_h="$(cat "$HOSTS_FILE" 2>/dev/null)"
	[ -n "$_h" ] || _h='[]'
	jqc -n --argjson h "$_h" --slurpfile st "$STATE_FILE" '{ok: true, devices: [$h[] | . + {type: ($st[0].devices[.mac].type // "regular")}]}'
}

m_devices_set_type() {
	_mac="$(jq_body '.params.mac // empty')"
	_type="$(jq_body '.params.type // empty')"
	case "$_type" in
	gaming | regular) ;;
	*)
		err "Тип устройства: gaming или regular"
		return
		;;
	esac
	if ! state_set_device "$_mac" "$_type"; then
		err "Неверный MAC-адрес"
		return
	fi
	flag_set dirty
	ok_msg "Сохранено"
}

# Случайный secret в своём конфиге mihomo: закрывает Clash API от чужих сайтов
m_secure_api() {
	_cfg="$(core_config)"
	if [ ! -f "$_cfg" ]; then
		err "Конфиг не найден"
		return
	fi
	_s="$(head -c 32 /dev/urandom | md5sum | cut -c1-24)"
	make_backup
	if grep -q '^secret:' "$_cfg"; then
		sed -i "s/^secret:.*/secret: '$_s'/" "$_cfg"
	else
		printf "\nsecret: '%s'\n" "$_s" >> "$_cfg"
	fi
	flag_set restart-core
	flag_set dirty
	ok_msg "API защищён паролем, ядро перезапускается"
}

case "$METHOD" in
status) m_status ;;
service) m_service ;;
service.pause) m_pause ;;
service.resume) m_resume ;;
get_config) m_get_config ;;
set_config) m_set_config ;;
check_config) m_check_config ;;
get_log) m_get_log ;;
journal) m_journal ;;
list_backups) m_list_backups ;;
restore_backup) m_restore_backup ;;
check_updates) m_check_updates ;;
update_core) m_update_core ;;
update_panel) run_task "$SCRIPTS/self-update.sh" ;;
install_dashboard) run_task "$SCRIPTS/dashboard-install.sh" ;;
set_compact) m_set_compact ;;
list_templates) m_list_templates ;;
get_template) m_get_template ;;
task_status) m_task_status ;;
policy_apply) m_policy_apply ;;
set_policy) m_set_policy ;;
settings.get) m_settings_get ;;
settings.set) m_settings_set ;;
devices.get) m_devices_get ;;
devices.set_type) m_devices_set_type ;;
expert.secure_api) m_secure_api ;;
*) jqc -n --arg m "$METHOD" '{ok: false, error: ("Неизвестный метод: " + $m)}' ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.tools/busybox.exe sh tests/run.sh tests/cgi_test.sh`
Expected: `16 passed, 0 failed`. Если `test_status_merges_watchdog_file` падает из-за `kill -0 $$` в busybox-w32 (см. Task 1, Step 5) — в этом тесте записывать в `watchdog.pid` PID живого фонового процесса: `sleep 30 & _p=$!` и создавать `cmdline` для `$_p`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/opt/share/grka/www/cgi-bin/api tests/cgi_test.sh
git commit -m "CGI: защита от CSRF, статус из файла сторожа, настройки, устройства, пауза"
```

---

### Task 12: Текущий интерфейс и фоновые скрипты под сторожа

**Files:**
- Modify: `rootfs/opt/share/grka/www/app.js`, `rootfs/opt/share/grka/www/style.css`, `docs/demo/demo-shim.js`
- Modify (переписать целиком): `rootfs/opt/share/grka/scripts/core-update.sh`, `rootfs/opt/share/grka/scripts/compact-toggle.sh`, `rootfs/opt/share/grka/scripts/self-update.sh`, `rootfs/opt/share/grka/scripts/dashboard-install.sh`
- Test: `tests/static_test.sh`

**Interfaces:**
- Consumes: методы CGI из Task 11; `flag_set`, `TASK_LOCK`, `MIHOMO_BIN`, `MIHOMO_GZ`, `MIHOMO_TMP`, `compact_on`, `ensure_core` (Task 2, 7).

- [ ] **Step 1: Тест**

`tests/static_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"

test_api_sends_csrf_header() {
	assert_contains "$(cat "$GRKA_SRC/www/app.js")" "'X-GrKa-Request': '1'"
}

test_no_references_to_removed_files() {
	_r="$(grep -rlE 'S97mihomo|policy-route\.sh|/tmp/grka-task\.lock' "$GRKA_SRC" "$REPO_DIR/rootfs/opt/etc" 2>/dev/null | grep -v 'lib/migrate.sh')"
	assert_eq "" "$_r"
}

test_scripts_use_new_library() {
	for _s in core-update.sh compact-toggle.sh self-update.sh dashboard-install.sh; do
		assert_contains "$(cat "$GRKA_SRC/scripts/$_s")" 'lib/common.sh' "$_s"
	done
}

run_tests "$0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.tools/busybox.exe sh tests/run.sh tests/static_test.sh`
Expected: FAIL во всех трёх тестах.

- [ ] **Step 3: Фоновые скрипты**

`rootfs/opt/share/grka/scripts/core-update.sh`:

```sh
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
```

`rootfs/opt/share/grka/scripts/compact-toggle.sh`:

```sh
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
```

`rootfs/opt/share/grka/scripts/self-update.sh`:

```sh
#!/bin/sh
# GrKa Keen - самообновление панели с GitHub-релизов

# Обновление перезапишет этот файл, поэтому работаем из копии в /tmp
if [ "${GRKA_SELFUPDATE_COPY:-}" != 1 ]; then
	cp "$0" /tmp/grka-self-update-run.sh
	export GRKA_SELFUPDATE_COPY=1
	exec sh /tmp/grka-self-update-run.sh "$@"
fi

GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"

TMP_TAR="/opt/tmp/grka-panel.tar.gz"

cleanup() {
	rm -f "$TASK_LOCK" "$TMP_TAR" /tmp/grka-self-update-run.sh
}
trap cleanup EXIT
mkdir -p "$GRKA_RUN" /opt/tmp
echo $$ > "$TASK_LOCK"

echo "Проверка последней версии GrKa Keen..."
TAG="$(latest_tag "$GRKA_REPO")"
[ -n "$TAG" ] || { echo "ОШИБКА: не удалось получить версию с GitHub API"; exit 1; }

CUR="$(cat "$GRKA_SHARE/version" 2>/dev/null)"
if [ "v$CUR" = "$TAG" ]; then
	echo "Уже установлена последняя версия ($CUR)"
	exit 0
fi

VER="${TAG#v}"
URL="https://github.com/$GRKA_REPO/releases/download/$TAG/grka-keen-$VER.tar.gz"
echo "Загрузка: $URL"
download "$URL" "$TMP_TAR" || { echo "ОШИБКА: не удалось скачать релиз"; exit 1; }

echo "Установка..."
tar -C / -xzf "$TMP_TAR" || { echo "ОШИБКА: не удалось распаковать архив"; exit 1; }
chmod +x "$GRKA_SHARE"/bin/* "$GRKA_SHARE"/scripts/*.sh "$GRKA_SHARE/www/cgi-bin/api" \
	/opt/etc/init.d/S99grka-keen /opt/etc/ndm/netfilter.d/50-grka.sh /opt/etc/ndm/ifstatechanged.d/50-grka.sh 2>/dev/null
sh "$GRKA_SHARE/bin/grka" migrate

echo "Перезапуск веб-панели (ядро продолжает работать)..."
/opt/etc/init.d/S99grka-keen restart >/dev/null 2>&1

echo ""
echo "Готово: панель обновлена до версии $VER."
echo "Обновите страницу в браузере (Ctrl+F5)."
```

`rootfs/opt/share/grka/scripts/dashboard-install.sh`:

```sh
#!/bin/sh
# GrKa Keen - установка веб-дашборда MetaCubeXD (Clash API UI) в /opt/etc/mihomo/ui
GRKA_SHARE="${GRKA_SHARE:-/opt/share/grka}"
. "$GRKA_SHARE/lib/common.sh"

TMP_TGZ="/opt/tmp/grka-ui.tgz"
UI_DIR="$MIHOMO_DIR/ui"

cleanup() {
	rm -f "$TASK_LOCK" "$TMP_TGZ"
}
trap cleanup EXIT
mkdir -p "$GRKA_RUN" /opt/tmp
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
```

- [ ] **Step 4: Правки `app.js`**

4.1. В `api()`:

```js
		headers: { 'Content-Type': 'application/json' },
```

заменить на

```js
		headers: { 'Content-Type': 'application/json', 'X-GrKa-Request': '1' },
```

4.2. В `statusTab` после строки `var statusTab = {` добавить свойство:

```js
	paused: false,
```

4.3. В `statusTab.render` после блока `u.btnDashInstall = el(...);` добавить:

```js
		u.warnings = el('div', { 'class': 'warnbox', 'style': 'display:none' });
		u.wdState = el('span', {}, '—');
		u.coreError = el('pre', { 'class': 'term', 'style': 'display:none;margin-top:.5em;max-height:12em' }, '');
		u.btnPause = el('button', { 'class': 'btn', onclick: function() {
			api(self.paused ? 'service.resume' : 'service.pause').then(function(res) {
				notify((res && (res.message || res.error)) || 'Готово', res && res.ok ? 'info' : 'error');
				self.refresh();
			});
		} }, 'Поставить VPN на паузу');
		u.btnSecureApi = el('button', { 'class': 'btn primary', 'style': 'display:none', onclick: function() {
			api('expert.secure_api').then(function(res) {
				notify((res && (res.message || res.error)) || 'Готово', res && res.ok ? 'info' : 'error');
				self.refresh();
			});
		} }, 'Защитить API паролем');
		u.token = el('input', { type: 'text', 'style': 'width:22em', placeholder: 'токен из Keenetic: Пользователи и доступ' });
		u.btnTokenSave = el('button', { 'class': 'btn', 'style': 'margin-left:8px', onclick: function() {
			api('settings.set', { rci_token: u.token.value.trim() }).then(function(res) {
				if (res && res.ok) { notify('Токен сохранён'); u.token.value = ''; self.refresh(); }
				else notify((res && res.error) || 'Ошибка сохранения', 'error');
			});
		} }, 'Сохранить');
```

4.4. В разметке `appendAny(root, [...])` статуса:
- сразу после `el('div', { 'class': 'descr' }, 'Панель управления mihomo для Keenetic. ...')` вставить `u.warnings,`;
- в секции «Сервис mihomo» после `row('Состояние', [u.state, ' ', u.details]),` вставить `row('Сторож', [u.wdState, u.coreError]),`;
- строку `row('Управление', el('div', { 'class': 'btnrow' }, [u.btnStart, u.btnStop, u.btnRestart]))),` заменить на `row('Управление', el('div', { 'class': 'btnrow' }, [u.btnStart, u.btnStop, u.btnRestart, u.btnSecureApi]))),`;
- в секции «Политика доступа Keenetic» строку `row('Действия', u.btnPolicyApply)),` заменить на:

```js
				row('Токен RCI', [u.token, u.btnTokenSave, el('div', { 'class': 'hint' }, 'Нужен на KeeneticOS 5.2 и новее. Пустое поле и «Сохранить» — удалить токен')]),
				row('Действия', el('div', { 'class': 'btnrow' }, [u.btnPolicyApply, u.btnPause]))),
```

4.5. В `statusTab.update` в начало функции (после `var u = this.el;`) добавить:

```js
		var WD = { ok: 'всё в порядке', starting: 'запускаю ядро', waiting_policy: 'жду политику Keenetic',
			paused: 'VPN на паузе', stopped: 'ядро остановлено', error: 'ошибка', down: 'не запущен' };
		u.wdState.textContent = WD[st.state] || st.state || '—';
		u.wdState.className = st.state === 'ok' ? 'ok' : ((st.state === 'error' || st.state === 'down') ? 'bad' : 'warn');
		var warns = st.warnings || [];
		u.warnings.innerHTML = '';
		warns.forEach(function(w) { u.warnings.appendChild(el('div', {}, w)); });
		u.warnings.style.display = warns.length ? '' : 'none';
		u.coreError.textContent = st.core_error ? st.core_error + (st.core_error_log ? '\n\n' + st.core_error_log : '') : '';
		u.coreError.style.display = st.core_error ? '' : 'none';
		this.paused = !!st.paused;
		u.btnPause.textContent = st.paused ? 'Снять паузу' : 'Поставить VPN на паузу';
		u.btnSecureApi.style.display = st.api_open ? '' : 'none';
```

и в ветке маршрутизации заменить

```js
			appendAny(u.policyRoute, el('span', { 'class': 'hint' }, 'mihomo остановлен — у клиентов политики нет интернета (режим резервирования)'));
```

на

```js
			appendAny(u.policyRoute, el('span', { 'class': 'hint' }, st.paused
				? 'VPN на паузе: устройства политики идут напрямую'
				: 'ядро остановлено: у устройств политики нет интернета (без утечек мимо VPN)'));
```

4.6. В `configTab.save` заменить функцию целиком:

```js
	save: function(restart) {
		return api('set_config', { content: this.textarea.value }).then(function(res) {
			if (!res || !res.ok) {
				modal('❌ Конфигурация не сохранена', [
					el('p', {}, (res && res.error) || 'Ошибка сохранения'),
					res && res.output ? el('pre', { 'class': 'term', 'style': 'max-height:50vh' }, res.output) : null
				], [el('button', { 'class': 'btn', onclick: closeModal }, 'Закрыть')]);
				return false;
			}
			if (res.warning) notify(res.warning, 'error');
			if (restart) return api('service', { action: 'restart' }).then(function() { return true; });
			return true;
		}).then(function(saved) {
			if (saved) notify(restart ? 'Конфигурация сохранена, ядро перезапускается' : 'Конфигурация сохранена');
		});
	},
```

4.7. В `logsTab.render` после `this.autoscroll = ...;` добавить:

```js
		this.sourceSelect = el('select', { onchange: function() { self.fetchLog(); } },
			el('option', { value: 'journal' }, 'Журнал сторожа'),
			el('option', { value: 'core' }, 'Лог ядра'));
```

в `btnrow` логов первым элементом вставить `this.sourceSelect,`; описание вкладки заменить на `'Журнал сторожа (что он проверял и чинил) и лог ядра (в памяти роутера, ротация при 1 МБ). Автообновление каждые 3 секунды.'`; в `fetchLog` вызов заменить на:

```js
		return api('get_log', { lines: parseInt(this.linesSelect.value, 10), source: this.sourceSelect.value }).then(function(res) {
```

4.8. `style.css` — добавить в конец:

```css
.warnbox {
  background: #3a3218;
  border: 1px solid #6b5a22;
  color: #f1dfa6;
  border-radius: 6px;
  padding: 10px 14px;
  margin-bottom: 16px;
  font-size: 13px;
}

.warnbox div + div { margin-top: 6px; }
```

4.9. `docs/demo/demo-shim.js` — строку

```js
	var STATUS = {
		running: true, pid: '9184', memory: '47616',
```

заменить на

```js
	var STATUS = {
		ok: true, state: 'ok', warnings: [], paused: false, enabled: true,
		api_open: false, core_error: '', core_error_log: '',
		running: true, pid: '9184', memory: '47616',
```

строку `name: 'GrKa', found: true, mark: '0xffffaab', table: '1001',` заменить на `name: 'GrKa', found: true, mark: '0xffffaab', table: '1001', rci: 'ok',`; в объект `API` после строки `get_log: function() { return { log: LOG }; },` добавить:

```js
		journal: function() { return { ok: true, entries: [] }; },
```

(неизвестные методы демо уже отвечает `{ ok: true }`).

- [ ] **Step 5: Run tests**

Run: `.tools/busybox.exe sh tests/run.sh tests/static_test.sh`
Expected: `3 passed, 0 failed`.

Ручная проверка интерфейса: открыть `docs/demo/demo.html` в браузере — вкладки «Статус», «Конфигурация», «Логи» открываются без ошибок в консоли, на «Статусе» видны строка «Сторож» и кнопка «Поставить VPN на паузу».

- [ ] **Step 6: Commit**

```bash
git add rootfs/opt/share/grka/www/app.js rootfs/opt/share/grka/www/style.css docs/demo/demo-shim.js rootfs/opt/share/grka/scripts/ tests/static_test.sh
git commit -m "Интерфейс 0.x под сторожа: заголовок CSRF, пауза, токен RCI, журнал; скрипты без S97mihomo"
```

---

### Task 13: Сборка, установка, версия, проверка стиля

**Files:**
- Modify (переписать целиком): `build-ipk.sh`, `install.sh`
- Modify: `rootfs/opt/share/grka/version`, `build.sh` (строка `cd "$(dirname "$0")"` → `cd "$(dirname "$0")" || exit 1`)
- Create: `docs/stage1-checklist.md`
- Test: `tests/lint_test.sh`

- [ ] **Step 1: Тест стиля**

`tests/lint_test.sh`:

```sh
#!/bin/sh
. "$(dirname "$0")/lib/env.sh"

test_shellcheck_clean() {
	_files="$(ls "$GRKA_SRC"/bin/* "$GRKA_SRC"/lib/*.sh "$GRKA_SRC"/scripts/*.sh "$GRKA_SRC/www/cgi-bin/api" \
		"$REPO_DIR"/rootfs/opt/etc/init.d/* "$REPO_DIR"/rootfs/opt/etc/ndm/*/*.sh \
		"$REPO_DIR/install.sh" "$REPO_DIR/build.sh" "$REPO_DIR/build-ipk.sh")"
	# shellcheck disable=SC2086
	_out="$(shellcheck -s sh -S warning -e SC1090,SC1091 $_files 2>&1)"
	assert_eq "" "$_out"
}

test_no_crlf_in_rootfs() {
	assert_eq "" "$(grep -rl "$(printf '\r')" "$REPO_DIR/rootfs" 2>/dev/null)"
}

test_version_is_alpha() {
	assert_eq "1.0.0-alpha.1" "$(tr -d ' \r\n' < "$GRKA_SRC/version")"
}

run_tests "$0"
```

Run: `.tools/busybox.exe sh tests/run.sh tests/lint_test.sh`
Expected: FAIL (`install.sh` использует `$'...'`, версия 0.0.2).

- [ ] **Step 2: Версия и установщик**

`rootfs/opt/share/grka/version`:

```
1.0.0-alpha.1
```

`install.sh`:

```sh
#!/bin/sh
# GrKa Keen - установщик (Keenetic + Entware)
# Последний релиз: sh -c "$(wget -qO- https://raw.githubusercontent.com/Soporif1c/GrKa-Keen/main/install.sh)"
# Конкретная версия: sh -c "$(wget -qO- .../install.sh)" _ v1.0.0-alpha.1

REPO="Soporif1c/GrKa-Keen"
TMP_TAR="/opt/tmp/grka-keen.tar.gz"
PATH="/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ESC="$(printf '\033')"
GREEN="${ESC}[1;32m"
RED="${ESC}[1;31m"
CYAN="${ESC}[1;96m"
NC="${ESC}[0m"

fail() {
	printf "%s ОШИБКА:%s %s\n" "$RED" "$NC" "$1" >&2
	exit 1
}

fetch() {
	if command -v curl >/dev/null 2>&1; then curl -sfL --connect-timeout 10 --retry 2 "$1"; else wget -qO- "$1"; fi
}

download() {
	if command -v curl >/dev/null 2>&1; then curl -fL --connect-timeout 10 --retry 2 -o "$2" "$1"; else wget -qO "$2" "$1"; fi
}

printf "\n%s=== GrKa Keen — установка ===%s\n\n" "$CYAN" "$NC"

[ -x /opt/bin/opkg ] || fail "Entware не найден (/opt/bin/opkg). Установите Entware: https://help.keenetic.com/hc/ru/articles/360021214160"

printf "Установка зависимостей (lighttpd, jq, curl, iptables, ip-full, unzip)...\n"
/opt/bin/opkg update >/dev/null 2>&1
/opt/bin/opkg install lighttpd lighttpd-mod-cgi jq curl iptables ip-full unzip >/dev/null 2>&1 ||
	printf "%sПредупреждение:%s не все пакеты установились — проверьте opkg вручную\n" "$RED" "$NC"
for _dep in jq lighttpd unzip; do
	command -v "$_dep" >/dev/null 2>&1 || fail "$_dep не установлен (opkg install $_dep)"
done

# Отдельный экземпляр lighttpd для панели поднимает S99grka-keen; глобальный S80lighttpd не нужен
if [ -f /opt/etc/init.d/S80lighttpd ] && [ ! -f /opt/etc/lighttpd/.grka-keep ]; then
	sed -i 's/^ENABLED=yes/ENABLED=no/' /opt/etc/init.d/S80lighttpd 2>/dev/null
fi

mkdir -p /opt/tmp
TAG="${1:-}"
if [ -z "$TAG" ]; then
	printf "Получение последней версии...\n"
	TAG="$(fetch "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
	[ -n "$TAG" ] || fail "не удалось получить версию с GitHub API"
fi
VER="${TAG#v}"

printf "Загрузка GrKa Keen %s...\n" "$VER"
download "https://github.com/$REPO/releases/download/$TAG/grka-keen-$VER.tar.gz" "$TMP_TAR" || fail "не удалось скачать релиз"

printf "Установка файлов...\n"
tar -C / -xzf "$TMP_TAR" || fail "не удалось распаковать архив"
rm -f "$TMP_TAR"
chmod +x /opt/share/grka/bin/* /opt/share/grka/scripts/*.sh /opt/share/grka/www/cgi-bin/api \
	/opt/etc/init.d/S99grka-keen /opt/etc/ndm/netfilter.d/50-grka.sh /opt/etc/ndm/ifstatechanged.d/50-grka.sh

mkdir -p /opt/etc/mihomo/backups /opt/var/log/grka /opt/var/run /opt/etc/grka
if [ ! -f /opt/etc/mihomo/config.yaml ]; then
	cp /opt/share/grka/config.yaml.default /opt/etc/mihomo/config.yaml
	printf "Создана конфигурация по умолчанию: /opt/etc/mihomo/config.yaml\n"
fi
sh /opt/share/grka/bin/grka migrate

if [ ! -x /opt/sbin/mihomo ] && [ ! -f /opt/share/grka/mihomo.gz ]; then
	printf "\nУстановка ядра mihomo с официального репозитория...\n"
	sh /opt/share/grka/scripts/core-update.sh || printf "%s Не удалось установить ядро автоматически — установите его через панель.%s\n" "$RED" "$NC"
fi

printf "Запуск веб-панели и сторожа...\n"
/opt/etc/init.d/S99grka-keen restart >/dev/null 2>&1

[ -e /dev/net/tun ] || printf "\n%sВНИМАНИЕ:%s /dev/net/tun не найден. Установите компонент «OpenVPN» (Управление -> Параметры системы -> Обновления и компоненты) и перезагрузите роутер.\n" "$RED" "$NC"

IP_HINT="$(ip -4 addr show br0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n1)"
[ -n "$IP_HINT" ] || IP_HINT="<IP роутера>"

printf "\n%s✔ Готово!%s Панель: %shttp://%s:1100%s\n" "$GREEN" "$NC" "$CYAN" "$IP_HINT" "$NC"
printf "  1. В веб-интерфейсе Keenetic создайте политику доступа «GrKa» (подключения ей не назначайте)\n"
printf "     и добавьте в неё устройства: Приоритеты подключений -> Применение политик\n"
printf "  2. В панели: «Конфигурация» -> добавьте прокси -> «Сохранить и перезапустить»\n"
printf "  3. Состояние из SSH: grka status (команда лежит в /opt/share/grka/bin/grka)\n\n"
```

- [ ] **Step 3: Пакет ipk**

`build-ipk.sh`:

```sh
#!/bin/sh
# Сборка opkg-пакета grka-keen_<version>_all.ipk из rootfs/
# Формат ipk (Entware/OpenWRT): tar.gz с файлами debian-binary, control.tar.gz, data.tar.gz
set -e

cd "$(dirname "$0")"
VERSION="$(tr -d ' \r\n' < rootfs/opt/share/grka/version)"
OUT="grka-keen_${VERSION}_all.ipk"
STAGE=".ipk-stage"

if grep -rl "$(printf '\r')" rootfs/ 2>/dev/null; then
	echo "ОШИБКА: найдены файлы с CRLF (список выше). Исправьте окончания строк на LF." >&2
	exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE/control"
printf '2.0\n' > "$STAGE/debian-binary"

cat > "$STAGE/control/control" <<EOF
Package: grka-keen
Version: $VERSION
Architecture: all
Maintainer: Soporif1c
Section: net
Priority: optional
Depends: lighttpd, lighttpd-mod-cgi, jq, curl, iptables, ip-full, unzip
Description: Панель управления VPN для Keenetic: сторож правил, политика доступа «GrKa»,
 вебморда на порту 1100. https://github.com/Soporif1c/GrKa-Keen
EOF

cat > "$STAGE/control/postinst" <<'EOF'
#!/bin/sh
chmod +x /opt/share/grka/bin/* /opt/share/grka/scripts/*.sh /opt/share/grka/www/cgi-bin/api \
	/opt/etc/init.d/S99grka-keen /opt/etc/ndm/netfilter.d/50-grka.sh /opt/etc/ndm/ifstatechanged.d/50-grka.sh 2>/dev/null
mkdir -p /opt/etc/mihomo/backups /opt/var/log/grka /opt/var/run /opt/tmp /opt/etc/grka
[ -f /opt/etc/mihomo/config.yaml ] || cp /opt/share/grka/config.yaml.default /opt/etc/mihomo/config.yaml
if [ -f /opt/etc/init.d/S80lighttpd ]; then
	sed -i 's/^ENABLED=yes/ENABLED=no/' /opt/etc/init.d/S80lighttpd 2>/dev/null
fi
sh /opt/share/grka/bin/grka migrate
/opt/etc/init.d/S99grka-keen restart >/dev/null 2>&1
IP_HINT="$(ip -4 addr show br0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n1)"
[ -n "$IP_HINT" ] || IP_HINT="<IP роутера>"
echo ""
echo "GrKa Keen установлен. Панель: http://$IP_HINT:1100"
echo "  Ядро mihomo: вкладка «Статус» -> «Установить ядро» (или sh /opt/share/grka/scripts/core-update.sh)"
echo "  Политика: создайте в Keenetic политику «GrKa» и добавьте в неё устройства"
[ -e /dev/net/tun ] || echo "ВНИМАНИЕ: /dev/net/tun нет — установите компонент Keenetic «OpenVPN» и перезагрузите роутер"
exit 0
EOF

cat > "$STAGE/control/prerm" <<'EOF'
#!/bin/sh
# При обновлении пакета ничего не останавливаем: postinst новой версии перезапустит только панель и сторожа
[ "$1" = "upgrade" ] && exit 0
/opt/etc/init.d/S99grka-keen stop >/dev/null 2>&1
exit 0
EOF

tar -C "$STAGE/control" --owner=0 --group=0 --numeric-owner --mode=0755 -czf "$STAGE/control.tar.gz" .
tar -C rootfs --owner=0 --group=0 --numeric-owner -czf "$STAGE/data.tar.gz" ./opt
tar -C "$STAGE" --owner=0 --group=0 --numeric-owner -czf "$OUT" ./debian-binary ./control.tar.gz ./data.tar.gz

rm -rf "$STAGE"
echo "Собрано: $OUT"
tar -tzf "$OUT"
```

- [ ] **Step 4: Чек-лист для стенда**

`docs/stage1-checklist.md`:

```markdown
# Проверка этапа 1 на роутере (KN-1811)

Установка альфы, если релиз опубликован:
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/Soporif1c/GrKa-Keen/release-1.0/install.sh)" _ v1.0.0-alpha.1

Если релиза нет: скопировать grka-keen-1.0.0-alpha.1.tar.gz в /opt/tmp и выполнить
    tar -C / -xzf /opt/tmp/grka-keen-1.0.0-alpha.1.tar.gz
    sh /opt/share/grka/bin/grka migrate && /opt/etc/init.d/S99grka-keen restart

Дальше команда `grka` — это `sh /opt/share/grka/bin/grka`.

1. `grka status` — «Состояние: ok», политика найдена, правила на месте, TUN поднят.
2. Перезагрузить роутер три раза. После каждой загрузки:
   `grka status` и `grka logs journal 30` — в журнале «Политика «GrKa» найдена», «Правила маршрутизации применены», состояние ok.
3. Отключить и включить интернет в веб-интерфейсе Keenetic. Через 10 секунд `grka status` — ok.
4. `kill -9 $(cat /tmp/grka/core.pid)` — через 5–10 секунд ядро снова работает, в журнале «упало, перезапуск через 5 с».
5. `grka device <MAC приставки> gaming`, затем `ip rule` — есть правила 97 и 98 с IP приставки;
   `iptables -t nat -S GRKA_DNS` — две строки с этим IP.
6. `grka pause` — интернет у устройств политики идёт напрямую; `grka resume` — снова через ядро.
7. `grka diag` — прислать получившийся файл (токены в нём скрыты, у MAC видна только первая половина).
```

- [ ] **Step 5: Run full suite and lint**

Run: `.tools/busybox.exe sh tests/run.sh`
Expected: все файлы `… passed, 0 failed`, в конце `ВСЕ ТЕСТЫ ПРОШЛИ`.

Run (Git Bash): `sh build.sh && sh build-ipk.sh`
Expected: `Собрано: grka-keen-1.0.0-alpha.1.tar.gz` и `Собрано: grka-keen_1.0.0-alpha.1_all.ipk`; в списке файлов есть `opt/share/grka/bin/grka-watchdog`, `opt/share/grka/lib/watchdog.sh`, нет `S97mihomo`, `policy-route.sh`, `tests/`, `.tools/`.

- [ ] **Step 6: Commit**

```bash
git add build.sh build-ipk.sh install.sh rootfs/opt/share/grka/version docs/stage1-checklist.md tests/lint_test.sh
git commit -m "1.0.0-alpha.1: сборка и установщик под сторожа, проверка стиля, чек-лист стенда"
```

---

### Task 14: Финальная проверка ветки и ревью

**Files:** нет новых; исправления по итогам ревью.

- [ ] **Step 1: Полный прогон**

Run: `.tools/busybox.exe sh tests/run.sh`
Expected: `ВСЕ ТЕСТЫ ПРОШЛИ`.

- [ ] **Step 2: Ревью всей ветки**

Использовать superpowers:requesting-code-review для диапазона `main..release-1.0`. Отдельно попросить ревьюера проверить: идемпотентность правил при перестройках NDM, поведение при `kill -9` сторожа (ядро продолжает работать, новый сторож подхватывает его по `/proc`), безопасность CGI (CSRF, подстановки в shell), сохранность пользовательских данных при переходе с 0.0.2.

- [ ] **Step 3: Исправить найденное**

Каждое исправление — сначала тест, который воспроизводит проблему, потом код, потом полный прогон.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Этап 1: исправления по итогам ревью"
```
