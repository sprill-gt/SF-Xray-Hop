#!/usr/bin/env bash
# Run ON EACH intended VPS after explicit installation. No update/reboot/uninstall.
set -uo pipefail
umask 077
[[ $EUID == 0 && $# == 1 ]] || { printf '用法：sudo bash tests/vps-acceptance.sh /私有目录/result.json\n' >&2; exit 2; }
output=$1
[[ ! -e $output && ! -L $output ]] || { printf '拒绝覆盖已有记录。\n' >&2; exit 2; }
entry=/usr/local/lib/sf-xray-hop/sf-xray-hop
[[ -x $entry ]] || exit 1
# Manager releases live behind an atomic entry symlink. Never source a legacy
# root directory that can belong to a different installed script version.
code=$(dirname "$(readlink -f "$entry")") || exit 1
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install operations benchmark ui; do source "$code/lib/$module.sh"; done
SFXH_CODE=$code
sf_paths
sf_platform_check || exit
state=$(sf_state) || exit
work=$(sf_temp) || exit
trap 'sf_remove_tree "$work"' EXIT
failed=0
check() {
    local name=$1 rc=0
    shift
    "$@" > "$work/check.log" 2>&1 || rc=$?
    jq -n --arg name "$name" --argjson rc "$rc" '{check:$name,passed:($rc==0),exitCode:$rc}' >> "$work/results.jsonl"
    if ((rc)); then printf '未通过：%s\n' "$name" >&2; failed=1; else printf '通过：%s\n' "$name" >&2; fi
}
check unit-validation systemd-analyze verify "$SFXH_UNIT"
check service-active systemctl is-active --quiet xray.service
check service-enabled systemctl is-enabled --quiet xray.service
check manager-config-private test "$(stat -c '%a:%U' "$SFXH_ETC")" = '700:root'
check state-private test "$(stat -c '%a:%U' "$state")" = '600:root'
check service-user test "$(systemctl show xray.service --property=User --value)" = sfxray
check service-cannot-read-state runuser -u sfxray -- bash -c '! test -r "$1"' bash "$state"
check service-cannot-replace-manager-log runuser -u sfxray -- bash -c '! test -w "$1"' bash "$SFXH_LOG"
check local-doctor "$code/sf-xray-hop" doctor
jq -s --arg os "$SF_OS_ID" --arg version "$SF_OS_VERSION" --arg at "$(sf_now)" --arg core "$(jq -r .core.version "$state")" \
  '{scope:"单台已安装 VPS 的只读验收；不包括重启、故障注入或独立设备",checkedAt:$at,os:$os,osVersion:$version,arch:"amd64",core:$core,checks:.}' "$work/results.jsonl" > "$output" || exit
printf '记录已保存；跨机器、开机恢复和设备验收仍需单独执行。\n' >&2
exit "$failed"
