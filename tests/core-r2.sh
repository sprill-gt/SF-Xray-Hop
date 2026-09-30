#!/usr/bin/env bash
# Update orchestration guards; downloading and transaction commit are fixtures.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$SFXH_CODE/.cache"
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/core-r2.XXXXXXXX"); export SFXH_TEST_ROOT
# shellcheck disable=SC1090
for module in common model product core operations; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
work=$(sf_temp); TEST_WORK=$work
trap 'sf_remove_tree "$work"' EXIT
printf '{"core":{"id":"v26.9.9-0123456789abcdef","version":"26.9.9","channel":"pre"},"identities":{"marker":"unchanged"},"nextHop":{"marker":"unchanged"}}' > "$work/current.json"
sf_edit_begin() { SF_EDIT_STATE=$TEST_WORK/current.json; SF_EDIT_WORK=$(sf_temp); }
sf_release_metadata() {
    printf '%s\n' "$1" >> "$TEST_WORK/channels"
    jq -n --arg v "${2:-$TEST_VERSION}" '{tag_name:("v"+$v)}' > "$3"
}
sf_core_download() {
    printf 'download\n' >> "$TEST_WORK/downloads"
    printf 'v%s-%s\n' "$(jq -r '.tag_name|ltrimstr("v")' "$1")" "$TEST_DIGEST"
}
sf_tx_apply() { cp "$1" "$TEST_WORK/committed.json"; }
sf_tty() { return 1; }
TEST_VERSION=26.9.2; TEST_DIGEST=0123456789abcdef
rc=0; sf_core_update --channel stable > "$work/output" 2>&1 || rc=$?
[[ $rc == 2 && ! -f $work/downloads && ! -f $work/committed.json ]]
printf 'PASS downgrade needs confirmation before downloading or changing channel\n'
sf_core_update --channel stable --yes > "$work/output" 2>&1
jq -e '.core.version=="26.9.2" and .core.channel=="stable" and .identities.marker=="unchanged" and .nextHop.marker=="unchanged"' "$work/committed.json" >/dev/null
printf 'PASS explicit stable downgrade preserves identity and current downstream\n'
rm "$work/committed.json"
TEST_VERSION=26.9.9; TEST_DIGEST=fedcba9876543210
rc=0; sf_core_update > "$work/output" 2>&1 || rc=$?
[[ $rc == 2 && ! -f $work/committed.json ]]
sf_core_update --yes > "$work/output" 2>&1
jq -e '.core.id=="v26.9.9-fedcba9876543210"' "$work/committed.json" >/dev/null
printf 'PASS same tag with changed digest requires explicit confirmation\n'
sf_core_update --version 26.10.1 --yes > "$work/output" 2>&1
jq -e '.core.version=="26.10.1" and .core.channel=="pinned" and .core.pinnedVersion=="26.10.1"' "$work/committed.json" >/dev/null
printf 'PASS explicit version pins only the core channel\n'
# Restore the real download guard. The fixture deliberately is not a ZIP: a
# changed archive must be stopped before extraction or execution is attempted.
source "$SFXH_CODE/lib/core.sh"
printf 'untrusted changed archive' > "$work/changed-archive"
sha=$(sf_hash "$work/changed-archive")
jq -n --arg sha "$sha" '{tag_name:"v26.9.9",assets:[
 {name:"Xray-linux-64.zip",digest:("sha256:"+$sha),browser_download_url:"https://github.com/XTLS/Xray-core/releases/download/v26.9.9/Xray-linux-64.zip"},
 {name:"Xray-linux-64.zip.dgst",browser_download_url:"https://github.com/XTLS/Xray-core/releases/download/v26.9.9/Xray-linux-64.zip.dgst"}]}' > "$work/changed-release.json"
sf_curl_download() { if [[ $1 == *.dgst ]]; then printf 'SHA256=%s\n' "$sha" > "$2"; else cp "$TEST_WORK/changed-archive" "$2"; fi; }
sf_require_space() { :; }
mkdir "$work/guard"
rc=0; sf_core_download "$work/changed-release.json" "$work/guard" inspect previous-archive-digest > "$work/guard.out" 2>&1 || rc=$?
[[ $rc == 2 && ! -e $work/guard/unpacked ]]
printf 'PASS changed same-tag archive requires consent before unpacking or executing core\n'
# Use the real download orchestration; capability parsing and safety behavior
# are independent boundaries. A safety failure must precede archive publication.
unzip() { printf '#!/usr/bin/env bash\nexit 0\n'; }
sf_core_capabilities() { printf 'Xray 26.9.9\n' > "$2/version.txt"; }
sf_core_security() { return 1; }
sf_core_publish() { touch "$TEST_WORK/unsafe-published"; }
mkdir "$work/safety-guard"
rc=0; sf_core_download "$work/changed-release.json" "$work/safety-guard" inspect > "$work/safety.out" 2>&1 || rc=$?
[[ $rc != 0 && -f $work/safety-guard/version.txt && ! -f $work/unsafe-published ]]
printf 'PASS candidate with matching release digest and capabilities still cannot publish after safety failure\n'
printf 'TOTAL 6 core update guard checks (release, binary and commit fixtures)\n'
