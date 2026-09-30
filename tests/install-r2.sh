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
sf_installed() { [[ -f $TEST_WORK/installed.json ]]; }
sf_state() { printf '%s/installed.json\n' "$TEST_WORK"; }
sf_tty() { return 0; }
sf_ask_choice() { sf_fail 'Unexpected protocol/role question'; return 2; }
sf_ask_text() { sf_fail 'Unexpected parameter question'; return 2; }
sf_port_free() { [[ $1 == 443 ]]; }
sf_detect_address() { printf '203.0.113.10\n'; }
sf_release_metadata() { jq -n --arg channel "$1" '{tag_name:"v26.9.9",channel:$channel}' > "$3"; }
sf_core_download() {
    [[ $3 == initialize ]]
    sf_core_capabilities "$SFXH_TEST_CORE" "$2"
    printf 'v26.9.9-0123456789abcdef\n'
}
sf_core_path() { printf '%s\n' "$SFXH_TEST_CORE"; }
sf_target_select() { [[ $2 == archive.archlinux.org ]]; printf '%s\n' "$2"; }
sf_deploy_manager() { :; }; sf_firewall_note() { :; }
sf_tx_apply() { sf_validate_state "$1" && cp "$1" "$TEST_WORK/installed.json"; }
sf_install > "$work/interactive.out" 2> "$work/interactive.err"
jq -e '.node.port==443 and .encryption.rtt=="0" and .reality.serverName=="archive.archlinux.org" and .core.channel=="pre" and .presentation.role=="standalone"' "$work/installed.json" >/dev/null
[[ $(grep -c '^vless://' "$work/interactive.out") == 1 ]]
sf_uri_parse "$work/interactive.out" "$work/shown.json"
jq -e --slurpfile s "$work/installed.json" '.id==$s[0].identities.direct.id' "$work/shown.json" >/dev/null
printf 'PASS default install asks no protocol questions and shows exactly Direct once\n'
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
printf 'TOTAL 3 install control-flow checks (deployment and network mocked)\n'
