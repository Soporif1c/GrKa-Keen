#!/bin/sh
# Скачивает инструменты для тестов на Windows в .tools/: busybox-w32 с UTF-8 (оболочка), jq 1.8.1, shellcheck 0.10.0
set -e
cd "$(dirname "$0")/.."
mkdir -p .tools
dl() {
	[ -s "$2" ] || curl -fL --retry 2 -o "$2" "$1"
}
dl https://frippery.org/files/busybox/busybox64u.exe .tools/busybox.exe
dl https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-windows-amd64.exe .tools/jq.exe
if [ ! -s .tools/shellcheck.exe ]; then
	dl https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.zip .tools/shellcheck.zip
	unzip -o -q .tools/shellcheck.zip shellcheck.exe -d .tools
	rm -f .tools/shellcheck.zip
fi
.tools/busybox.exe | head -n 1
.tools/jq.exe --version
.tools/shellcheck.exe --version | sed -n 2p
