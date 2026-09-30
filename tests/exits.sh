#!/usr/bin/env bash
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1 SFXH_TEST_ROOT=$SFXH_CODE/.cache/exit-root
source "$SFXH_CODE/lib/common.sh"
source "$SFXH_CODE/lib/health.sh"
sf_paths; sf_dirs
work=$(sf_temp)
trap 'sf_remove_tree "$work"' EXIT
jq -n --arg at "$(sf_now)" '{observedAt:$at,exit:{endpoint:"https://example.com/ip",family:4,ips:["203.0.113.1","203.0.113.2"]}}' > "$work/expected"
jq '.exit.ips=["203.0.113.2"]' "$work/expected" > "$work/actual"
sf_exit_compare "$work/expected" "$work/actual" "$work/result"
printf 'PASS observed NAT pool subset is comparable\n'
# Regression: an expected address must not hide an additional unknown exit.
for observed in '["203.0.113.2","198.51.100.1"]' '["198.51.100.1","203.0.113.2"]'; do
    jq --argjson ips "$observed" '.exit.ips=$ips' "$work/expected" > "$work/actual"
    if sf_exit_compare "$work/expected" "$work/actual" "$work/result" 2>/dev/null; then
        printf 'FAIL mixed expected and unexpected exits were confirmed\n' >&2; exit 1
    fi
    jq -e '.status=="unconfirmed" and .unexpected==["198.51.100.1"]' "$work/result" >/dev/null
done
printf 'PASS mixed exits are unconfirmed regardless of sample order\n'
jq '.exit.ips=["198.51.100.1"]' "$work/expected" > "$work/actual"
if sf_exit_compare "$work/expected" "$work/actual" "$work/result" 2>/dev/null; then exit 1; fi
jq -e '.status=="mismatch"' "$work/result" >/dev/null
printf 'PASS disjoint observations stop submission without diagnosing a leak\n'
jq '.exit.family=6|.exit.ips=["2001:db8::1"]' "$work/expected" > "$work/actual"
if sf_exit_compare "$work/expected" "$work/actual" "$work/result" 2>/dev/null; then exit 1; fi
jq -e '.status=="unconfirmed"' "$work/result" >/dev/null
printf 'PASS address families are not compared as route failures\n'
jq '.exit.endpoint="https://example.net/ip"' "$work/expected" > "$work/actual"
if sf_exit_compare "$work/expected" "$work/actual" "$work/result" 2>/dev/null; then exit 1; fi
jq -e '.status=="unconfirmed"' "$work/result" >/dev/null
printf 'PASS unrelated endpoints are not marked confirmed\n'
for expression in '.exit.ips=[]' '.exit.family=5' 'del(.observedAt)' '.observedAt="2000-01-01T00:00:00Z"' '.observedAt="2999-01-01T00:00:00Z"'; do
    jq "$expression" "$work/expected" > "$work/actual"
    if sf_exit_compare "$work/expected" "$work/actual" "$work/result" 2>/dev/null; then exit 1; fi
    jq -e '.status=="unconfirmed"' "$work/result" >/dev/null
done
printf 'PASS empty, unknown-family, undated, stale and future observations are unconfirmed\n'
jq '.exit.ips=["203.0.113.2","203.0.113.2"]' "$work/expected" > "$work/actual"
sf_exit_compare "$work/expected" "$work/actual" "$work/result"
printf 'PASS duplicate expected samples remain comparable\n'
# Exercise the health orchestration, not just the comparison predicate. Both
# paths claim HTTPS success but Relay is deliberately observed at the wrong IP.
printf '{"nextHop":{"address":"exit.example.com"}}\n' > "$work/state.json"
sf_profile() { printf '{"profile":"%s"}\n' "$2"; }
sf_probe_profile() {
    local ip=198.51.100.1
    [[ $3 != */next-hop ]] || ip=203.0.113.1
    jq -n --arg at "$(sf_now)" --arg ip "$ip" '{status:"pass",observedAt:$at,exit:{endpoint:"https://example.com/ip",family:4,ips:[$ip]}}' > "$4"
}
if sf_probe_state "$work/state.json" unused 127.0.0.1 443 "$work/wrong-route" "$work/health" 2>/dev/null; then exit 1; fi
jq -e '.status=="mismatch"' "$work/wrong-route/exit-verification.json" >/dev/null
test ! -f "$work/health"
printf 'PASS full health orchestration rejects wrong Relay exit despite successful HTTPS\n'
sf_probe_profile() {
    local ips='["203.0.113.1","198.51.100.1"]'
    [[ $3 != */next-hop ]] || ips='["203.0.113.1"]'
    jq -n --arg at "$(sf_now)" --argjson ips "$ips" '{status:"pass",observedAt:$at,exit:{endpoint:"https://example.com/ip",family:4,ips:$ips}}' > "$4"
}
if sf_probe_state "$work/state.json" unused 127.0.0.1 443 "$work/mixed-route" "$work/health" 2>/dev/null; then exit 1; fi
jq -e '.status=="unconfirmed" and .reason=="unexpected-address"' "$work/mixed-route/exit-verification.json" >/dev/null
test ! -f "$work/health"
printf 'PASS full health orchestration rejects mixed Relay samples\nTOTAL 9 exit comparison groups\n'
