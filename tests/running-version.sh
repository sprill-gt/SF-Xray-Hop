#!/usr/bin/env bash
# Real Linux process inspection; the formal xray.service is never touched.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ $(uname -s) == Linux ]] || { printf 'Linux /proc is required.\n' >&2; exit 2; }
export SFXH_TEST_MODE=1
mkdir -p "$SFXH_CODE/.cache"
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/version.XXXXXXXX"); export SFXH_TEST_ROOT
source "$SFXH_CODE/lib/common.sh"
source "$SFXH_CODE/lib/product.sh"
sf_paths; sf_dirs
work=$(sf_temp); pid=''
cleanup() { [[ -z $pid ]] || { kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; }; sf_remove_tree "$work"; }
trap cleanup EXIT
binary=${SFXH_TEST_CORE:?verified Linux core required}
version=$("$binary" version); version=${version%%$'\n'*}
[[ $version =~ ^Xray[[:space:]]([0-9]+\.[0-9]+\.[0-9]+) ]]
expected=${BASH_REMATCH[1]}
mkdir -p "$SFXH_VAR/cores/test-version"
install -m 755 "$binary" "$SFXH_VAR/cores/test-version/xray"
printf '{"log":{"loglevel":"none"},"outbounds":[{"protocol":"freedom"}]}\n' > "$work/config.json"
"$SFXH_VAR/cores/test-version/xray" run -config "$work/config.json" > "$work/core.log" 2>&1 &
pid=$!
TEST_RUNNING_CORE_PID=$pid
systemctl() { printf '%s\n' "$TEST_RUNNING_CORE_PID"; }
for ((attempt=0;attempt<100;attempt++)); do
    [[ $(readlink "/proc/$pid/exe") != "$SFXH_VAR/cores/test-version/xray" ]] || break
    kill -0 "$pid"
    sleep .02
done
for ((attempt=0;attempt<50;attempt++)); do
    [[ $(sf_running_core_version) == "$expected" ]]
done
printf 'PASS 50 running-process version reads under pipefail\n'
kill "$pid"; wait "$pid" || :
if sf_running_core_version >/dev/null; then exit 1; fi
printf 'PASS stopped process is unknown, not the configured version\n'
