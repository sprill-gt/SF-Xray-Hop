#!/usr/bin/env bash
# Explicit root/systemd test; DOES NOT install or modify the formal service.
# Supply official 26.9.9 and 26.3.27 binaries whose download was verified.
set -euo pipefail
[[ $EUID == 0 && $# == 2 ]] || { printf 'Usage (root): %s protected-core legacy-core\n' "$0" >&2; exit 2; }
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source_code=$SFXH_CODE
mkdir -p "$SFXH_CODE/.cache"
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/safety-live.XXXXXXXX"); export SFXH_TEST_ROOT
# shellcheck disable=SC1090
for module in common core health; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
trap '[[ $SFXH_TEST_ROOT == "$source_code"/.cache/safety-live.* ]] && rm -rf -- "$SFXH_TEST_ROOT"' EXIT
protected=$(realpath "$1"); legacy=$(realpath "$2")
formal_pid=$(systemctl show xray.service -p MainPID --value 2>/dev/null || :)
private_code=$SFXH_TEST_ROOT/private-source
for file in lib/core.sh lib/core-safety-worker.sh data/core-safety.json templates/model.jq; do
    install -D -m 600 "$source_code/$file" "$private_code/$file"
done
chmod 700 "$private_code"
SFXH_CODE=$private_code
sf_core_security "$protected"
SFXH_CODE=$source_code
[[ $(stat -c %a "$private_code/lib/core-safety-worker.sh") == 600 &&
   $(stat -c %a "$private_code/data/core-safety.json") == 600 &&
   $(stat -c %a "$private_code") == 700 ]]
printf 'PASS root-only bootstrap source: DynamicUser reads staged public inputs; private source modes unchanged\n'
record=$SFXH_VAR/cache/core-safety/$(sf_hash "$protected").json
jq -e '.status=="pass" and .tcpChecks==26 and .receiverControls==2 and .authenticatedControls==2' "$record" >/dev/null
printf 'PASS protected core: both authenticated identities, IPv4/IPv6/private DNS, 26 TCP blocks\n'
original=$(sf_hash "$record")
sf_core_security "$protected"
[[ $(sf_hash "$record") == "$original" ]]
printf 'PASS exact binary and policy reuse the recorded result\n'
if sf_core_security "$legacy"; then printf 'FAIL legacy core accepted\n' >&2; exit 1; fi
[[ ! -f $SFXH_VAR/cache/core-safety/$(sf_hash "$legacy").json ]]
printf 'PASS unprotected legacy core rejected without positive cache\n'
jq '.policySha256="obsolete"' "$record" > "$record.new"; mv "$record.new" "$record"
sf_core_security "$protected"
jq -e '.policySha256!="obsolete"' "$record" >/dev/null
printf 'PASS policy change invalidates cached evidence and reruns isolation\n'
[[ -z $(find "$SFXH_RUN/probes" -type f -print -quit) ]]
[[ $(systemctl show xray.service -p MainPID --value 2>/dev/null || :) == "$formal_pid" ]]
printf 'PASS owned probe records removed; formal service PID unchanged\n'
for binary in "$protected" "$legacy"; do
    version=$("$binary" version)
    printf '%s\n' "${version%%$'\n'*}"
done
sha256sum "$protected" "$legacy"
