#!/usr/bin/env bash
# Real install control flow, mocked system/deploy/network boundaries.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$SFXH_CODE/.cache"
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/install-r2.XXXXXXXX"); export SFXH_TEST_ROOT
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install operations benchmark ui; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
work=$(sf_temp); TEST_WORK=$work
trap 'sf_remove_tree "$work"' EXIT
sf_platform_check() { :; }; sf_existing_check() { :; }; sf_dependencies() { :; }
case $(uname -s) in MINGW*|MSYS*) sf_lock() { :; } ;; esac # Windows control-flow fixture only.
sf_installed() { [[ -f $TEST_WORK/installed.json ]]; }
sf_state() { printf '%s/installed.json\n' "$TEST_WORK"; }
sf_tty() { return 0; }
sf_ask_choice() { sf_fail 'Unexpected protocol/role question'; return 2; }
sf_ask_text() { sf_fail 'Unexpected parameter question'; return 2; }
sf_port_free() { [[ $1 == 443 ]]; }
sf_detect_address() { printf '203.0.113.10\n'; }
sf_release_metadata() {
    printf '%s\n' "$1" >> "$TEST_WORK/release-calls"
    jq -n --arg channel "$1" --arg version "${2:-26.9.30}" --argjson pre "${TEST_RELEASE_PRE:-true}" '{tag_name:("v"+$version),channel:$channel,prerelease:$pre}' > "$3"
}
sf_core_download() {
    [[ $3 == initialize ]]
    sf_core_capabilities "$SFXH_TEST_CORE" "$2"
    printf '%s-0123456789abcdef\n' "$(jq -r .tag_name "$1")"
}
sf_core_path() { printf '%s\n' "$SFXH_TEST_CORE"; }
sf_target_select() { [[ $2 == archive.archlinux.org ]]; printf '%s\n' "$2"; }
sf_deploy_manager() { :; }; sf_firewall_note() { :; }
sf_tx_apply() { sf_validate_state "$1" && cp "$1" "$TEST_WORK/installed.json"; }
sf_install > "$work/interactive.out" 2> "$work/interactive.err"
jq -e '.node.port==443 and .encryption.rtt=="0" and .reality.serverName=="archive.archlinux.org" and .core.channel=="pre" and .core.version=="26.9.30" and .presentation.role=="standalone"' "$work/installed.json" >/dev/null
[[ $(grep -c '^vless://' "$work/interactive.out") == 1 ]]
sf_uri_parse "$work/interactive.out" "$work/shown.json"
jq -e --slurpfile s "$work/installed.json" '.id==$s[0].identities.direct.id' "$work/shown.json" >/dev/null
[[ $(head -n 1 "$work/release-calls") == auto ]]
printf 'PASS default install compares stable and Pre, asks no protocol questions and shows exactly Direct once\n'
jq '.core.channel="pinned"|.core.pinnedVersion=.core.version|.node.name="既有节点"|.presentation.role="exit"' "$work/installed.json" > "$work/existing.json"
cp "$work/existing.json" "$work/installed.json"
sf_install --name 新名字 --rtt 1 --channel pre > "$work/repeated.out" 2>/dev/null
cmp "$work/existing.json" "$work/installed.json"
[[ ! -s $work/repeated.out ]]
printf 'PASS repeated install preserves existing identity, name, role and pinned channel\n'
rm "$work/installed.json"
sf_tty() { return 1; }
sf_install > "$work/noninteractive.out" 2> "$work/noninteractive.err"
[[ ! -s $work/noninteractive.out ]]
jq -e '.encryption.rtt=="0"' "$work/installed.json" >/dev/null
printf 'PASS noninteractive default install neither waits nor exports credentials\n'
cp "$work/installed.json" "$work/before-version-rejection.json"
cp "$work/release-calls" "$work/before-release-calls"
for version in 26.9.8 26.3.27 ''; do
    rc=0; sf_install --version "$version" > "$work/version-rejection.out" 2>&1 || rc=$?
    [[ $rc == 2 ]]
done
cmp "$work/installed.json" "$work/before-version-rejection.json"
cmp "$work/release-calls" "$work/before-release-calls"
printf 'PASS unsupported install versions fail before release lookup or changing an existing installation\n'
rm "$work/installed.json"
sf_install --version v26.9.9 --channel pre > "$work/selected.out" 2>&1
jq -e '.core.version=="26.9.9" and .core.channel=="pinned" and .core.pinnedVersion=="26.9.9"' "$work/installed.json" >/dev/null
printf 'PASS exact minimum install version takes precedence over channel option order\n'
rm "$work/installed.json"
TEST_RELEASE_PRE=false
sf_install > "$work/stable-install.out" 2>&1
[[ $(tail -n 1 "$work/release-calls") == auto ]]
jq -e '.core.channel=="stable" and .core.pinnedVersion==null' "$work/installed.json" >/dev/null
printf 'PASS automatic install records stable when stable wins the comparison\n'
printf 'TOTAL 6 install control-flow checks (deployment and network mocked)\n' 
