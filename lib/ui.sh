#!/usr/bin/env bash
sf_ask_choice() {
    sf_tty || { sf_usage_error '需要交互终端；非交互调用请提供明确参数。'; return 2; }
    local title=$1 label default='' choice
    shift
    sf_msg ''; sf_msg "$title"
    local -a choices=()
    for label in "$@"; do
        if [[ $label == --default=* ]]; then default=${label#*=}; continue; fi
        sf_msg "$label"; choices+=("${label%%.*}")
    done
    while :; do
        printf '请输入数字：' >&2
        IFS= read -r SF_REPLY || return 130
        [[ -n $SF_REPLY ]] || SF_REPLY=$default
        for choice in "${choices[@]}"; do [[ $SF_REPLY != "$choice" ]] || return 0; done
        sf_msg '请输入菜单中显示的数字。'
    done
}
sf_ask_text() {
    sf_tty || { sf_usage_error '缺少必要参数。'; return 2; }
    local title=$1 default=${2:-}
    while :; do
        printf '%s%s（输入0返回）：' "$title" "${default:+ [$default]}" >&2
        IFS= read -r SF_REPLY || return 130
        [[ $SF_REPLY != 0 ]] || return 130
        [[ -n $SF_REPLY ]] || SF_REPLY=$default
        [[ -z $SF_REPLY || $SF_REPLY =~ [[:cntrl:]] ]] || return 0
        sf_msg '请输入有效内容。'
    done
}
sf_ask_name() {
    while :; do
        sf_ask_text "$1" "${2:-}" || return
        sf_safe_name "$SF_REPLY" && return 0
        sf_msg '名称应为1–80字且不超过240字节，不得含控制或不可见字符。'
    done
}
sf_pause() { if sf_tty; then sf_msg '按回车继续。'; IFS= read -r _ || :; fi; }
sf_action_done() {
    case "$1" in 0) ;; 130) sf_msg '已取消／保存进度。' ;; *) sf_msg '操作未完成，请按上方提示处理。当前结果不记为通过。' ;; esac
    sf_pause
}
sf_guide_save() (
    local position=$1 stage=$2 temp generation=''
    sf_lock || return
    temp=$(sf_temp) || return
    trap 'sf_remove_tree "$temp"; sf_unlock' EXIT
    generation=$(sf_generation) || generation=''
    jq -n --arg position "$position" --arg stage "$stage" --arg generation "${generation##*/}" --arg at "$(sf_now)" \
      '{schemaVersion:1,position:$position,stage:$stage,generation:$generation,updatedAt:$at}' > "$temp/guide.json" &&
      sf_atomic_json "$SFXH_ETC/guide.json" "$temp/guide.json"
)
sf_exit_instructions() {
    sf_msg '保留当前入口 A（1号机）窗口，打开出口 B（2号机）的 SSH 窗口。'
    sf_msg '若出口未安装，使用同一已验证发行来源：'
    if ! sf_install_command >&2; then sf_msg '本机来自离线包；复制同一完整发行包，在包目录运行 sudo bash install.sh。'; fi
    sf_msg '在出口 B 运行 sudo sfxh → 1 链式引导 → 2 出口 B。'
    sf_msg '显示“对接链接”，复制完整一行；回到入口 A 的当前步骤粘贴。'
    sf_msg '设备最终使用入口 A 的链式链接；两台机器不需要 SSH 信任。'
}
sf_setup() {
    if sf_installed; then
        sf_msg '检测到已有安装；保留身份、名称、角色、下游及频道。'
        sf_tty || return 0
        if [[ -x $SFXH_INSTALL/sf-xray-hop && $(readlink -f "$SFXH_INSTALL/sf-xray-hop") != "$SFXH_CODE/sf-xray-hop" ]]; then bash "$SFXH_INSTALL/sf-xray-hop" menu
        else sf_menu; fi
        return $?
    fi
    local state
    sf_msg 'SF-Xray-Hop 一键安装（暂时性实验产物）'
    sf_msg '默认：单机直连 / TCP 443 / 0-RTT / archive.archlinux.org / Xray 官方 Pre。'
    sf_install || return
    sf_tty || return 0
    state=$(sf_state) || return
    sf_msg "当前名称：$(jq -r .node.name "$state")；以后输入 sfxh 管理。"
    sf_ask_choice '可选设置名称（回车跳过）' '1. 修改名称' '0. 跳过' --default=0 || return
    if [[ $SF_REPLY == 1 ]]; then sf_ask_name '本机名称' "$(jq -r .node.name "$state")" && sf_set_name "$SF_REPLY" || :; fi
    sf_ask_choice '现在可以直连；链式可稍后开启（回车退出）' '1. 进入管理菜单' '0. 退出' --default=0 || return
    [[ $SF_REPLY != 1 ]] || sf_menu
}
sf_guide_complete() {
    local state
    state=$(sf_state) || return
    sf_msg '入口侧链式复测通过；仍需在手机／电脑验证公网连接。'
    sf_msg "可登记到出口 B 的入口地址：$(jq -r .node.address "$state")"
    while :; do
        sf_ask_choice '设备连接' '1. 显示链式链接（日常使用）' '2. 显示直连链接（应急使用）' '3. 导出链式客户端 JSON' '0. 返回' || return
        case "$SF_REPLY" in 1) sf_view relay ;; 2) sf_view direct ;; 3) sf_view json relay ;; 0) return 0 ;; esac
    done
}
sf_entry_registration_menu() {
    local address name=''
    sf_msg '可选登记入口 A；仅保存在本机，不证明已连接。'
    printf '入口 IP／域名（回车跳过，0返回）：' >&2
    IFS= read -r address || return 130
    [[ -n $address && $address != 0 ]] || return 0
    until sf_host_valid "$address"; do sf_ask_text '地址无效，请输入入口 IP／域名' '' || return; address=$SF_REPLY; done
    printf '入口名称（可选，回车跳过）：' >&2
    IFS= read -r name || return 130
    [[ -z $name ]] || sf_safe_name "$name" || { sf_msg '名称无效，地址尚未保存。'; return 2; }
    sf_set_entry "$address" "$name"
}
sf_guide() {
    local position='' state role code
    sf_tty || { sf_usage_error '向导需要交互终端；自动化请用 chain 和 node 命令。'; return 2; }
    if ! sf_installed; then sf_install || return; fi
    state=$(sf_state) || return; role=$(sf_role "$state") || return
    sf_msg "当前机器：$(jq -r '.node.name+" / "+.node.address' "$state")；用途：$(sf_role_label "$role")"
    if [[ $role == entry ]]; then
        while :; do
            sf_ask_choice '管理当前链式连接' '1. 检查连接并查看设备链接' '2. 更换出口' '3. 取消链式，恢复本机出口' '4. 排障与测速' '5. 查看日志' '0. 返回' || return
            case "$SF_REPLY" in 1) sf_health_current && sf_guide_complete ;; 2) sf_chain_change replace && sf_guide_save entry complete && sf_guide_complete ;;
                3) sf_chain_remove && return 0 ;; 4) sf_test_menu ;; 5) sf_logs ;; 0) return 0 ;; esac
            sf_action_done "$?"
        done
    fi
    if [[ -f $SFXH_ETC/guide.json ]]; then
        sf_ask_choice '检测到向导进度' '1. 继续上次用途' '2. 重新选择用途' '0. 返回' || return
        case "$SF_REPLY" in 1) position=$(jq -r '.position' "$SFXH_ETC/guide.json"); [[ $position == entry || $position == exit ]] || position='' ;; 0) return 0 ;; esac
    fi
    if [[ -z $position ]]; then
        sf_ask_choice '当前机器准备承担什么用途？' '1. 入口 A（1号机）：设备先连接它' '2. 出口 B（2号机）：由它最终访问互联网' '0. 返回' || return
        case "$SF_REPLY" in 1) position=entry ;; 2) position='exit' ;; 0) return 0 ;; esac
    fi
    if [[ $position == exit ]]; then
        sf_health_current && sf_set_role exit && sf_guide_save exit ready || return
        sf_msg '出口已配置，等待 A 对接（本机没有入口连接成功的证据）。'
        while :; do
            sf_ask_choice '出口管理' '1. 显示对接链接，交给入口 A' '2. 可选登记入口地址' '3. 显示本机直连链接' '4. 检查连接与测速' '0. 返回' || return
            case "$SF_REPLY" in
                1) sf_view handoff || return
                   sf_msg '切换到 A：sfxh → 1 链式引导 → 1 入口 A → 粘贴。设备链式链接将在 A 生成。' ;;
                2) sf_entry_registration_menu ;; 3) sf_view direct ;; 4) sf_test_menu ;; 0) return 0 ;;
            esac
        done
    fi
    sf_guide_save entry awaiting_link || return
    while :; do
        sf_ask_choice '准备出口 B' '1. 已有对接链接，立即粘贴' '2. 尚未准备，显示出口步骤' '0. 保存进度，稍后继续' || return
        case "$SF_REPLY" in
            0) return 0 ;; 2) sf_exit_instructions ;;
            1) if sf_chain_change set; then sf_guide_save entry complete && sf_guide_complete; return $?
               else code=$?; [[ $code != 130 ]] || return 0; fi
               sf_msg '候选未提交，原配置保留；可重新粘贴或稍后继续。' ;;
        esac
    done
}
sf_chain_view_menu() {
    local state
    state=$(sf_state) || return
    case "$(sf_role "$state")" in
        entry) sf_view relay; return $? ;;
        exit) sf_view relay || [[ $? == 2 ]]; return $? ;;
    esac
    sf_ask_choice '链式尚未启用' '1. 开始链式引导' '0. 返回' || return
    [[ $SF_REPLY != 1 ]] || sf_guide
}
sf_node_menu() {
    local state
    while :; do
        state=$(sf_state) || return
        sf_ask_choice '节点设置（名称不会改变身份或系统主机名）' '1. 修改本机名称' '2. 修改本地下游别名' '3. 修改用途' '4. 登记入口地址（出口 B）' '5. 清除本机登记的入口地址' '0. 返回' || return
        case "$SF_REPLY" in
            1) sf_ask_name '本机名称' "$(jq -r .node.name "$state")" && sf_set_name "$SF_REPLY" ;;
            2) if jq -e '.nextHop!=null' "$state" >/dev/null; then sf_ask_name '本地下游别名' "$(sf_jq -r 'include "model"; downstream_name' "$state")" && sf_set_downstream_name "$SF_REPLY"; else sf_msg '本机没有下游。'; fi ;;
            3) sf_ask_choice '选择用途（入口 A 需通过链式引导建立）' '1. 单机' '2. 出口 B' '3. 进入链式引导' '0. 返回' || return
               case "$SF_REPLY" in 1) sf_set_role standalone ;; 2) sf_set_role exit ;; 3) sf_guide ;; 0) : ;; esac ;;
            4) sf_entry_registration_menu ;; 5) sf_set_entry '' ;; 0) return 0 ;;
        esac
        sf_action_done "$?"
    done
}
sf_rtt_menu() {
    local state scope=local mode
    state=$(sf_state) || return
    sf_msg "本机接受／导出：$(jq -r '.encryption.rtt+"-RTT"' "$state")"
    if jq -e '.nextHop!=null' "$state" >/dev/null; then
        sf_msg "入口到下游：$(jq -r '.nextHop.encryption|split(".")[2]' "$state")"
        sf_ask_choice '选择修改范围（两项独立）' '1. 本机 RTT（影响设备／上游）' '2. 入口到下游 RTT（仅客户端偏好）' '0. 返回' || return
        case "$SF_REPLY" in 1) ;; 2) scope=downstream ;; 0) return 0 ;; esac
    fi
    sf_ask_choice '选择 RTT' '1. 0-RTT：允许恢复' '2. 1-RTT：完整握手' '0. 返回' || return
    case "$SF_REPLY" in 1) mode=0 ;; 2) mode=1 ;; 0) return 0 ;; esac
    sf_set_rtt "$mode" "$scope"
}
sf_sni_menu() {
    sf_set_target
    sf_ask_choice '修改 SNI（先检查候选，再确认应用）' '1. 输入域名' '2. 从候选目标自动选择' '0. 返回' || return
    case "$SF_REPLY" in
        1) while :; do
               sf_ask_text '目标域名' '' || return
               if sf_domain "$SF_REPLY"; then sf_set_target "$SF_REPLY"; return $?; fi
               sf_msg '域名格式无效，请重新输入。'
           done ;;
        2) sf_set_target auto ;; 0) return 0 ;;
    esac
}
sf_core_menu() {
    while :; do
        sf_ask_choice 'Xray 核心管理（不改变管理脚本）' '1. 按当前频道检查并更新' '2. 切换 Pre／正式版' '3. 回滚上一可用核心' '4. 固定指定版本（高级）' '0. 返回' || return
        case "$SF_REPLY" in
            1) sf_core_update ;;
            2) sf_ask_choice '核心频道' '1. Pre：仅预发布' '2. Stable：仅正式发布' '0. 返回' || return
               case "$SF_REPLY" in 1) sf_core_update --channel pre ;; 2) sf_core_update --channel stable ;; 0) : ;; esac ;;
            3) sf_core_rollback --previous ;; 4) sf_ask_text '固定版本，如26.9.9' '' && sf_core_update --version "$SF_REPLY" ;; 0) return 0 ;;
        esac
        sf_action_done "$?"
    done
}
sf_self_menu() {
    sf_self_info
    sf_self_check || :
    sf_ask_choice '脚本自身更新（核心与节点参数保持）' '1. 更新到最新项目正式发行版' '2. 回滚上一个可恢复脚本' '0. 返回' || return
    case "$SF_REPLY" in 1) sf_self_update || return ;; 2) sf_self_rollback || return ;; 0) return 0 ;; esac
    if [[ ${SFXH_TEST_MODE:-0} != 1 ]]; then exec bash "$SFXH_INSTALL/sf-xray-hop" menu; fi
}
sf_test_menu() {
    sf_ask_choice '连接检查' '1. 测试两条身份线路' '2. 完整诊断' '3. 下游测试及 ICMP' '4. 性能测试（消耗流量）' '0. 返回' || return
    case "$SF_REPLY" in 1) sf_health_current ;; 2) sf_doctor ;; 3) sf_chain_test ;;
        4) sf_bench_notice || return
           sf_ask_choice '测试线路' '1. Relay' '2. Direct' '0. 返回' || return
           case "$SF_REPLY" in 1) sf_benchmark relay ;; 2) sf_benchmark direct ;; 0) return 0 ;; esac ;; 0) return 0 ;; esac
}
sf_menu() {
    sf_tty || { sf_help; return 2; }
    while :; do
        sf_status
        if ! sf_installed; then
            sf_ask_choice 'SF-Xray-Hop' '1. 安装本机' '2. 链式连接引导' '3. 检查安装环境' '0. 退出' --default=0 || return
            case "$SF_REPLY" in 1) sf_setup ;; 2) sf_guide ;; 3) sf_platform_check ;; 0) return 0 ;; esac
        else
            sf_ask_choice '主菜单' '1. 启动 / 管理链式代理引导' '2. Xray 核心管理（更新 / 正式版 / 回滚）' '3. 显示直连代理分享链接' '4. 显示链式代理分享链接' '5. 节点设置（名称 / 角色 / 关联机器）' '6. 修改 SNI' '7. RTT 设置' '8. 更新 SF-Xray-Hop 脚本' '9. 完整卸载' '0. 退出' --default=0 || return
            case "$SF_REPLY" in 1) sf_guide ;; 2) sf_core_menu ;; 3) sf_view direct ;; 4) sf_chain_view_menu ;; 5) sf_node_menu ;; 6) sf_sni_menu ;; 7) sf_rtt_menu ;; 8) sf_self_menu ;;
                9) sf_uninstall; if ! sf_installed; then return 0; fi ;; 0) return 0 ;; esac
        fi
        sf_action_done "$?"
    done
}
sf_help() {
    cat <<'HELP'
SF-Xray-Hop / sfxh — 一键直连、按需链式（发布候选版 RC）
  无参数                        中文数字菜单
  version                       查看当前脚本版本，无需 sudo／联网
  --version                     仅输出脚本版本号，供自动化读取
  install [选项]                默认443 / 0-RTT / archive.archlinux.org / pre
                                --address 地址 --port 端口 --rtt 0|1 --target 域名|auto
                                --name 名称 --channel pre|stable --version 核心版本
  guide                         两端链式连接引导
  view [direct|relay|handoff]    默认直连；relay 仅入口，handoff 仅出口
  view json [direct|relay]       客户端 JSON，默认 direct，HTTP 127.0.0.1:10809
  node name 名称                修改本机显示名
  node downstream-name 名称     修改本地下游别名
  node role standalone|exit [--yes]
  node entry 地址 [名称]        出口登记入口；node entry clear 清除本机记录
  status / doctor / test        状态／诊断／两条身份测试
  test --performance [--profile direct|relay]
  chain set / replace           隐藏输入或 stdin 导入出口对接链接
  chain remove [--yes] / test    明确取消链式／测试下游
  rtt [0|1]                     修改本机 RTT，保留密钥
  rtt downstream 0|1            仅修改到下游的 RTT 偏好
  target [auto|set 域名]         查看／修改 SNI 与 REALITY 目标
  fingerprint chrome|firefox|safari
  core check                    当前频道候选
  core update [--channel pre|stable|pinned] [--version 版本] [--yes]
  core rollback [完整归档ID|--previous] [--offline]
  core prune                    保留至少5个已验证核心
  self check / update [--version 版本 --allow-pre] [--yes]
  self rollback [--yes]          验证当前状态后回退管理脚本
  logs                          脱敏日志
  uninstall [--yes] [--keep-data] 默认完整删除；交互需输入 UNINSTALL
HELP
}
sf_main() {
    local command=${1:-menu} sub
    (($#==0)) || shift
    case "$command" in
        help|-h|--help) sf_help; return 0 ;;
        version) [[ $# == 0 ]] || return 2; printf 'SF-Xray-Hop\n脚本版本：%s\n' "$SFXH_VERSION"; return 0 ;;
        --version) printf '%s\n' "$SFXH_VERSION"; return 0 ;;
    esac
    if [[ $command == internal ]]; then
        [[ $# == 1 ]] || return 2
        case "$1" in prepare-runtime) sf_prepare_runtime ;; runtime) sf_runtime ;; setup) sf_root && sf_setup ;; upgrade-manager) sf_upgrade_manager ;; *) return 2 ;; esac
        return $?
    fi
    sf_root || return
    case "$command" in menu|guide|status|doctor|logs) [[ $# == 0 ]] || return 2 ;; fingerprint) [[ $# == 1 ]] || return 2 ;; view) [[ $# -le 2 && ($# -le 1 || $1 == json) ]] || return 2 ;; esac
    if [[ $command != install && $command != menu && $command != guide ]]; then command -v jq >/dev/null || { sf_fail '缺少 jq；请先安装本机。'; return 2; }; fi
    case "$command" in
        menu) sf_menu ;; install) sf_install "$@" ;; guide) sf_guide ;; view) sf_view "$@" ;; status) sf_status ;; doctor) sf_doctor ;;
        test) if (($#==0)); then sf_health_current
              elif [[ $1 == --performance ]]; then shift
                  if (($#==0)); then sf_benchmark relay
                  elif [[ $# == 2 && $1 == --profile && ($2 == direct || $2 == relay) ]]; then sf_benchmark "$2"; else return 2; fi
              else return 2; fi ;;
        node) sub=${1:-}; (($#==0)) || shift
              case "$sub" in name) [[ $# == 1 ]] || return 2; sf_set_name "$1" ;; downstream-name) [[ $# == 1 ]] || return 2; sf_set_downstream_name "$1" ;;
                  role) [[ $# == 1 || ($# == 2 && $2 == --yes) ]] || return 2; sf_set_role "$@" ;;
                  entry) if [[ $# == 1 && $1 == clear ]]; then sf_set_entry ''; else [[ $# == 1 || $# == 2 ]] || return 2; sf_set_entry "$@"; fi ;; *) return 2 ;; esac ;;
        chain) sub=${1:-}; (($#==0)) || shift
               case "$sub" in set|replace) [[ $# == 0 ]] || return 2; sf_chain_change "$sub" ;; remove) [[ $# == 0 || ($# == 1 && $1 == --yes) ]] || return 2; sf_chain_remove "$@" ;; test) [[ $# == 0 ]] || return 2; sf_chain_test ;; *) return 2 ;; esac ;;
        rtt) if [[ $# == 2 && $1 == downstream ]]; then sf_set_rtt "$2" downstream; elif [[ $# -le 1 ]]; then sf_set_rtt "${1:-}"; else return 2; fi ;;
        fingerprint) sf_set_fingerprint "$1" ;;
        target) if (($#==0)); then sf_set_target; elif [[ $# == 1 && $1 == auto ]]; then sf_set_target auto; elif [[ $# == 2 && $1 == set ]]; then sf_set_target "$2"; else return 2; fi ;;
        core) sub=${1:-}; (($#==0)) || shift
              if [[ $sub == check || $sub == prune ]]; then [[ $# == 0 ]] || return 2; fi
              case "$sub" in check) [[ $# == 0 ]] && sf_core_check ;; update) sf_core_update "$@" ;; rollback) sf_core_rollback "$@" ;; prune) [[ $# == 0 ]] && sf_core_prune ;; *) return 2 ;; esac ;;
        self) sub=${1:-}; (($#==0)) || shift
              case "$sub" in check) sf_self_check "$@" ;; update) sf_self_update "$@" ;; rollback) sf_self_rollback "$@" ;; *) return 2 ;; esac ;;
        logs) sf_logs ;; uninstall) sf_uninstall "$@" ;; *) sf_usage_error '未知命令，请运行 sfxh help。' ;;
    esac
}
