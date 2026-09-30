#!/usr/bin/env bash
# Isolated product contracts. Services and HTTP are fixtures, not VPS acceptance.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$SFXH_CODE/.cache"
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/product-r2.XXXXXXXX"); export SFXH_TEST_ROOT
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install operations benchmark ui; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
work=$(sf_temp); TEST_WORK=$work
trap 'sf_remove_tree "$work"' EXIT
count=0
pass() { count=$((count+1)); printf 'PASS %02d %s\n' "$count" "$1"; }
reject() { if "$@" > "$work/reject.out" 2>&1; then printf 'FAIL expected rejection: %s\n' "$1" >&2; exit 1; fi; }
for name in '中文 节点' 'node-01234567' 'literal $(touch SENTINEL) "quotes"'; do sf_safe_name "$name"; done
for name in '' $'line\nbreak' $'\033[31mred' $'\u202Ereversed' $'\u200Bhidden' $'\u0085control' $'\u00adsoft-hyphen' $'\xff'; do reject sf_safe_name "$name"; done
reject sf_safe_name "$(printf '%081d' 0)"
[[ ! -e SENTINEL ]]; pass 'names preserve literal shell characters and reject controls, bidi, invisibles and overflow'
binary=${SFXH_TEST_CORE:?official core required}
sf_core_capabilities "$binary" "$work"
sf_build_initial_state "$binary" "$work" '' example.com 443 archive.archlinux.org v26.9.9-0123456789abcdef 26.9.9 pre 0
sf_validate_state "$work/state.json"
jq -e '.schemaVersion==2 and .presentation.role=="standalone" and .node.name==("node-"+(.node.id[0:8])) and .encryption.rtt=="0"' "$work/state.json" >/dev/null
pass 'first initialization uses stable ID name, standalone and 0-RTT'
cp "$work/state.json" "$work/standalone.json"
sf_state() { printf '%s/state.json\n' "$TEST_WORK"; }
reject sf_view relay
[[ ! -s $work/reject.out || $(head -c 8 "$work/reject.out") != vless:// ]]
sf_view > "$work/default-view" 2>/dev/null
[[ $(grep -c '^vless://' "$work/default-view") == 1 ]]
sf_view json > "$work/client.json"
jq -e --slurpfile state "$work/state.json" '.outbounds[0].settings.id==$state[0].identities.direct.id' "$work/client.json" >/dev/null
pass 'default URI and JSON use Direct; standalone refuses misleading chain export'
jq '.presentation.role="exit"|.presentation.entry={source:"user",address:"entry.example.com",name:null}' "$work/state.json" > "$work/exit.json"
cp "$work/exit.json" "$work/state.json"
reject sf_view relay
grep -q entry.example.com "$work/reject.out"
sf_view handoff > "$work/handoff.txt" 2>/dev/null
sf_uri_parse "$work/handoff.txt" "$work/hop.json"
[[ $(sf_import_name "$work/hop.json") == "$(jq -r .node.name "$work/state.json")" ]]
pass 'exit shares handoff only and displays explicitly registered entry'
jq --slurpfile hop "$work/hop.json" '.nextHop=$hop[0]|.presentation.role="entry"|.presentation.downstreamName="中文 出口"' "$work/standalone.json" > "$work/state.json"
sf_validate_state "$work/state.json"
sf_profile "$work/state.json" relay > "$work/before-profile.json"
sf_next_rtt_values "$work/state.json" 1 "$work/downstream.json"
jq -e --slurpfile old "$work/state.json" 'del(.nextHop.encryption)==($old[0]|del(.nextHop.encryption)) and (.nextHop.encryption|split(".")[2])=="1rtt"' "$work/downstream.json" >/dev/null
sf_rtt_values "$work/downstream.json" 1 "$work/local.json"
jq -e --slurpfile old "$work/downstream.json" '.nextHop==$old[0].nextHop and .identities==$old[0].identities' "$work/local.json" >/dev/null
pass 'local and downstream RTT are independent and preserve credentials'
jq '.nextHop.encryption+=".unknown"' "$work/state.json" > "$work/unknown.json"
reject sf_next_rtt_values "$work/unknown.json" 0 "$work/rejected.json"
pass 'unknown encryption format stops instead of rewriting guessed positions'
jq '.node.name="新入口"|.presentation.downstreamName="出口二"' "$work/state.json" > "$work/renamed.json"
sf_render "$work/state.json" "$work/before-config.json"; sf_render "$work/renamed.json" "$work/after-config.json"
cmp "$work/before-config.json" "$work/after-config.json"
sf_profile "$work/renamed.json" relay > "$work/after-profile.json"
diff <(jq -S 'del(.remark)' "$work/before-profile.json") <(jq -S 'del(.remark)' "$work/after-profile.json")
pass 'renaming changes remarks only; runtime configuration and connection fields are identical'
jq 'del(.presentation)|.schemaVersion=1' "$work/state.json" > "$work/legacy.json"
sf_normalize_state "$work/legacy.json" "$work/migrated.json"; sf_validate_state "$work/migrated.json"
diff <(jq -S 'del(.schemaVersion,.presentation)' "$work/legacy.json") <(jq -S 'del(.schemaVersion,.presentation)' "$work/migrated.json")
pass 'legacy state normalization preserves all protocol material and channel'
sf_core_capabilities "$binary" "$work/inspect" inspect 2>/dev/null && exit 1 || :
mkdir "$work/inspect"; sf_core_capabilities "$binary" "$work/inspect" inspect
[[ ! -e $work/inspect/encryption.json && ! -e $work/inspect/reality-keys.json ]]
pass 'ordinary capability checks do not generate new long-term key material'
sf_curl_download() {
    printf '%s\n' "$1" >> "$TEST_WORK/requests"
    case "$1" in
      *'page=1') jq -n '[range(0;99)|{id:.,draft:true,prerelease:true,published_at:"2026-01-01",tag_name:"v99.0.0"}]+[{id:999,draft:false,prerelease:false,published_at:"2026-01-01",tag_name:"v99.1.0"}]' > "$2" ;;
      *'page=2') printf '[{"id":100,"draft":false,"prerelease":true,"published_at":"2026-01-02","tag_name":"v26.9.9"},{"id":101,"draft":false,"prerelease":true,"published_at":"2026-01-01","tag_name":"v26.10.1"}]' > "$2" ;;
      *) return 1 ;;
    esac
}
sf_release_metadata pre '' "$work/pre.json"; [[ $(jq -r .tag_name "$work/pre.json") == v26.10.1 ]]
sf_release_metadata stable '' "$work/stable.json"; [[ $(jq -r .tag_name "$work/stable.json") == v99.1.0 ]]
[[ $(sf_version_direction 26.10.1 26.9.9) == downgrade ]]
pass 'release pagination, exact channel filtering and numerical comparison ignore date and lexical traps'
sf_curl_download() { printf '[]' > "$2"; }
reject sf_self_check
pass 'absence of official project releases never falls back to experimental code'
sf_tty() { return 0; }
sf_uninstall <<< '' > "$work/cancelled" 2>&1 && exit 1 || [[ $? == 130 ]]
sf_uninstall < /dev/null > "$work/eof" 2>&1 && exit 1 || [[ $? == 130 ]]
[[ -f $work/state.json ]]; pass 'blank and EOF never authorize destructive uninstall'
sf_status() { :; }; sf_installed() { return 0; }; sf_pause() { :; }
sf_menu <<< '' > "$work/menu" 2>&1
grep -q '1. 启动 / 管理链式代理引导' "$work/menu"; grep -q '8. 更新 SF-Xray-Hop 脚本' "$work/menu"
[[ $(grep -cE '^[0-9]\. ' "$work/menu") == 10 ]]
! grep -q $'\033' "$work/menu"
pass 'R2 menu has exact ten numeric actions and Enter exits without credentials or ANSI'
printf 'TOTAL %d R2 product checks (network and services are fixtures)\n' "$count"
