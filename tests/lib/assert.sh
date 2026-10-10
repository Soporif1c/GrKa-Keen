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
