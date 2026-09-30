#!/usr/bin/env bash
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1
export SFXH_TEST_ROOT=${SFXH_TEST_ROOT:-$SFXH_CODE/.cache/unit-root}
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install operations benchmark ui; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths
sf_dirs
mkdir -p "$SFXH_TEST_ROOT/fixtures"
work=$SFXH_TEST_ROOT/fixtures
count=0
pass() { count=$((count+1)); printf 'PASS %02d %s\n' "$count" "$1"; }
reject() { if "$@" > "$work/rejected.stdout" 2> "$work/rejected.stderr"; then printf 'FAIL expected rejection: %s\n' "$1" >&2; exit 1; fi; }
for os in 'debian 13' 'debian 13.1' 'debian 13.3' 'debian 13.7' 'ubuntu 24.04' 'ubuntu 24.04.3'; do
    read -r id version <<< "$os"
    printf 'ID="%s"\nVERSION_ID="%s"\n' "$id" "$version" > "$work/os-release"
    sf_os_read "$work/os-release"; pass "platform $os"
done
for os in 'ubuntu 22.04' 'ubuntu 22.04.5' 'ubuntu 24.10' 'ubuntu 20.04' 'debian 12' 'debian 12.9' 'debian 11' 'linuxmint 24.04'; do
    read -r id version <<< "$os"
    printf 'ID=%s\nVERSION_ID=%s\nID_LIKE=ubuntu\n' "$id" "$version" > "$work/os-release"
    reject sf_os_read "$work/os-release"; pass "reject platform $os"
done
printf 'ID=$(touch SENTINEL)\nVERSION_ID=13\n' > "$work/os-release"
reject sf_os_read "$work/os-release"; [[ ! -e SENTINEL ]]; pass 'os-release data never executed'
for host in example.com 203.0.113.10 2001:db8::1; do sf_host_valid "$host"; done
for host in '-bad.example' 'x;touch.example' '256.1.1.1' 'x..example' ':::' '2001::a::b' '12345::1' 'a.-bad.example' '1:2:3:4:5:6:7:8:9'; do reject sf_host_valid "$host"; done
pass 'host input validation'
binary=${SFXH_TEST_CORE:?set path to official xray binary}
sf_core_capabilities "$binary" "$work"
pass 'official vlessenc and x25519 output adapters'
sf_build_initial_state "$binary" "$work" '入口 中文 % + & / ? #' example.com 443 www.example.com v26.9.9-0123456789abcdef 26.9.9 pre 0
sf_validate_state "$work/state.json"
sf_render "$work/state.json" "$work/server.json"
sf_core_test "$binary" "$work/server.json" "$work/server-test.log"
pass 'core validates one-inbound dual-user baseline'
jq -e '.inbounds|length==1' "$work/server.json" >/dev/null
jq -e '.inbounds[0].settings.clients|length==2 and .[0].id!=.[1].id' "$work/server.json" >/dev/null
jq -e '.routing.rules[0].outboundTag=="direct-freedom" and .routing.rules[1].outboundTag=="direct-freedom" and .outbounds[0].protocol=="blackhole"' "$work/server.json" >/dev/null
pass 'two identities and explicit default-deny routing'
sf_profile "$work/state.json" relay > "$work/profile.json"
sf_uri_encode "$work/profile.json" > "$work/uri.txt"
sf_uri_parse "$work/uri.txt" "$work/parsed.json"
diff <(jq -S . "$work/profile.json") <(jq -S . "$work/parsed.json")
pass 'long ML-KEM credential and Chinese remark lossless round-trip'
jq '.address="2001:db8::1"|.path="/a%2F+b?x=1&y=中文"' "$work/profile.json" > "$work/v6.json"
sf_uri_encode "$work/v6.json" > "$work/v6-uri.txt"
sf_uri_parse "$work/v6-uri.txt" "$work/v6-parsed.json"
diff <(jq -S . "$work/v6.json") <(jq -S . "$work/v6-parsed.json")
pass 'IPv6 plus and percent decode exactly once'
for mutation in duplicate unsupported nul newline malformed protocol fingerprint mode password; do
    jq -Rr --arg op "$mutation" '
      if $op=="duplicate" then sub("&flow=";"&mode=auto&flow=")
      elif $op=="unsupported" then sub("&flow=";"&extra=%7B%7D&flow=")
      elif $op=="nul" then .+"%00"
      elif $op=="newline" then .+"%0A"
      elif $op=="malformed" then .+"%GG"
      elif $op=="protocol" then sub("type=xhttp";"type=tcp")
      elif $op=="fingerprint" then sub("fp=chrome";"fp=randomized")
      elif $op=="mode" then sub("mode=auto";"mode=stream-one")
      else sub("pbk=[^&]+";"pbk=short") end' "$work/uri.txt" > "$work/bad-uri.txt"
    reject sf_uri_parse "$work/bad-uri.txt" "$work/bad-profile.json"
    pass "reject URI $mutation"
done
sf_client_config "$work/profile.json" "$work/client.json"
sf_core_test "$binary" "$work/client.json" "$work/client-test.log"
jq -e '..|objects|select(has("privateKey") or has("decryption"))' "$work/client.json" >/dev/null && exit 1
pass 'complete client JSON validates and contains no server private material'
sf_rtt_values "$work/state.json" 1 "$work/state1.json"
sf_validate_state "$work/state1.json"
jq -e --slurpfile old "$work/state.json" '(.encryption.decryption|split(".")[2])=="0s" and (.encryption.encryption|split(".")[2])=="1rtt" and .identities==$old[0].identities and (.encryption.decryption|split(".")[3])==($old[0].encryption.decryption|split(".")[3])' "$work/state1.json" >/dev/null
sf_render "$work/state1.json" "$work/server1.json"
sf_core_test "$binary" "$work/server1.json" "$work/server1-test.log"
sf_rtt_values "$work/state1.json" 0 "$work/state0-again.json"
diff <(jq -S . "$work/state.json") <(jq -S . "$work/state0-again.json")
pass 'RTT switch preserves credentials and restores generator ticket setting'
jq --slurpfile hop "$work/v6.json" '.nextHop=$hop[0]|.presentation.role="entry"|.presentation.downstreamName="测试出口"' "$work/state.json" > "$work/chained-state.json"
sf_render "$work/chained-state.json" "$work/chained-server.json"
jq -e '.routing.rules[0].outboundTag=="direct-freedom" and .routing.rules[1].outboundTag=="sf-xray-hop-next-hop"' "$work/chained-server.json" >/dev/null
sf_profile "$work/chained-state.json" relay > "$work/chained-profile.json"
diff <(jq -S 'del(.remark)' "$work/profile.json") <(jq -S 'del(.remark)' "$work/chained-profile.json")
pass 'next-hop change preserves connection fields while remark explains chain'
sf_core_test "$binary" "$work/chained-server.json" "$work/chained-server-test.log"
pass 'core validates real chained outbound'
printf '%s\n' 'vless://secret@host?encryption=secret' '01234567-89ab-cdef-0123-456789abcdef' 'abcdefghijklmnopqrstuvwxyzABCDEFGH_123456' | sf_redact > "$work/redacted.txt"
! grep -Eq 'vless://|01234567|abcdefghijklmnopqrstuvwxyz' "$work/redacted.txt"
pass 'logs redact credentials and identifiers'
printf 'not known\n' > "$work/unknown-generator.txt"
reject sf_parse_encryption "$work/unknown-generator.txt" "$work/no.json"
pass 'unknown generator format fails closed'
printf 'TOTAL %d unit checks\n' "$count"
