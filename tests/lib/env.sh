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
