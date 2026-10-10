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
