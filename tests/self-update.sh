#!/usr/bin/env bash
# Linux/root isolated release, rollback and uninstall tests. No real service edits.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$SFXH_CODE/.cache"
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/self-r2.XXXXXXXX"); export SFXH_TEST_ROOT
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install operations benchmark ui; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
work=$(sf_temp); TEST_WORK=$work
trap 'sf_remove_tree "$work"' EXIT
count=0
pass() { count=$((count+1)); printf 'PASS %02d %s\n' "$count" "$1"; }
reject() { if "$@" > "$work/rejected" 2>&1; then printf 'FAIL expected rejection: %s\n' "$1" >&2; exit 1; fi; }
systemctl() { printf '%s\n' "$*" >> "$TEST_WORK/service-calls"; return 0; }
mkdir -p "$(dirname "$SFXH_UNIT")" "$SFXH_BIN"
cp "$SFXH_CODE/systemd/xray.service" "$SFXH_UNIT"
printf 'SF-Xray-Hop\n' > "$SFXH_ETC/owner"
binary=${SFXH_TEST_CORE:?official core required}
sf_core_capabilities "$binary" "$work"
id="v26.9.9-$(sf_hash "$binary" | cut -c1-16)"
mkdir -p "$SFXH_VAR/cores/$id"
install -m 755 "$binary" "$SFXH_VAR/cores/$id/xray"
jq -n --arg id "$id" --arg sha "$(sf_hash "$binary")" '{id:$id,version:"26.9.9",sha256:$sha,verified:true}' > "$SFXH_VAR/cores/$id/metadata.json"
sf_build_initial_state "$binary" "$work" '更新测试' example.com 443 archive.archlinux.org "$id" 26.9.9 pinned 1
mkdir -p "$SFXH_ETC/generations/initial"
cp "$work/state.json" "$SFXH_ETC/generations/initial/state.json"
sf_render "$work/state.json" "$SFXH_ETC/generations/initial/config.json"
printf '%s\n' "$id" > "$SFXH_ETC/generations/initial/core-id"
(cd "$SFXH_ETC/generations/initial" && sha256sum state.json config.json core-id > SHA256SUMS)
sf_activate initial
sf_manager_copy "$SFXH_CODE" "$work/old"
sed -i 's/^SFXH_VERSION=.*/SFXH_VERSION=0.1.9/' "$work/old/lib/common.sh"
mkdir -p "$SFXH_INSTALL/releases/.stage-abandoned"
printf stale > "$SFXH_INSTALL/releases/.stage-abandoned/incomplete"
old=$(sf_manager_stage "$work/old"); sf_manager_activate "$old"
[[ ! -e $SFXH_INSTALL/releases/.stage-abandoned ]]
pass 'locked manager publication cleans abandoned staging without growing history'
ln -s "$SFXH_INSTALL/sf-xray-hop" "$SFXH_BIN/sfxh"
ln -s "$SFXH_INSTALL/sf-xray-hop" "$SFXH_BIN/sf-xray-hop"
sf_manager_copy "$SFXH_CODE" "$work/pack/SF-Xray-Hop"
tar -czf "$work/package.tar.gz" -C "$work/pack" SF-Xray-Hop
sha=$(sf_hash "$work/package.tar.gz")
commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
jq -n --arg sha "$sha" --arg commit "$commit" --argjson size "$(wc -c < "$work/package.tar.gz")" \
  '{schemaVersion:1,project:"SF-Xray-Hop",version:"0.2.4",commit:$commit,archive:{name:"SF-Xray-Hop-0.2.4.tar.gz",sha256:$sha,size:$size}}' > "$work/manifest-source.json"
jq -n --arg sha "$sha" '{id:1,tag_name:"v0.2.4",draft:false,prerelease:false,published_at:"2026-09-30",assets:[
  {name:"manifest.json",browser_download_url:"https://github.com/sprill-gt/SF-Xray-Hop/releases/download/v0.2.4/manifest.json"},
  {name:"SF-Xray-Hop-0.2.4.tar.gz",digest:("sha256:"+$sha),browser_download_url:"https://github.com/sprill-gt/SF-Xray-Hop/releases/download/v0.2.4/SF-Xray-Hop-0.2.4.tar.gz"}]}' > "$work/release-source.json"
sf_curl_download() {
    case "$1" in
        */releases\?*) jq -s . "$TEST_WORK/release-source.json" > "$2" ;;
        */manifest.json) cp "$TEST_WORK/manifest-source.json" "$2" ;;
        */commits/*) printf '{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' > "$2" ;;
        *.tar.gz) cp "$TEST_WORK/package.tar.gz" "$2" ;;
        *) return 1 ;;
    esac
}
sf_self_update --yes
[[ $(bash "$SFXH_INSTALL/sf-xray-hop" --version) == 0.2.4 ]]
[[ $(readlink -f "$SFXH_INSTALL/previous-manager") == "$old" ]]
[[ ! -e $work/service-calls ]]
sf_generation_integrity "$(sf_generation)"
pass 'verified complete release updates script without service restart or state/core change'
sf_self_rollback --yes
[[ $(bash "$SFXH_INSTALL/sf-xray-hop" --version) == 0.1.9 ]]
sf_self_update --yes
pass 'manual rollback validates current state and preserves protocol material'
sf_manager_copy "$SFXH_CODE" "$work/incompatible"
sed -i 's/^SFXH_VERSION=.*/SFXH_VERSION=0.1.8/' "$work/incompatible/lib/common.sh"
sed -i 's/\.schemaVersion==[12]/.schemaVersion==0/g' "$work/incompatible/templates/model.jq"
bad=$(sf_manager_stage "$work/incompatible")
ln -sfn "$bad" "$SFXH_INSTALL/previous-manager"
entry=$(readlink "$SFXH_INSTALL/sf-xray-hop")
reject sf_self_rollback --yes
[[ $(readlink "$SFXH_INSTALL/sf-xray-hop") == "$entry" ]]
pass 'incompatible old schema is rejected without restoring obsolete state'
sf_manager_checkpoint() { [[ $1 != after-switch ]] || kill -KILL "$BASHPID"; }
reject sf_manager_switch "$work/old"
[[ -f $SFXH_ETC/manager-transaction.json ]]
sf_manager_checkpoint() { :; }
sf_lock
sf_self_recover > "$work/recovery.log" 2>&1 || [[ $? == 75 ]]
sf_unlock
[[ $(readlink "$SFXH_INSTALL/sf-xray-hop") == "$entry" ]]
[[ $(readlink -f "$SFXH_INSTALL/previous-manager") == "$bad" ]]
[[ ! -f $SFXH_ETC/manager-transaction.json && ! -e $work/service-calls ]]
pass 'SIGKILL restores active and previous-script pointers without touching live proxy'
sf_manager_checkpoint() {
    if [[ $1 == after-switch ]]; then
        local live
        live=$(dirname "$(readlink -f "$SFXH_INSTALL/sf-xray-hop")")
        printf '\n# injected damage after switch\n' >> "$live/lib/common.sh"
    fi
}
reject sf_manager_switch "$work/old"
sf_manager_checkpoint() { :; }
[[ $(readlink "$SFXH_INSTALL/sf-xray-hop") == "$entry" ]]
[[ $(readlink -f "$SFXH_INSTALL/previous-manager") == "$bad" ]]
[[ ! -f $SFXH_ETC/manager-transaction.json && ! -e $work/service-calls ]]
pass 'failed post-switch verification restores both script pointers automatically'
mkdir "$work/unpack"
cp "$work/manifest-source.json" "$work/good-manifest"
jq '.commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$work/good-manifest" > "$work/manifest-source.json"
reject sf_self_download "$work/release-source.json" "$work/unpack"
cp "$work/good-manifest" "$work/manifest-source.json"
printf damage >> "$work/package.tar.gz"
reject sf_self_download "$work/release-source.json" "$work/unpack"
pass 'tag/manifest mismatch and damaged package stop before executing downloaded code'
sf_lock
( sf_lock; sf_unlock; [[ -n ${SF_LOCK_FD:-} ]]; )
if flock -n "$SFXH_LOCK" -c true; then exit 1; fi
sf_unlock
flock -n "$SFXH_LOCK" -c true
pass 'nested mutation lock cannot release parent ownership'
# Reject a symlinked destructive root before issuing systemctl.
mv "$SFXH_LOG" "$SFXH_TEST_ROOT/kept-log"
ln -s "$SFXH_TEST_ROOT/kept-log" "$SFXH_LOG"
reject sf_uninstall --yes
[[ -f $SFXH_ETC/owner && ! -e $work/service-calls ]]
rm "$SFXH_LOG"; mv "$SFXH_TEST_ROOT/kept-log" "$SFXH_LOG"
pass 'uninstall rejects symlinked roots before stopping any service'
# Record service calls outside the managed roots that will be deleted.
systemctl() { printf '%s\n' "$*" >> "$SFXH_TEST_ROOT/uninstall-service-calls"; }
printf untouched > "$SFXH_TEST_ROOT/unrelated"
sf_uninstall --yes
[[ ! -e $SFXH_ETC && ! -e $SFXH_VAR && ! -e $SFXH_INSTALL && ! -e $SFXH_BIN/sfxh ]]
[[ $(cat "$SFXH_TEST_ROOT/unrelated") == untouched ]]
pass 'complete uninstall removes owned private data and manager history only'
printf 'TOTAL %d self-update and uninstall checks (HTTPS and systemd fixtures)\n' "$count"
