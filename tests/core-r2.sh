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
count=0
pass() { count=$((count+1)); printf 'PASS %02d %s\n' "$count" "$1"; }
reject() { local rc=0; "$@" > "$work/output" 2>&1 || rc=$?; [[ $rc == 2 ]]; }
for version in 26.9.9 v26.9.9 26.9.30 26.10.1 27.1.1; do sf_core_require_version "$version"; done
for version in 26.9.8 26.8.99 25.99.99 26.3.27 '' latest 26.9 v26.9.9-extra 26.9.1000000000; do reject sf_core_require_version "$version"; done
pass 'minimum version uses numeric components, accepts the boundary and rejects malformed or older versions'
printf '{"core":{"id":"v26.9.30-0123456789abcdef","version":"26.9.30","channel":"pinned","pinnedVersion":"26.9.30"},"identities":{"marker":"unchanged"},"nextHop":{"marker":"unchanged"}}' > "$work/current.json"
sf_state() { printf '%s/current.json\n' "$TEST_WORK"; }
sf_edit_begin() { SF_EDIT_STATE=$TEST_WORK/current.json; SF_EDIT_WORK=$(sf_temp); }
sf_release_metadata() {
    printf '%s\n' "$1" >> "$TEST_WORK/channels"
    printf '%s\n' "$2" >> "$TEST_WORK/requested-versions"
    jq -n --arg v "${2:-$TEST_VERSION}" '{tag_name:("v"+$v),prerelease:($ENV.TEST_PRERELEASE!="false")}' > "$3"
}
sf_core_download() {
    printf 'download\n' >> "$TEST_WORK/downloads"
    printf 'v%s-%s\n' "$(jq -r '.tag_name|ltrimstr("v")' "$1")" "$TEST_DIGEST"
}
sf_tx_apply() { cp "$1" "$TEST_WORK/committed.json"; printf '%s\n' "${3:-online}" > "$TEST_WORK/mode"; }
sf_tty() { return 1; }
TEST_VERSION=26.9.2; TEST_DIGEST=0123456789abcdef
reject sf_core_update --version 26.9.8 --yes
reject sf_core_select 26.3.27
[[ ! -f $work/channels && ! -f $work/downloads && ! -f $work/committed.json ]]
pass 'unsupported exact versions stop before release lookup even with --yes'
reject sf_core_update --channel stable --yes
[[ ! -f $work/downloads && ! -f $work/committed.json ]]
pass 'a channel candidate below the floor cannot be downloaded or committed'
sf_core_select v26.9.9 > "$work/output" 2>&1
jq -e '.core.version=="26.9.9" and .core.channel=="pinned" and .core.pinnedVersion=="26.9.9" and .identities.marker=="unchanged" and .nextHop.marker=="unchanged"' "$work/committed.json" >/dev/null
pass 'explicit lower supported version needs no extra downgrade consent and preserves identities and downstream'
cp "$work/committed.json" "$work/current.json"
TEST_VERSION=26.9.30
sf_core_update > "$work/output" 2>&1
[[ $(tail -n 1 "$work/channels") == auto && -z $(tail -n 1 "$work/requested-versions") ]]
jq -e '.core.version=="26.9.30" and .core.channel=="pre" and .core.pinnedVersion==null' "$work/committed.json" >/dev/null
pass 'default update leaves a selected version and compares stable and Pre'
jq '.core.channel="stable"|.core.pinnedVersion=null' "$work/current.json" > "$work/stable.json"
cp "$work/stable.json" "$work/current.json"
sf_core_update > "$work/output" 2>&1
[[ $(tail -n 1 "$work/channels") == auto ]]
pass 'default update also compares stable and Pre after an explicit stable choice'
jq '.core.channel="pinned"|.core.pinnedVersion=.core.version' "$work/current.json" > "$work/pinned.json"
cp "$work/pinned.json" "$work/current.json"
sf_core_check > "$work/output" 2>&1
[[ $(tail -n 2 "$work/channels" | head -n 1) == auto && $(tail -n 1 "$work/channels") == stable ]]
grep -q 'v26.9.30' "$work/output"
cmp "$work/current.json" "$work/pinned.json"
pass 'check reports the latest stable-or-Pre without changing a selected version'
export TEST_PRERELEASE=false
sf_core_update > "$work/output" 2>&1
[[ $(tail -n 1 "$work/channels") == auto ]]
jq -e '.core.channel=="stable" and .core.pinnedVersion==null' "$work/committed.json" >/dev/null
unset TEST_PRERELEASE
pass 'automatic selection records stable when the winning release is stable'
cp "$work/committed.json" "$work/current.json"
rm "$work/committed.json"
TEST_VERSION=26.9.9
reject sf_core_update --channel stable
[[ ! -f $work/committed.json ]]
export TEST_PRERELEASE=false
sf_core_update --channel stable --yes > "$work/output" 2>&1
jq -e '.core.version=="26.9.9" and .core.channel=="stable"' "$work/committed.json" >/dev/null
pass 'an implicit channel downgrade still needs consent and accepts the minimum version'
rm "$work/committed.json"
unset TEST_PRERELEASE
TEST_VERSION=26.9.30; TEST_DIGEST=fedcba9876543210
rc=0; sf_core_update > "$work/output" 2>&1 || rc=$?
[[ $rc == 2 && ! -f $work/committed.json ]]
sf_core_update --yes > "$work/output" 2>&1
jq -e '.core.id=="v26.9.30-fedcba9876543210"' "$work/committed.json" >/dev/null
pass 'same tag with changed digest still requires explicit confirmation'
sf_core_update --version 26.10.1 --yes > "$work/output" 2>&1
jq -e '.core.version=="26.10.1" and .core.channel=="pinned" and .core.pinnedVersion=="26.10.1"' "$work/committed.json" >/dev/null
pass 'explicit version pins only the core channel'
sf_core_rollback 26.9.9 > "$work/output" 2>&1
jq -e '.core.version=="26.9.9" and .core.channel=="pinned"' "$work/committed.json" >/dev/null
reject sf_core_rollback 26.9.9 --offline
reject sf_core_rollback 26.9.9 --previous
pass 'rollback accepts a version as an online selection but never treats it as an offline archive'
for version in 26.9.8 26.9.9 26.9.30; do
    id="v$version-0123456789abcdef"
    mkdir -p "$SFXH_VAR/cores/$id"
    jq -n --arg id "$id" --arg version "$version" '{id:$id,version:$version,verified:true}' > "$SFXH_VAR/cores/$id/metadata.json"
done
sf_core_verify_archive() { printf '%s\n' "$1" > "$TEST_WORK/verified-archive"; }
rm "$work/committed.json"
reject sf_core_rollback v26.9.8-0123456789abcdef --offline
[[ ! -f $work/committed.json && ! -f $work/verified-archive ]]
sf_core_rollback v26.9.9-0123456789abcdef --offline > "$work/output" 2>&1
[[ $(cat "$work/mode") == offline ]]
jq -e '.core.version=="26.9.9" and .identities.marker=="unchanged" and .nextHop.marker=="unchanged"' "$work/committed.json" >/dev/null
pass 'local offline recovery enforces the floor and preserves current configuration'
mkdir -p "$SFXH_ETC/generations/20261002" "$SFXH_ETC/generations/20261001"
printf '%s\n' v26.9.8-0123456789abcdef > "$SFXH_ETC/generations/20261002/core-id"
printf '%s\n' v26.9.9-0123456789abcdef > "$SFXH_ETC/generations/20261001/core-id"
sf_core_rollback --previous > "$work/output" 2>&1
jq -e '.core.version=="26.9.9"' "$work/committed.json" >/dev/null
pass 'previous-core recovery skips history below the minimum'
sf_ask_choice() { printf '%s\n' "$@" > "$TEST_WORK/history-menu"; SF_REPLY=2; }
sf_core_rollback > "$work/output" 2>&1
! grep -q 26.9.8 "$work/history-menu"
jq -e '.core.version=="26.9.9"' "$work/committed.json" >/dev/null
pass 'interactive local history omits unsupported versions'
jq '.core.track="stable"' "$work/current.json" > "$work/track.json"
cp "$work/track.json" "$work/current.json"
sf_core_update --yes > "$work/output" 2>&1
[[ $(tail -n 1 "$work/channels") == stable ]]
jq -e '.core.track=="stable"' "$work/committed.json" >/dev/null
sf_core_update --channel pre --yes > "$work/output" 2>&1
[[ $(tail -n 1 "$work/channels") == pre ]]
jq -e '.core.track=="stable"' "$work/committed.json" >/dev/null
reject sf_core_track invalid
pass 'saved stable intent controls default update; explicit Pre does not change intent'
# Restore the real download guard. The fixture deliberately is not a ZIP: a
# changed archive must be stopped before extraction or execution is attempted.
source "$SFXH_CODE/lib/core.sh"
sf_curl_download() { touch "$TEST_WORK/unexpected-request"; return 1; }
reject sf_release_metadata pinned 26.9.8 "$work/rejected-release.json"
[[ ! -f $work/unexpected-request ]]
printf '{"tag_name":"v26.9.8"}' > "$work/old-release.json"
reject sf_core_download "$work/old-release.json" "$work"
[[ ! -f $work/unexpected-request ]]
pass 'real metadata and download entry points reject old versions before any request'
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
pass 'changed same-tag archive requires consent before unpacking or executing core'
# Use the real download orchestration; capability parsing and safety behavior
# are independent boundaries. A safety failure must precede archive publication.
unzip() { printf '#!/usr/bin/env bash\nexit 0\n'; }
sf_core_capabilities() { printf 'Xray 26.9.9\n' > "$2/version.txt"; }
sf_core_security() { return 1; }
sf_core_publish() { touch "$TEST_WORK/unsafe-published"; }
mkdir "$work/safety-guard"
rc=0; sf_core_download "$work/changed-release.json" "$work/safety-guard" inspect > "$work/safety.out" 2>&1 || rc=$?
[[ $rc != 0 && -f $work/safety-guard/version.txt && ! -f $work/unsafe-published ]]
pass 'candidate with matching release digest and capabilities still cannot publish after safety failure'
printf 'TOTAL %d core version selection checks (release, binary and commit fixtures)\n' "$count"
