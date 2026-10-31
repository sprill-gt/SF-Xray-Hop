#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck disable=SC1090
for module in common manager core self; do source "$root/lib/$module.sh"; done
TEST_SELF_CHANNEL_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_SELF_CHANNEL_ROOT"' EXIT
SFXH_CODE=$TEST_SELF_CHANNEL_ROOT/code; SFXH_INSTALL=$TEST_SELF_CHANNEL_ROOT/install
mkdir -p "$SFXH_CODE" "$SFXH_INSTALL"
printf '{"id":1,"tag_name":"v1.1.0","draft":false,"prerelease":false,"published_at":"2026-11-01"}\n' > "$TEST_SELF_CHANNEL_ROOT/stable.json"
printf '{"id":2,"tag_name":"v1.1.1","draft":false,"prerelease":true,"published_at":"2026-11-01"}\n' > "$TEST_SELF_CHANNEL_ROOT/pre.json"
jq -s . "$TEST_SELF_CHANNEL_ROOT/stable.json" "$TEST_SELF_CHANNEL_ROOT/pre.json" > "$TEST_SELF_CHANNEL_ROOT/list.json"
sf_curl_download() {
    printf '%s\n' "$1" >> "$TEST_SELF_CHANNEL_ROOT/requests"
    case "$1" in
        *releases\?*) cp "$TEST_SELF_CHANNEL_ROOT/list.json" "$2" ;;
        */v1.1.0) cp "$TEST_SELF_CHANNEL_ROOT/stable.json" "$2" ;;
        */v1.1.1) cp "$TEST_SELF_CHANNEL_ROOT/pre.json" "$2" ;;
        *) return 1 ;;
    esac
}
[[ $(sf_self_channel) == stable ]]
sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json"
jq -e '.tag_name=="v1.1.0"' "$TEST_SELF_CHANNEL_ROOT/chosen.json" >/dev/null
sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json" '' '' pre
jq -e '.tag_name=="v1.1.1" and .prerelease==true' "$TEST_SELF_CHANNEL_ROOT/chosen.json" >/dev/null
jq -n '{kind:"github-release",version:"1.1.1",commit:("a"*40),archiveSha256:("b"*64),prerelease:true}' > "$SFXH_CODE/source.json"
[[ $(sf_self_channel) == pre ]]
sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json"
jq -e '.tag_name=="v1.1.1"' "$TEST_SELF_CHANNEL_ROOT/chosen.json" >/dev/null
sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json" '' '' stable
jq -e '.tag_name=="v1.1.0" and .prerelease==false' "$TEST_SELF_CHANNEL_ROOT/chosen.json" >/dev/null
jq -s . "$TEST_SELF_CHANNEL_ROOT/stable.json" > "$TEST_SELF_CHANNEL_ROOT/list.json"
if sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json" '' '' pre; then exit 1; fi
if sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json" '' '' invalid; then exit 1; fi
if sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json" '' 1; then exit 1; fi
sf_self_resolve "$TEST_SELF_CHANNEL_ROOT/chosen.json" 1.1.1 1
jq -e '.prerelease==true' "$TEST_SELF_CHANNEL_ROOT/chosen.json" >/dev/null
printf 'PASS script stable/pre resolution, source-based defaults, legacy opt-in and no fallback\n'
