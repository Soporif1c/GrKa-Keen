# shellcheck shell=sh
# GrKa Keen - общие функции

GRKA_REPO="Soporif1c/GrKa-Keen"
MIHOMO_REPO="MetaCubeX/mihomo"
DASHBOARD_URL="https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz"

PATH="/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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
	# $1 - owner/repo -> tag_name последнего релиза
	fetch "https://api.github.com/repos/$1/releases/latest" 2>/dev/null |
		sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

# Запуск команды в фоне, отвязанно от родителя.
# На стоковом busybox Keenetic нет setsid — используем его, только если он есть.
# Использование: detach <лог-файл> команда [аргументы...]
detach() {
	local log="$1"
	shift
	if command -v setsid >/dev/null 2>&1; then
		nohup setsid "$@" >> "$log" 2>&1 < /dev/null &
	else
		nohup "$@" >> "$log" 2>&1 < /dev/null &
	fi
}

CORE_BIN="/opt/sbin/mihomo"
CORE_GZ="/opt/share/grka/mihomo.gz"
CORE_TMP="/tmp/grka/mihomo"
COMPACT_FLAG="/opt/etc/mihomo/.compact"

compact_on() {
	[ -f "$COMPACT_FLAG" ]
}

# Есть ли ядро в каком-либо виде (бинарник или сжатый архив)
core_ready() {
	[ -x "$CORE_BIN" ] || [ -x "$CORE_TMP" ] || [ -f "$CORE_GZ" ]
}

# Путь к готовому к запуску бинарнику (без распаковки)
core_bin() {
	if [ -x "$CORE_BIN" ]; then
		echo "$CORE_BIN"
	elif [ -x "$CORE_TMP" ]; then
		echo "$CORE_TMP"
	fi
}

# Путь к бинарнику, при необходимости распаковав сжатое ядро в /tmp (RAM)
ensure_core() {
	local b
	b="$(core_bin)"
	if [ -z "$b" ] && [ -f "$CORE_GZ" ]; then
		mkdir -p /tmp/grka
		if gunzip -c "$CORE_GZ" > "$CORE_TMP" 2>/dev/null; then
			chmod +x "$CORE_TMP"
			b="$CORE_TMP"
		else
			rm -f "$CORE_TMP"
		fi
	fi
	echo "$b"
}

mihomo_arch() {
	# Определение архитектуры бинарника mihomo для этого устройства.
	# На Keenetic/Entware архитектура пакетов выглядит как aarch64-3.10, armv7sf-k3.2,
	# mipselsf-3.4, mipssf-3.4, x64-3.2 и т.п.
	local pkgarch=""
	if command -v opkg >/dev/null 2>&1; then
		pkgarch="$(opkg print-architecture 2>/dev/null | awk '$2 != "all" && $2 != "noarch" { a = $2 } END { print a }')"
	fi
	case "$pkgarch" in
		x64*|x86_64*)     echo "amd64-compatible"; return ;;
		x86*|i386*|i686*) echo "386"; return ;;
		aarch64*|arm64*)  echo "arm64"; return ;;
		armv7*)           echo "armv7"; return ;;
		armv5*)           echo "armv5"; return ;;
		mips64el*)        echo "mips64le"; return ;;
		mips64*)          echo "mips64"; return ;;
		mipsel*)          echo "mipsle-softfloat"; return ;;
		mips*)            echo "mips-softfloat"; return ;;
		riscv64*)         echo "riscv64"; return ;;
	esac
	case "$(uname -m)" in
		x86_64)    echo "amd64-compatible" ;;
		i386|i686) echo "386" ;;
		aarch64)   echo "arm64" ;;
		armv7*)    echo "armv7" ;;
		armv6*)    echo "armv6" ;;
		armv5*)    echo "armv5" ;;
		mips64)    echo "mips64" ;;
		mipsel)    echo "mipsle-softfloat" ;;
		mips)      echo "mips-softfloat" ;;
		riscv64)   echo "riscv64" ;;
		*)         echo "" ;;
	esac
}
