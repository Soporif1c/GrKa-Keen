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
