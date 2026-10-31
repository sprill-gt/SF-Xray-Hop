#!/usr/bin/env bash
# Real lightweight resolver; HTTP and curl boundaries are fixtures.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck disable=SC1090
source "$root/lib/common.sh"
# shellcheck disable=SC1090
source "$root/lib/core.sh"
TEST_RELEASE_WORK=$(mktemp -d)
trap 'rm -rf -- "$TEST_RELEASE_WORK"' EXIT
sf_core_api() {
    printf '%s\n' "$1" >> "$TEST_RELEASE_WORK/requests"
    [[ ${TEST_HTTP_FAILURE:-0} == 0 ]] || return 1
    case "$1" in
      *tags\?*page=1) cp "$TEST_RELEASE_WORK/page.json" "$2" ;;
      *tags\?*page=2) [[ -f $TEST_RELEASE_WORK/page2.json ]] && cp "$TEST_RELEASE_WORK/page2.json" "$2" ;;
      */releases/tags/*)
        local tag=${1##*/}
        [[ $tag != "${TEST_FORBIDDEN_TAG:-}" ]] || return 1
        [[ -f $TEST_RELEASE_WORK/$tag.json ]] || return 4
        cp "$TEST_RELEASE_WORK/$tag.json" "$2" ;;
      *) return 1 ;;
    esac
}
choose() {
    local name
    for name in "$TEST_RELEASE_WORK"/v*.json; do [[ ! -f $name ]] || rm -- "$name"; done
    printf '%s\n' "$1" | jq 'map({name:.tag_name})' > "$TEST_RELEASE_WORK/page.json"
    while IFS= read -r name; do
        printf '%s\n' "$1" | jq --arg name "$name" '[.[]|select(.tag_name==$name)]|last|.+{draft:false,published_at:"2026-11-01"}' > "$TEST_RELEASE_WORK/$name.json"
    done < <(printf '%s\n' "$1" | jq -r '.[].tag_name')
    sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json"
    jq -e --arg tag "$2" --argjson pre "$3" '.tag_name==$tag and .prerelease==$pre' "$TEST_RELEASE_WORK/chosen.json" >/dev/null
}
choose '[{"tag_name":"v26.10.10","prerelease":false},{"tag_name":"v26.10.9","prerelease":true}]' v26.10.10 false
printf 'PASS numerically greater stable wins without fetching the lower Pre\n'
[[ $(grep -c '/releases/tags/' "$TEST_RELEASE_WORK/requests") == 1 ]]
choose '[{"tag_name":"v26.9.30","prerelease":false},{"tag_name":"v26.10.1","prerelease":true}]' v26.10.1 true
printf 'PASS numerically greater Pre wins regardless of tag order\n'
sf_release_metadata stable '' "$TEST_RELEASE_WORK/stable.json"
jq -e '.tag_name=="v26.9.30" and .prerelease==false' "$TEST_RELEASE_WORK/stable.json" >/dev/null
printf 'PASS explicit stable skips a higher Pre\n'
choose '[{"tag_name":"v26.10.1","prerelease":true},{"tag_name":"v26.10.1","prerelease":false}]' v26.10.1 false
printf 'PASS the same tag promoted to stable is resolved from its current Release\n'
printf '[{"name":"v99.0.0"},{"name":"v26.10.1"},{"name":"v100.0.0-beta"}]' > "$TEST_RELEASE_WORK/page.json"
sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json"
[[ $(jq -r .tag_name "$TEST_RELEASE_WORK/chosen.json") == v26.10.1 ]]
printf 'PASS unpublished 404 tags and nonnumeric tags never become candidates\n'
TEST_FORBIDDEN_TAG=v99.0.0
if sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json" 2>/dev/null; then exit 1; fi
unset TEST_FORBIDDEN_TAG
printf 'PASS a failed candidate lookup stops rather than selecting an older release\n'
jq -n '[range(0;100)|{name:("v1.0."+tostring)}]' > "$TEST_RELEASE_WORK/page.json"
if sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json" 2>/dev/null; then exit 1; fi
printf 'PASS a failed later index page cannot declare a partial result latest\n'
printf '[{"name":"v26.10.1"}]' > "$TEST_RELEASE_WORK/page2.json"
sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json"
[[ $(jq -r .tag_name "$TEST_RELEASE_WORK/chosen.json") == v26.10.1 ]]
printf 'PASS all index pages are compared numerically before Release lookup\n'
printf '[{"name":"v26.10.1"}]' > "$TEST_RELEASE_WORK/page.json"
printf '{"tag_name":"v26.10.1","draft":false,"prerelease":null,"published_at":"2026-11-01"}' > "$TEST_RELEASE_WORK/v26.10.1.json"
if sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json" 2>/dev/null; then exit 1; fi
printf 'PASS malformed Release flags stop instead of falling back\n'
TEST_HTTP_FAILURE=1
if sf_release_metadata auto '' "$TEST_RELEASE_WORK/chosen.json" 2>/dev/null; then exit 1; fi
printf 'PASS index HTTP failure stops without cached fallback\n'
if sf_project_release sprill-gt/SF-Xray-Hop auto '' "$TEST_RELEASE_WORK/chosen.json"; then exit 1; fi
rc=0
# Defined by the initial core.sh import; the later import restores the real API.
# shellcheck disable=SC2218
sf_project_release XTLS/Xray-core invalid '' "$TEST_RELEASE_WORK/chosen.json" || rc=$?
[[ $rc == 2 ]]
printf 'PASS manager policy stays separate and invalid channels stop before HTTP\n'
! grep -q '/releases?' "$TEST_RELEASE_WORK/requests"
# Exercise actual timeout/compression/status handling without a network call.
# shellcheck disable=SC1090
source "$root/lib/core.sh"
curl() {
    printf '%s\n' "$*" > "$TEST_RELEASE_WORK/curl-options"
    printf '%s' "$TEST_HTTP_CODE"
    return "$TEST_CURL_RC"
}
TEST_HTTP_CODE=200 TEST_CURL_RC=0
sf_core_api https://api.github.com/repos/XTLS/Xray-core/tags "$TEST_RELEASE_WORK/api.json"
grep -q -- '--compressed' "$TEST_RELEASE_WORK/curl-options"
grep -q -- '--max-time 30' "$TEST_RELEASE_WORK/curl-options"
grep -q -- '--max-filesize 2097152' "$TEST_RELEASE_WORK/curl-options"
TEST_HTTP_CODE=404
rc=0; sf_core_api https://api.github.com/repos/XTLS/Xray-core/tags "$TEST_RELEASE_WORK/api.json" || rc=$?
[[ $rc == 4 ]]
TEST_HTTP_CODE=403
rc=0; sf_core_api https://api.github.com/repos/XTLS/Xray-core/tags "$TEST_RELEASE_WORK/api.json" 2>/dev/null || rc=$?
[[ $rc == 1 ]]
TEST_CURL_RC=28
rc=0; sf_core_api https://api.github.com/repos/XTLS/Xray-core/tags "$TEST_RELEASE_WORK/api.json" 2>/dev/null || rc=$?
[[ $rc == 1 ]]
printf 'PASS metadata requests use compression, bounded size/time and distinguish 404 from errors\n'
printf 'TOTAL 12 lightweight release-selection/transport checks (HTTP mocked)\n'
