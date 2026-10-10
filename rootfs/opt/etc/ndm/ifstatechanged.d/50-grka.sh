#!/bin/sh
# GrKa Keen — изменилось состояние интерфейса. Флаг для сторожа, правила он проверит сам.
_run="${GRKA_RUN:-/tmp/grka}"
mkdir -p "$_run" && : > "$_run/dirty"
exit 0
