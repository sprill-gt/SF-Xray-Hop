#!/usr/bin/env bash
# Exercises real menu/guide control flow with no terminal escapes or real changes.
set -euo pipefail
umask 077
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1 SFXH_TEST_ROOT=$SFXH_CODE/.cache/ui-root
# shellcheck disable=SC1090
for module in common platform model product links core reality health transaction manager self install operations benchmark ui; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
rm -f -- "$SFXH_ETC/guide.json"
TEST_WORK=$(sf_temp)
trap 'sf_remove_tree "$TEST_WORK"' EXIT
count=0
pass() { count=$((count+1)); printf 'PASS %02d %s\n' "$count" "$1"; }
sf_tty() { return 0; }
sf_status() { sf_msg 'SF-Xray-Hop 测试机器'; }
sf_pause() { :; }
sf_installed() { return 0; }
case $(uname -s) in MINGW*|MSYS*) sf_lock() { :; } ;; esac # Windows control-flow fixture only.
sf_state() { printf '%s/state.json\n' "$TEST_WORK"; }
sf_generation() { printf '%s/generations/test\n' "$SFXH_ETC"; }
sf_health_current() { printf 'health\n' >> "$TEST_WORK/calls"; }
sf_set_role() {
    jq --arg role "$1" '.presentation.role=$role' "$TEST_WORK/state.json" > "$TEST_WORK/new.json" && mv "$TEST_WORK/new.json" "$TEST_WORK/state.json"
}
sf_view() { printf 'explicit-view %s\n' "$*" >> "$TEST_WORK/calls"; }
sf_chain_change() {
    local candidate
    read -r candidate
    printf 'chain-%s\n' "$1" >> "$TEST_WORK/calls"
    [[ $candidate == candidate-good ]] || return 1
    jq '.nextHop={address:"exit.example.com",port:443}' "$TEST_WORK/state.json" > "$TEST_WORK/new.json" && mv "$TEST_WORK/new.json" "$TEST_WORK/state.json"
}
printf '{"node":{"name":"测试节点","address":"203.0.113.10"},"nextHop":null}\n' > "$TEST_WORK/state.json"

# Calls the sourced real menu here; a later setup-only case replaces it.
# shellcheck disable=SC2218
sf_menu > "$TEST_WORK/empty.txt" 2>&1 <<< ''
pass 'main menu empty Enter exits without mutations'
(
    sf_ask_choice 'RTT 必选' '1. 0-RTT' '2. 1-RTT' '0. 返回'
    [[ $SF_REPLY == 2 ]]
) > "$TEST_WORK/invalid.txt" 2>&1 <<'INPUT'

99
2
INPUT
[[ $(grep -c '请输入菜单中显示的数字' "$TEST_WORK/invalid.txt") == 2 ]]
pass 'explicit RTT change has no default; invalid input stays at current step'

(
    sf_chain_setup_menu() { printf 'setup\n' >> "$TEST_WORK/main-calls"; }
    sf_chain_manage_menu() { printf 'manage\n' >> "$TEST_WORK/main-calls"; }
    sf_share_menu() { printf 'share\n' >> "$TEST_WORK/main-calls"; }
    sf_core_menu() { printf 'core\n' >> "$TEST_WORK/main-calls"; }
    sf_uninstall() { printf 'uninstall\n' >> "$TEST_WORK/main-calls"; return 130; }
    rc=0; sf_menu <<'INPUT' || rc=$?
1
2
3
6
9
0
INPUT
    [[ $rc == 0 ]]
) > "$TEST_WORK/main-menu.txt" 2>&1
printf '%s\n' setup manage share core uninstall > "$TEST_WORK/main-expected"
cmp "$TEST_WORK/main-calls" "$TEST_WORK/main-expected"
! grep -q 'Xray 更新到最新核心\|Xray 自主选择版本\|Xray 恢复上一可用核心' "$TEST_WORK/main-menu.txt"
pass 'main menu separates chain setup/management and routes all core actions through one submenu'

(
    sf_core_update() { printf 'update:%s\n' "$*" >> "$TEST_WORK/core-calls"; }
    sf_core_rollback() { printf 'history:%s\n' "$*" >> "$TEST_WORK/core-calls"; }
    # The real entry point has no errexit; a rejected choice stays in the menu.
    rc=0; sf_core_menu <<'INPUT' || rc=$?
1
2
26.9.8
2
26.9.9
3
4
0
INPUT
    [[ $rc == 0 ]]
) > "$TEST_WORK/core-menu.txt" 2>&1
printf '%s\n' 'update:' 'update:--version 26.9.9' 'history:--previous' 'history:' > "$TEST_WORK/core-expected"
cmp "$TEST_WORK/core-calls" "$TEST_WORK/core-expected"
grep -q '最低支持 Xray 26.9.9' "$TEST_WORK/core-menu.txt"
pass 'core menu defaults to newest stable-or-Pre, accepts version numbers and rejects unsupported choices without applying them'
(
    sf_core_update() { printf 'update:%s\n' "$*" >> "$TEST_WORK/core-cli"; }
    sf_main core select 26.9.9
    sf_main core v26.9.9
    sf_main core rollback 26.9.9
    sf_main core select 26.9.9 --yes
    for command in 'core select' 'core select 26.9.9 extra' 'core select 26.9.8 --yes' 'core 26.9.8' 'core rollback 26.9.9 --offline'; do
        read -r -a args <<< "$command"
        rc=0; sf_main "${args[@]}" || rc=$?
        [[ $rc == 2 ]]
    done
) > "$TEST_WORK/core-cli.txt" 2>&1
printf '%s\n' 'update:--version 26.9.9' 'update:--version v26.9.9' 'update:--version 26.9.9' 'update:--version 26.9.9 --yes' > "$TEST_WORK/core-cli-expected"
cmp "$TEST_WORK/core-cli" "$TEST_WORK/core-cli-expected"
pass 'version selection CLI and compatibility aliases share validation and reject excess arguments'

sf_guide > "$TEST_WORK/entry.txt" 2>&1 <<'INPUT'
1
2
0
INPUT
jq -e '.position=="entry" and .stage=="awaiting_link"' "$SFXH_ETC/guide.json" >/dev/null
grep -q '打开出口 B' "$TEST_WORK/entry.txt"
[[ ! -f $TEST_WORK/calls ]]
pass 'entry handoff instructions and progress saved without credentials'

sf_guide > "$TEST_WORK/resume.txt" 2>&1 <<'INPUT'
1
1
candidate-bad
1
candidate-good
0
INPUT
jq -e '.stage=="complete"' "$SFXH_ETC/guide.json" >/dev/null
[[ $(grep -c chain-set "$TEST_WORK/calls") == 2 ]]
! grep -q explicit-view "$TEST_WORK/calls"
pass 'resumed entry retries failed candidate and explicitly finishes device step'

cp "$TEST_WORK/state.json" "$TEST_WORK/before.json"
sf_guide > "$TEST_WORK/reenter.txt" 2>&1 <<'INPUT'
0
INPUT
cmp "$TEST_WORK/state.json" "$TEST_WORK/before.json"
[[ $(grep -c chain-set "$TEST_WORK/calls") == 2 ]]
pass 'completed guide never overwrites existing next hop'

jq '.nextHop=null' "$TEST_WORK/state.json" > "$TEST_WORK/new.json"; mv "$TEST_WORK/new.json" "$TEST_WORK/state.json"
sf_guide > "$TEST_WORK/exit.txt" 2>&1 <<'INPUT'
2
2
0
INPUT
jq -e '.position=="exit" and .stage=="ready"' "$SFXH_ETC/guide.json" >/dev/null
grep -q '没有入口连接成功的证据' "$TEST_WORK/exit.txt"
! grep -q '两台已连接成功' "$TEST_WORK/exit.txt"
! grep -q explicit-view "$TEST_WORK/calls"
pass 'exit reports ready only and does not expose link automatically'

sf_guide > "$TEST_WORK/view.txt" 2>&1 <<'INPUT'
1
1
0
INPUT
[[ $(grep -c explicit-view "$TEST_WORK/calls") == 1 ]]
pass 'outlet credential display requires explicit numeric action'

sf_tty() { return 1; }
for command in 'guide' 'rtt' 'status extra' 'view relay extra' 'core check extra' 'uninstall extra extra' 'node name' 'node entry' 'chain remove unknown'; do
    read -r -a args <<< "$command"
    rc=0; sf_main "${args[@]}" > "$TEST_WORK/noninteractive.txt" 2>&1 || rc=$?
    [[ $rc == 2 ]]
done
pass 'noninteractive missing and excess arguments reject without waiting'
! grep -q $'\033' "$TEST_WORK/entry.txt"
pass 'menu output has no ANSI color dependency'
sf_tty() { return 0; }
sf_installed() { return 1; }
sf_install() { printf 'install\n' >> "$TEST_WORK/setup-calls"; }
sf_setup > "$TEST_WORK/setup.txt" 2>&1 <<'INPUT'


INPUT
grep -q '默认：单机直连' "$TEST_WORK/setup.txt"
grep -q '可选设置名称' "$TEST_WORK/setup.txt"
[[ $(cat "$TEST_WORK/setup-calls") == install ]]
! grep -q 'explicit-view' "$TEST_WORK/setup.txt"
pass 'setup has no required role or protocol questions; post-install name can be skipped'
sf_installed() { return 0; }
sf_menu() { printf 'menu\n' >> "$TEST_WORK/setup-calls"; }
sf_setup > "$TEST_WORK/setup-existing.txt" 2>&1
[[ $(grep -c '^install$' "$TEST_WORK/setup-calls") == 1 ]]
[[ $(grep -c '^menu$' "$TEST_WORK/setup-calls") == 1 ]]
pass 'repeated installer opens management without reinstalling'
SFXH_INSTALL=$TEST_WORK/installed
mkdir "$SFXH_INSTALL"
printf '#!/usr/bin/env bash\nprintf "installed-manager:%%s\\n" "$1"\n' > "$SFXH_INSTALL/sf-xray-hop"
chmod 755 "$SFXH_INSTALL/sf-xray-hop"
sf_setup > "$TEST_WORK/delegate.txt" 2>&1
grep -q '^installed-manager:menu$' "$TEST_WORK/delegate.txt"
pass 'new bootstrap delegates existing installation to its installed manager version'
sf_installed() { return 1; }
sf_install() { return 130; }
rc=0; sf_setup > "$TEST_WORK/setup-cancel.txt" 2>&1 || rc=$?
[[ $rc == 130 ]]
! grep -q '安装完成' "$TEST_WORK/setup-cancel.txt"
pass 'cancelled setup preserves exit status and never reports success'
(
    # Restore status implementation; service/OS boundaries remain fixtures.
    source "$SFXH_CODE/lib/operations.sh"
    sf_installed() { return 0; }
    sf_running_core_version() { printf '26.10.31\n'; }
    systemctl() { return 0; }
    sf_os_read() { SF_OS_ID=debian; SF_OS_VERSION=12; }
    printf '{"node":{"name":"测试节点","address":"203.0.113.10","port":443},"core":{"version":"26.10.31","channel":"stable"},"encryption":{"rtt":"0"},"reality":{"serverName":"example.com"},"presentation":{"role":"standalone"},"nextHop":null}' > "$TEST_WORK/state.json"
    sf_status > "$TEST_WORK/status.txt" 2>&1
    ! grep -Eq '管理器源码|公网可达|最近检测|历史结果|内存|源码提交|直连路径' "$TEST_WORK/status.txt"
    grep -q '26.10.31 · 正式版' "$TEST_WORK/status.txt"
    [[ $(wc -l < "$TEST_WORK/status.txt") -le 9 ]]
    jq '.core.version="26.9.9"' "$TEST_WORK/state.json" > "$TEST_WORK/new.json"
    mv "$TEST_WORK/new.json" "$TEST_WORK/state.json"
    sf_status > "$TEST_WORK/mismatch.txt" 2>&1
    grep -q '与运行版本不同' "$TEST_WORK/mismatch.txt"
)
pass 'compact status removes clutter and still flags actual version mismatch'
(
    sf_role() { printf 'standalone\n'; }
    sf_guide() { touch "$TEST_WORK/unexpected-setup"; }
    sf_chain_manage_menu > "$TEST_WORK/no-chain.txt" 2>&1
    [[ ! -e $TEST_WORK/unexpected-setup ]]
    grep -q '尚未配置链式' "$TEST_WORK/no-chain.txt"
    sf_role() { printf 'entry\n'; }
    sf_chain_setup_menu > "$TEST_WORK/has-chain.txt" 2>&1
    [[ ! -e $TEST_WORK/unexpected-setup ]]
    grep -q '管理链式' "$TEST_WORK/has-chain.txt"
)
pass 'separate chain entries never silently switch from management to setup'
(
    sf_color_enabled() { return 0; }
    sf_ask_choice '彩色菜单' '@分组' '1. 测试' '0. 返回' <<< 0 > "$TEST_WORK/color.txt" 2>&1
    [[ $SF_REPLY == 0 ]]
    grep -q $'\033\[1;36m' "$TEST_WORK/color.txt"
    grep -q $'\033\[36m' "$TEST_WORK/color.txt"
)
pass 'color highlights title and choices without turning section labels into actions'
printf 'TOTAL %d UI control-flow checks (business actions mocked)\n' "$count"
