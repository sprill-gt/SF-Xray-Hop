#!/usr/bin/env bash
# Upgrade fixtures only: no production paths, service mutations or network calls.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$SFXH_CODE/.cache"
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/manager-root.XXXXXXXX")
export SFXH_TEST_ROOT
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
work=$(sf_temp); TEST_WORK=$work
trap 'sf_remove_tree "$work"' EXIT
sf_installed() { return 0; }
systemctl() { printf '%s\n' "$*" >> "$TEST_WORK/service-calls"; return 1; }
sf_manager_copy "$SFXH_CODE" "$work/legacy"
sed -i 's/^SFXH_VERSION=.*/SFXH_VERSION=0.1.3/' "$work/legacy/lib/common.sh"
# Legacy layout used a regular entry file, not a version pointer.
mkdir -p "$SFXH_INSTALL"
rm -f "$SFXH_INSTALL/sf-xray-hop"
sf_manager_copy "$work/legacy" "$SFXH_INSTALL"
mkdir -p "$(dirname "$SFXH_UNIT")"
cp "$SFXH_CODE/systemd/xray.service" "$SFXH_UNIT"
printf 'SF-Xray-Hop\n' > "$SFXH_ETC/owner"
binary=${SFXH_TEST_CORE:?official core required}
sf_core_capabilities "$binary" "$work"
id="v26.9.9-$(sf_hash "$binary" | cut -c1-16)"
mkdir -p "$SFXH_VAR/cores/$id"
install -m 755 "$binary" "$SFXH_VAR/cores/$id/xray"
jq -n --arg id "$id" --arg sha "$(sf_hash "$binary")" '{id:$id,version:"26.9.9",sha256:$sha,verified:true}' > "$SFXH_VAR/cores/$id/metadata.json"
sf_build_initial_state "$binary" "$work" '升级夹具' example.com 443 www.example.com "$id" 26.9.9 pre 0
mkdir -p "$SFXH_ETC/generations/initial"
cp "$work/state.json" "$SFXH_ETC/generations/initial/state.json"
sf_render "$work/state.json" "$SFXH_ETC/generations/initial/config.json"
printf '%s\n' "$id" > "$SFXH_ETC/generations/initial/core-id"
(cd "$SFXH_ETC/generations/initial" && sha256sum state.json config.json core-id > SHA256SUMS)
sf_activate initial
sf_manager_checkpoint() { kill -KILL "$BASHPID"; }
if sf_upgrade_manager > "$work/interrupted.log" 2>&1; then exit 1; fi
test -f "$SFXH_INSTALL/sf-xray-hop" && test ! -L "$SFXH_INSTALL/sf-xray-hop"
test "$(bash "$SFXH_INSTALL/sf-xray-hop" --version)" = 0.1.3
printf 'PASS kill before entry switch preserves executable legacy manager\n'
sf_manager_checkpoint() { :; }
sf_self_recover > "$work/recovery.log" 2>&1 || test "$?" = 75
sf_upgrade_manager
test "$(bash "$SFXH_INSTALL/sf-xray-hop" --version)" = "$SFXH_VERSION"
test "$(bash "$SFXH_INSTALL/previous-manager/sf-xray-hop" --version)" = 0.1.3
test ! -e "$work/service-calls"
sf_generation_integrity "$(sf_generation)"
test "$(sf_generation)" = "$SFXH_ETC/generations/initial"
printf 'PASS atomic legacy-to-release upgrade preserves old manager and live configuration without restart\n'
entry=$(readlink "$SFXH_INSTALL/sf-xray-hop")
sf_upgrade_manager
test "$(readlink "$SFXH_INSTALL/sf-xray-hop")" = "$entry"
printf 'PASS identical manager upgrade is a no-op\n'
printf '\n# changed unit\n' >> "$SFXH_UNIT"
if sf_upgrade_manager > "$work/rejected.log" 2>&1; then exit 1; fi
test "$(readlink "$SFXH_INSTALL/sf-xray-hop")" = "$entry"
printf 'PASS incompatible unit blocks manager upgrade before publication\n'
cp "$SFXH_CODE/systemd/xray.service" "$SFXH_UNIT"
jq '.outbounds[0].tag="changed"' "$SFXH_ETC/generations/initial/config.json" > "$work/changed.json"
cp "$work/changed.json" "$SFXH_ETC/generations/initial/config.json"
if sf_upgrade_manager > "$work/rejected.log" 2>&1; then exit 1; fi
test "$(readlink "$SFXH_INSTALL/sf-xray-hop")" = "$entry"
printf 'PASS changed runtime configuration blocks code-only upgrade\nTOTAL 5 manager upgrade checks\n'
