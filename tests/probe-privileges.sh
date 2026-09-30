#!/usr/bin/env bash
# Actual temporary systemd units; no production service is restarted or reconfigured.
set -euo pipefail
[[ $EUID == 0 ]] || exit 2
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1 SFXH_TEST_ROOT=$SFXH_CODE/.cache/probe-root
source "$SFXH_CODE/lib/common.sh"
source "$SFXH_CODE/lib/health.sh"
sf_paths; sf_dirs
work=$(sf_temp); pid=''; unit=''
trap 'sf_stop_probe "$pid" "$unit"; sf_remove_tree "$work"' EXIT
port=$(sf_local_port)
printf '{"inbounds":[{"listen":"127.0.0.1","port":%s,"protocol":"http"}],"outbounds":[{"protocol":"blackhole"}]}\n' "$port" > "$work/config.json"
sf_probe_start "${SFXH_TEST_CORE:?}" "$work/config.json" "$work/log" 20
pid=$SF_PROBE_PID; unit=$SF_PROBE_UNIT
sf_wait_port "$port" "$pid" || { cat "$work/log"; exit 1; }
main=$(systemctl show "$unit" -p MainPID --value)
uid=$(awk '/^Uid:/{print $2}' "/proc/$main/status")
caps=$(awk '/^CapEff:/{print $2}' "/proc/$main/status")
test "$uid" -gt 0
test "$caps" = 0000000000000000
runuser -u nobody -- test ! -r "$work/config.json"
printf 'PASS probe UID=%s, effective capabilities=%s, private config inaccessible to nobody\n' "$uid" "$caps"
sf_stop_probe "$pid" "$unit"; pid=''
if systemctl is-active --quiet "$unit"; then exit 1; fi
printf 'PASS stop removes temporary unit and process\n'
sf_probe_start "${SFXH_TEST_CORE:?}" "$work/config.json" "$work/timeout-log" 2
pid=$SF_PROBE_PID; unit=$SF_PROBE_UNIT
sf_wait_port "$port" "$pid" || exit 1
if wait "$pid"; then exit 1; fi
pid=''
if systemctl is-active --quiet "$unit"; then exit 1; fi
printf 'PASS runtime timeout removes abandoned probe\n'
