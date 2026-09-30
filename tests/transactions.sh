#!/usr/bin/env bash
# Fault injection of transaction orchestration. Real services/network are mocked.
set -uo pipefail
umask 077
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1
export SFXH_TEST_ROOT=$SFXH_CODE/.cache/transaction-root
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install operations benchmark ui; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths
sf_dirs || exit 1
work=$(sf_temp) || exit 1
TEST_WORK=$work
trap 'sf_remove_tree "$work"' EXIT
count=0
pass() { count=$((count+1)); printf 'PASS %02d %s\n' "$count" "$1"; }
require() { "$@" || { printf 'FAIL %s\n' "$1" >&2; exit 1; }; }
reject() { if "$@" > "$work/rejected.out" 2>&1; then printf 'FAIL expected rejection: %s\n' "$1" >&2; exit 1; fi; }

case $(uname -s) in
    MINGW*|MSYS*)
        printf 'NOTE Windows: flock, symlink activation and boot/process identity are simulated.\n'
        sf_lock() { :; }
        sf_unlock() { :; }
        sf_activate() { printf '%s\n' "$1" > "$SFXH_ETC/active-simulated.tmp" && mv -f "$SFXH_ETC/active-simulated.tmp" "$SFXH_ETC/active-simulated"; }
        sf_generation() { [[ -f $SFXH_ETC/active-simulated ]] && printf '%s/generations/%s\n' "$SFXH_ETC" "$(cat "$SFXH_ETC/active-simulated")"; }
        sf_journal() { jq -n --arg old "$1" --arg new "$2" '{old:$old,new:$new,phase:"switching"}' > "$SFXH_ETC/transaction.json"; }
        sf_journal_owner_alive() { return 1; }
        ;;
esac
systemctl() {
    printf '%s\n' "$*" >> "$TEST_WORK/service-calls"
    if [[ ${1:-} == reset-failed ]]; then rm -f "$TEST_WORK/start-limited"; fi
    if [[ ${1:-} == restart && -f $TEST_WORK/start-limited ]]; then return 1; fi
    if [[ ${1:-} == restart && -f $TEST_WORK/fail-restart ]]; then rm -f "$TEST_WORK/fail-restart"; return 1; fi
}
sf_probe_candidate() { [[ ! -f $TEST_WORK/fail-candidate ]]; }
sf_core_security() { printf 'checked\n' >> "$TEST_WORK/safety-calls"; [[ ! -f $TEST_WORK/fail-safety ]]; }
sf_service_active() { [[ ! -f $TEST_WORK/service-stopped ]]; }
sf_service_ready() { sf_service_active; }
sf_health_current() {
    if [[ -f $TEST_WORK/fail-health ]]; then rm -f "$TEST_WORK/fail-health"; return 1; fi
    if [[ -f $TEST_WORK/interrupt-health ]]; then rm -f "$TEST_WORK/interrupt-health"; kill -TERM "$BASHPID"; return 1; fi
    if [[ -f $TEST_WORK/kill-health ]]; then rm -f "$TEST_WORK/kill-health"; kill -KILL "$BASHPID"; return 1; fi
    return 0
}

binary=${SFXH_TEST_CORE:?set official Xray binary}
require sf_core_capabilities "$binary" "$work"
id="v26.9.9-$(sf_hash "$binary" | cut -c1-16)"
mkdir -p "$SFXH_VAR/cores/$id"
cp "$binary" "$SFXH_VAR/cores/$id/xray" && chmod 755 "$SFXH_VAR/cores/$id/xray" || exit 1
jq -n --arg id "$id" --arg hash "$(sf_hash "$binary")" '{id:$id,version:"26.9.9",sha256:$hash,verified:false}' > "$SFXH_VAR/cores/$id/metadata.json"
require sf_build_initial_state "$binary" "$work" '事务测试' example.com 443 www.example.com "$id" 26.9.9 pre 0
require sf_tx_apply "$work/state.json" test-initial
old=$(sf_generation) || exit 1
require sf_generation_integrity "$old"
require jq -e '.verified==true' "$SFXH_VAR/cores/$id/metadata.json"
pass 'commit coherent generation and mark core verified'

jq '.node.name="候选节点"|.node.port=444' "$work/state.json" > "$work/candidate.json"
calls=$(wc -l < "$work/service-calls")
touch "$work/fail-safety"
reject sf_tx_apply "$work/candidate.json" test-safety-fail
rm -f "$work/fail-safety"
require test "$(sf_generation)" = "$old"
require test ! -f "$SFXH_ETC/transaction.json"
require test "$(wc -l < "$work/service-calls")" = "$calls"
pass 'unsafe candidate is rejected before activation or service restart'
touch "$work/fail-candidate"
reject sf_tx_apply "$work/candidate.json" test-candidate-fail
rm -f "$work/fail-candidate"
require test "$(sf_generation)" = "$old"
pass 'candidate failure preserves active generation'

jq '.identities.relay.id=.identities.direct.id' "$work/candidate.json" > "$work/invalid.json"
reject sf_tx_apply "$work/invalid.json" test-invalid
require test "$(sf_generation)" = "$old"
pass 'invalid identity configuration never activated'

for failure in fail-restart fail-health interrupt-health; do
    touch "$work/$failure"
    reject sf_tx_apply "$work/candidate.json" "test-$failure"
    require test "$(sf_generation)" = "$old"
    require test ! -f "$SFXH_ETC/transaction.json"
    pass "$failure restores previous config state and core"
done

SF_EXPECT_GENERATION=stale-generation
reject sf_tx_apply "$work/candidate.json" test-stale
unset SF_EXPECT_GENERATION
require test "$(sf_generation)" = "$old"
pass 'stale writer cannot overwrite newer generation'

touch "$work/kill-health"
reject sf_tx_apply "$work/candidate.json" test-hard-kill
require test -f "$SFXH_ETC/transaction.json"
require test "$(sf_generation)" != "$old"
require sf_recover boot
require test "$(sf_generation)" = "$old"
require test ! -f "$SFXH_ETC/transaction.json"
pass 'SIGKILL journal recovery returns to previous verified generation'

cp "$old/config.json" "$work/intact.json"
printf '\n ' >> "$old/config.json"
reject sf_tx_apply "$work/candidate.json" test-tamper
cp "$work/intact.json" "$old/config.json"
require sf_generation_integrity "$old"
pass 'external config tampering stops transaction'

require sf_tx_apply "$work/candidate.json" test-final
require test "$(sf_generation)" != "$old"
require jq -e '.node.name=="候选节点"' "$(sf_state)"
pass 'successful edit commits after fault recovery'
touch "$TEST_WORK/start-limited"
require sf_service_restart
require test ! -f "$TEST_WORK/start-limited"
pass 'explicit managed restart clears candidate crash rate limiting'
calls=$(wc -l < "$TEST_WORK/service-calls")
current=$(sf_state)
jq -n --arg g "$(basename "$(dirname "$current")")" '{generation:$g,checkedAt:"2026-01-01T00:00:00Z",status:"pass"}' > "$SFXH_VAR/cache/health.json"
jq '.node.name="只改备注"|.fingerprint="firefox"' "$current" > "$work/metadata.json"
touch "$work/fail-candidate"
require sf_tx_apply "$work/metadata.json" metadata-only
require test "$(wc -l < "$TEST_WORK/service-calls")" = "$calls"
require test -f "$work/fail-candidate"
require sf_generation_integrity "$(sf_generation)"
pass 'name and exported fingerprint commit coherently without probes or restart'
metadata_generation=$(sf_generation)
require jq -e --arg g "${metadata_generation##*/}" '.generation==$g and .checkedAt=="2026-01-01T00:00:00Z"' "$SFXH_VAR/cache/health.json"
pass 'metadata keeps original health observation time'
jq -n --arg old "$(basename "$(dirname "$current")")" --arg new "${metadata_generation##*/}" \
  '{old:$old,new:$new,phase:"metadata",bootId:"dead-owner",pid:2147483647,processStart:"0"}' > "$SFXH_ETC/transaction.json"
require sf_recover
require test "$(sf_generation)" = "$(dirname "$current")"
require test "$(wc -l < "$TEST_WORK/service-calls")" = "$calls"
require sf_tx_apply "$work/metadata.json" retry-metadata
metadata_generation=$(sf_generation)
pass 'interrupted metadata transaction restores coherently without restarting'
require sf_tx_apply "$work/metadata.json" identical
require test "$(sf_generation)" = "$metadata_generation"
require test "$(wc -l < "$TEST_WORK/service-calls")" = "$calls"
rm -f "$work/fail-candidate"
pass 'identical state and core return without backup generation or restart'
touch "$TEST_WORK/service-stopped"
require sf_tx_apply "$work/metadata.json" restore-stopped
require test "$(sf_generation)" != "$metadata_generation"
rm -f "$TEST_WORK/service-stopped"
pass 'retained installation with stopped service is revalidated and restarted'

# Offline rollback uses a different binary hash but the same protocol capabilities.
# Appending an inert byte to the official ELF is only a test fixture, never shipped.
cp "$binary" "$work/history-core"
printf '\0' >> "$work/history-core"
history_id="v26.9.9-$(sf_hash "$work/history-core" | cut -c1-16)"
mkdir -p "$SFXH_VAR/cores/$history_id"
install -m 755 "$work/history-core" "$SFXH_VAR/cores/$history_id/xray"
jq -n --arg id "$history_id" --arg hash "$(sf_hash "$work/history-core")" \
    '{id:$id,version:"26.9.9",sha256:$hash,verified:true}' > "$SFXH_VAR/cores/$history_id/metadata.json"
jq --arg id "$history_id" '.core.id=$id|.core.channel="pinned"|.core.pinnedVersion="26.9.9"' "$(sf_state)" > "$work/offline.json"
last_good=$(cat "$SFXH_ETC/last-good")
before_offline=$(sf_generation)
calls=$(wc -l < "$work/service-calls")
touch "$work/fail-safety"
reject sf_tx_apply "$work/offline.json" offline-unsafe-core offline
rm -f "$work/fail-safety"
require test "$(sf_generation)" = "$before_offline"
require test "$(wc -l < "$work/service-calls")" = "$calls"
require test ! -f "$SFXH_ETC/transaction.json"
pass 'offline rollback still rejects a historically verified core that fails safety policy'
touch "$work/fail-candidate" "$work/fail-health"
require sf_tx_apply "$work/offline.json" offline-recovery offline
require test -f "$work/fail-candidate"
require test -f "$work/fail-health"
require test "$(cat "$SFXH_ETC/last-good")" = "$last_good"
require jq -e '.status=="unverified-offline"' "$SFXH_VAR/cache/health.json"
pass 'explicit offline core recovery never claims network validation or advances last-good'
jq '.node.port=445' "$work/offline.json" > "$work/offline-invalid.json"
reject sf_tx_apply "$work/offline-invalid.json" offline-change-route offline
pass 'offline recovery cannot change node or downstream configuration'
offline_generation=$(sf_generation)
jq --arg id "$id" '.core.id=$id' "$work/offline.json" > "$work/offline-retry.json"
touch "$work/fail-restart"
reject sf_tx_apply "$work/offline-retry.json" offline-failed-start offline
require test "$(sf_generation)" = "$offline_generation"
require test -f "$work/fail-health"
pass 'failed offline startup restores previous core without external network probes'
rm -f "$work/fail-candidate" "$work/fail-health"
touch "$work/service-stopped" "$work/fail-candidate" "$work/fail-health"
calls=$(wc -l < "$work/service-calls")
jq '.node.name="停止状态下重命名"' "$(sf_state)" > "$work/metadata-stopped.json"
require sf_tx_apply "$work/metadata-stopped.json" rename-stopped online metadata
require test "$(wc -l < "$work/service-calls")" = "$calls"
require test -f "$work/service-stopped"
require test -f "$work/fail-candidate"
pass 'metadata-only edit preserves a stopped service and never probes or starts it'
reject sf_tx_apply "$work/offline-invalid.json" forbidden-runtime-change online metadata
pass 'metadata intent cannot bypass runtime-change validation'
printf 'TOTAL %d transaction checks (services and network mocked)\n' "$count"
