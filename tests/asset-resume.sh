#!/usr/bin/env bash
# Real retry/resume orchestration; no external network or core execution.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck disable=SC1090
source "$root/lib/common.sh"
# shellcheck disable=SC1090
source "$root/lib/core.sh"
TEST_ASSET_WORK=$(mktemp -d)
trap 'rm -rf -- "$TEST_ASSET_WORK"' EXIT
sleep() { command sleep 0.02; }
curl() {
    local dest='' count=0
    printf '%s\n' "$*" >> "$TEST_ASSET_WORK/options"
    while (($#)); do
        if [[ $1 == -o ]]; then dest=$2; shift 2; else shift; fi
    done
    [[ ! -f $TEST_ASSET_WORK/count ]] || count=$(cat "$TEST_ASSET_WORK/count")
    printf '%s\n' "$((count+1))" > "$TEST_ASSET_WORK/count"
    printf '%s\n' "$(wc -c < "$dest" 2>/dev/null || printf 0)" >> "$TEST_ASSET_WORK/offsets"
    if [[ $TEST_ASSET_MODE == unsupported ]]; then return 33; fi
    if [[ $TEST_ASSET_MODE == always-timeout || $count == 0 ]]; then
        printf abc >> "$dest"; return 28
    fi
    printf def >> "$dest"
}
TEST_ASSET_MODE=resume
sf_core_asset https://github.com/XTLS/Xray-core/releases/download/v26.10.31/Xray-linux-64.zip "$TEST_ASSET_WORK/core.zip" > "$TEST_ASSET_WORK/output" 2>&1
[[ $(cat "$TEST_ASSET_WORK/core.zip") == abcdef ]]
[[ $(cat "$TEST_ASSET_WORK/count") == 2 ]]
[[ $(tail -n 1 "$TEST_ASSET_WORK/offsets") == 3 ]]
grep -q -- '--continue-at -' "$TEST_ASSET_WORK/options"
grep -q -- '--max-time 180' "$TEST_ASSET_WORK/options"
printf 'PASS transient timeout resumes partial bytes instead of restarting\n'
rm "$TEST_ASSET_WORK/count"
TEST_ASSET_MODE=unsupported
if sf_core_asset unused "$TEST_ASSET_WORK/core.zip" > "$TEST_ASSET_WORK/output" 2>&1; then exit 1; fi
[[ $(cat "$TEST_ASSET_WORK/count") == 1 ]]
printf 'PASS unsupported Range fails without silently restarting or executing\n'
rm "$TEST_ASSET_WORK/count"
TEST_ASSET_MODE=always-timeout
if sf_core_asset unused "$TEST_ASSET_WORK/core.zip" > "$TEST_ASSET_WORK/output" 2>&1; then exit 1; fi
[[ $(cat "$TEST_ASSET_WORK/count") == 5 ]]
[[ ! -e $TEST_ASSET_WORK/core.zip.error ]]
printf 'PASS persistent timeout has a finite retry bound and cleans errors\n'
printf 'TOTAL 3 asset resume checks (curl mocked)\n'
