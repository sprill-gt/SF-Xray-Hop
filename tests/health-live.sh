#!/usr/bin/env bash
# Explicit lightweight Internet probe; only generated fixtures and loopback units.
# Does not read production credentials or install/restart the formal service.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1 SFXH_TEST_ROOT=$SFXH_CODE/.cache/live-health-root
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
work=$(sf_temp); pid=''; unit=''
trap 'sf_stop_probe "$pid" "$unit"; sf_remove_tree "$work"' EXIT
trap 'exit 130' INT TERM HUP
binary=${SFXH_TEST_CORE:?official core required}
sf_core_capabilities "$binary" "$work"
sf_target_check "$binary" archive.archlinux.org "$work"
printf 'PASS REALITY target includes unprivileged core TLS probe\n'
id="v26.9.9-$(sf_hash "$binary" | cut -c1-16)"
port=$(sf_local_port)
sf_build_initial_state "$binary" "$work" '隔离出口' 127.0.0.1 "$port" archive.archlinux.org "$id" 26.9.9 pre 0
cp "$work/state.json" "$work/exit-state.json"
sf_render "$work/exit-state.json" "$work/exit-all.json"
jq '.inbounds[0].listen="127.0.0.1"' "$work/exit-all.json" > "$work/exit.json"
sf_probe_start "$binary" "$work/exit.json" "$work/exit.log" 480
pid=$SF_PROBE_PID; unit=$SF_PROBE_UNIT
sf_wait_port "$port" "$pid"
sf_probe_state "$work/exit-state.json" "$binary" 127.0.0.1 "$port" "$work/no-hop" "$work/no-hop.json"
jq -e '.exitVerification.status=="confirmed"' "$work/no-hop.json" >/dev/null
printf 'PASS real single-node HTTPS and same-endpoint exit comparison\n'
sf_profile "$work/exit-state.json" relay > "$work/next-hop.json"
sf_build_initial_state "$binary" "$work" '隔离入口' 127.0.0.1 "$(sf_local_port)" archive.archlinux.org "$id" 26.9.9 pre 1
jq --slurpfile next "$work/next-hop.json" '.nextHop=$next[0]|.presentation.role="entry"|.presentation.downstreamName="隔离出口"' "$work/state.json" > "$work/entry-state.json"
sf_validate_state "$work/entry-state.json"
sf_probe_candidate "$work/entry-state.json" "$binary" "$binary" "$work/candidate"
jq -e '.exitVerification.status=="confirmed"' "$work/candidate/result.json" >/dev/null
printf 'PASS independent downstream baseline and complete chain compared with real sandboxed cores\n'
printf 'TOTAL 3 live health checks (loopback chain; shared public exit, not distinct VPS routing proof)\n'
