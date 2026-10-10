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
