#!/bin/sh
. "$(dirname "$0")/lib/env.sh"
. "$GRKA_SRC/lib/common.sh"

# Ответ GitHub API на releases/latest. $1 - owner/repo, $2 - тег
stub_github_latest() {
	_ck="$(stub_curl_key "repos/$1/releases/latest")"
	echo 200 > "$STUB/curl/$_ck.code"
	printf '{"tag_name": "%s"}\n' "$2" > "$STUB/curl/$_ck.body"
}

# Скрипт подключается в подоболочке: так ему видны заглушки curl. До распаковки он не доходит
test_self_update_refuses_downgrade() {
	stub_github_latest "$GRKA_REPO" v0.0.2
	_o="$(GRKA_SELFUPDATE_COPY=1; . "$GRKA_SRC/scripts/self-update.sh" 2>&1)"
	assert_contains "$_o" "Обновлять нечего" "альфа не откатывается на последний стабильный 0.0.2"
	assert_not_contains "$(cat "$STUB/calls")" "releases/download"
}

run_tests "$0"
