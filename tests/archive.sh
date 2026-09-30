#!/usr/bin/env bash
# Linux fault injection: actual flock/rename/SIGKILL; fixture binary is not executed.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1 SFXH_TEST_ROOT=$SFXH_CODE/.cache/archive-root
source "$SFXH_CODE/lib/common.sh"
source "$SFXH_CODE/lib/core.sh"
sf_paths; sf_dirs
work=$(sf_temp)
trap 'sf_remove_tree "$work"' EXIT
printf 'fixture core\n' > "$work/xray"
chmod 755 "$work/xray"
id="v26.9.9-$(sf_hash "$work/xray" | cut -c1-16)"
printf '{"tag_name":"v26.9.9","html_url":"https://example.com/release"}\n' > "$work/meta.json"
publish() { sf_core_publish "$id" "$work/xray" "$work/meta.json" fixture; }
count=0
pass() { ((count+=1)); printf 'PASS %02d %s\n' "$count" "$1"; }
for TEST_FAULT_STEP in mkdir binary metadata published; do
    sf_remove_tree "$SFXH_VAR/cores/$id"
    sf_core_checkpoint() { if [[ $1 == "$TEST_FAULT_STEP" ]]; then kill -KILL "$BASHPID"; fi; }
    if publish > "$work/failure.log" 2>&1; then exit 1; fi
    sf_core_checkpoint() { :; }
    publish
    sf_core_verify_archive "$id"
    pass "SIGKILL after $TEST_FAULT_STEP retries to a complete archive"
done
rm "$SFXH_VAR/cores/$id/metadata.json"
publish
sf_core_verify_archive "$id"
pass 'legacy incomplete unreferenced archive is quarantined and repaired'
mkdir -p "$SFXH_ETC/generations/protected"
printf '%s\n' "$id" > "$SFXH_ETC/generations/protected/core-id"
rm "$SFXH_VAR/cores/$id/metadata.json"
if publish > "$work/rejected.log" 2>&1; then exit 1; fi
test -f "$SFXH_VAR/cores/$id/xray"
test ! -f "$SFXH_VAR/cores/$id/metadata.json"
pass 'referenced damaged core is preserved and blocks publication'
sf_remove_tree "$SFXH_ETC/generations/protected"
sf_remove_tree "$SFXH_VAR/cores/$id"
publish & first=$!
publish & second=$!
wait "$first"; wait "$second"
sf_core_verify_archive "$id"
pass 'concurrent publishers produce one complete archive'
printf 'TOTAL %d archive checks\n' "$count"
