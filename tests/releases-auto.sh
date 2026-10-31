#!/usr/bin/env bash
# Real resolver, fixture HTTP pages. No core download, service or host mutation.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck disable=SC1090
source "$root/lib/common.sh"
# shellcheck disable=SC1090
source "$root/lib/core.sh"
TEST_RELEASE_WORK=$(mktemp -d)
trap 'rm -rf -- "$TEST_RELEASE_WORK"' EXIT
sf_curl_download() {
    [[ ${TEST_HTTP_FAILURE:-0} == 0 ]] || return 22
    case "$1" in *'page=1') cp "$TEST_RELEASE_WORK/page.json" "$2" ;; *) return 22 ;; esac
}
choose() {
    printf '%s\n' "$1" | jq 'to_entries|map(.value+{id:.key,draft:false,published_at:"2026-10-31"})' > "$TEST_RELEASE_WORK/page.json"
    sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json"
    jq -e --arg tag "$2" --argjson pre "$3" '.tag_name==$tag and .prerelease==$pre' "$TEST_RELEASE_WORK/chosen.json" >/dev/null
}
choose '[{"tag_name":"v26.10.10","prerelease":false},{"tag_name":"v26.10.9","prerelease":true}]' v26.10.10 false
printf 'PASS stable wins when numerically greater than Pre\n'
choose '[{"tag_name":"v26.9.30","prerelease":false},{"tag_name":"v26.10.1","prerelease":true}]' v26.10.1 true
printf 'PASS Pre wins when numerically greater than stable\n'
choose '[{"tag_name":"v26.10.1","prerelease":false},{"tag_name":"v26.10.1","prerelease":true}]' v26.10.1 false
choose '[{"tag_name":"v26.10.1","prerelease":true},{"tag_name":"v26.10.1","prerelease":false}]' v26.10.1 false
printf 'PASS equal versions prefer stable regardless of API order\n'
choose '[{"tag_name":"v26.10.1","prerelease":false}]' v26.10.1 false
choose '[{"tag_name":"v26.10.1","prerelease":true}]' v26.10.1 true
printf 'PASS a published release in either channel can be selected\n'
jq -n '[range(0;99)|{id:.,draft:true,prerelease:true,published_at:"2026-10-31",tag_name:"v99.0.0"}]+[{id:999,draft:false,prerelease:false,published_at:"2026-10-31",tag_name:"v26.10.1"}]' > "$TEST_RELEASE_WORK/page.json"
if sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json" 2>/dev/null; then exit 1; fi
printf 'PASS failed later page never declares an incomplete result latest\n'
printf '[{"id":1,"draft":true,"tag_name":"v99.0.0","prerelease":true,"published_at":"2026-10-31"},{"id":2,"draft":false,"tag_name":"v98.0.0","prerelease":null,"published_at":"2026-10-31"},{"id":3,"draft":false,"tag_name":"v27.0.0-beta","prerelease":true,"published_at":"2026-10-31"}]' > "$TEST_RELEASE_WORK/page.json"
if sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json" 2>/dev/null; then exit 1; fi
printf 'PASS drafts, invalid channel flags and nonnumeric tags are excluded\n'
TEST_HTTP_FAILURE=1
if sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json" 2>/dev/null; then exit 1; fi
printf 'PASS API failure stops without cached or channel fallback\n'
if sf_project_release sprill-gt/SF-Xray-Hop auto '' "$TEST_RELEASE_WORK/chosen.json"; then exit 1; fi
printf 'PASS core automatic policy does not broaden manager release selection\n'
rc=0
sf_project_release XTLS/Xray-core invalid '' "$TEST_RELEASE_WORK/chosen.json" || rc=$?
[[ $rc == 2 ]]
printf 'PASS invalid channel stops before HTTP even when caller handles errors\n'
printf 'TOTAL 9 automatic release-selection checks (HTTP mocked)\n'
