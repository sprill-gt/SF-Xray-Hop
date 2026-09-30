#!/usr/bin/env bash
sf_edit_begin() {
    sf_recover && sf_lock || return
    sf_self_recover || { sf_unlock; return 1; }
    SF_EDIT_STATE=$(sf_state) || { sf_unlock; return 1; }
    SF_EXPECT_GENERATION=$(basename "$(dirname "$SF_EDIT_STATE")")
    export SF_EXPECT_GENERATION
    SF_EDIT_WORK=$(sf_temp) || { sf_unlock; return 1; }
    sf_normalize_state "$SF_EDIT_STATE" "$SF_EDIT_WORK/base.json" || { sf_unlock; return 1; }
    SF_EDIT_STATE=$SF_EDIT_WORK/base.json
}
sf_chain_change() (
    local action=$1 profile work binary name
    sf_edit_begin || return; work=$SF_EDIT_WORK
    trap 'sf_remove_tree "$work"; sf_unlock' EXIT
    if [[ $action == set ]] && jq -e '.nextHop!=null' "$SF_EDIT_STATE" >/dev/null; then sf_fail '已有出口，请使用更换出口。'; return 2; fi
    if [[ $action == replace ]] && jq -e '.nextHop==null' "$SF_EDIT_STATE" >/dev/null; then sf_fail '尚无出口，请先设置。'; return 2; fi
    sf_read_uri "$work/link.txt" || return
    sf_uri_parse "$work/link.txt" "$work/profile.json" || return
    profile=$work/profile.json
    if jq -e --slurpfile p "$profile" '.identities.direct.id==$p[0].id or .identities.relay.id==$p[0].id or (.node.address==$p[0].address and .node.port==$p[0].port)' "$SF_EDIT_STATE" >/dev/null; then sf_fail '不能把本机链接设置为自己的出口。'; return 2; fi
    binary=$(sf_current_core) || return
    name=$(sf_import_name "$profile") || return
    sf_msg "候选名称：$name"
    sf_msg "候选出口：$(jq -r '.address+":"+(.port|tostring)' "$profile")"
    sf_msg "协议：VLESS Encryption / XHTTP auto / REALITY / Vision；下游 RTT：$(jq -r '.encryption|split(".")[2]' "$profile")"
    if sf_tty; then
        sf_ask_name '此出口在本机的名称' "$name" || return; name=$SF_REPLY
    fi
    sf_safe_name "$name" || { sf_usage_error '名称包含控制字符或超过80字／240字节。'; return 2; }
    sf_msg '正在独立测试候选出口，正式配置保持原样……'
    sf_probe_profile "$binary" "$profile" "$work/probe" "$work/probe-result.json" || return
    export SF_EXPECT_EXIT_RESULT=$work/probe-result.json
    jq --slurpfile profile "$profile" --arg name "$name" '.nextHop=$profile[0]|.presentation.role="entry"|.presentation.downstreamName=$name|.presentation.downstreamNameSource="local"' "$SF_EDIT_STATE" > "$work/state.json" || return
    # Test the complete prospective route before asking the user to commit it.
    sf_probe_candidate "$work/state.json" "$binary" "$binary" "$work/route-probe" || return
    if sf_tty; then sf_confirm '候选握手及完整路径已通过；现在切换出口（可能短暂重连）。入口身份及设备连接参数保持不变。' || return; fi
    sf_tx_apply "$work/state.json" '设置或更换出口'
)
sf_chain_remove() (
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"' EXIT
    if jq -e '.nextHop==null' "$SF_EDIT_STATE" >/dev/null; then sf_msg '当前已是本机出口。'; return 0; fi
    [[ ${1:-} == --yes ]] || sf_confirm '取消链式后，已有链式身份将从本机出口；设备和远端保存的链接不会删除。' || return
    jq '.nextHop=null|.presentation.role="standalone"|.presentation.downstreamName=null|.presentation.downstreamNameSource=null' "$SF_EDIT_STATE" > "$SF_EDIT_WORK/state.json" && sf_tx_apply "$SF_EDIT_WORK/state.json" '取消双机'
)
sf_set_rtt() (
    local mode=${1:-} scope=${2:-local}
    [[ $scope == local || $scope == downstream ]] || return 2
    if [[ -z $mode ]]; then
        sf_ask_choice '请选择握手模式' '1. 0-RTT' '2. 1-RTT' '0. 返回' || return
        case "$SF_REPLY" in 1) mode=0 ;; 2) mode=1 ;; *) return 130 ;; esac
    fi
    [[ $mode == 0 || $mode == 1 ]] || return 2
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"' EXIT
    if [[ $scope == local ]]; then
        sf_msg '修改本机 RTT，保留密钥；设备及连接本机的上游需要重新导入。不会自动同步另一台机器。'
        sf_rtt_values "$SF_EDIT_STATE" "$mode" "$SF_EDIT_WORK/state.json" || return
    else
        sf_msg '只修改入口到下游的客户端偏好；实际能否复用票据仍由出口机决定。本机对设备的设置不变。'
        sf_next_rtt_values "$SF_EDIT_STATE" "$mode" "$SF_EDIT_WORK/state.json" || return
    fi
    sf_tx_apply "$SF_EDIT_WORK/state.json" '修改握手模式'
)
sf_set_fingerprint() (
    local value=${1:-}
    case "$value" in chrome|firefox|safari) ;; *) sf_usage_error '指纹允许 chrome、firefox、safari。'; return 2 ;; esac
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"' EXIT
    jq --arg fp "$value" '.fingerprint=$fp' "$SF_EDIT_STATE" > "$SF_EDIT_WORK/state.json" && sf_tx_apply "$SF_EDIT_WORK/state.json" '修改导出指纹' online metadata
)
sf_set_target() (
    local requested=${1:-} binary domain
    if [[ -z $requested ]]; then local state; state=$(sf_state) || return; jq -r '.reality.serverName' "$state"; return; fi
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"' EXIT
    binary=$(sf_current_core) || return
    sf_msg '目标／SNI 改变后，设备和上游需要重新导入本节点链接。'
    domain=$(sf_target_select "$binary" "$requested" "$SF_EDIT_WORK" "$SF_EDIT_STATE") || return
    jq --arg domain "$domain" '.reality.target=($domain+":443")|.reality.serverName=$domain' "$SF_EDIT_STATE" > "$SF_EDIT_WORK/state.json" || return
    if sf_tty; then
        sf_confirm "候选目标已通过检查。当前用途：$(sf_role_label "$(sf_role "$SF_EDIT_STATE")")；SNI 同时影响本机直连和对接身份，设备及上游需重新导入。确认应用 $domain？" || return
    fi
    sf_tx_apply "$SF_EDIT_WORK/state.json" '修改 REALITY 目标'
)
sf_set_name() (
    sf_safe_name "$1" || { sf_usage_error '名称应为1–80字且不超过240字节，不得含控制或不可见字符。'; return 2; }
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"' EXIT
    jq --arg name "$1" '.node.name=$name' "$SF_EDIT_STATE" > "$SF_EDIT_WORK/state.json" && sf_tx_apply "$SF_EDIT_WORK/state.json" '修改节点名称' online metadata
)
sf_core_check() (
    local work state channel version
    state=$(sf_state) || return; work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"' EXIT
    channel=$(jq -r .core.channel "$state"); version=$(jq -r '.core.pinnedVersion // ""' "$state")
    sf_release_metadata "$channel" "$version" "$work/release.json" || { sf_fail '读取 Release 失败。'; return 1; }
    sf_msg "当前：$(jq -r .core.version "$state")；频道：$channel；候选：$(jq -r .tag_name "$work/release.json")"
)
sf_core_update() (
    local channel='' version='' core work consent='' old direction archive=''
    while (($#)); do
        if [[ $1 == --yes ]]; then consent=--yes; shift; continue; fi
        [[ $# -ge 2 ]] || return 2
        case "$1" in --channel) channel=$2 ;; --version) version=${2#v}; channel=pinned ;; *) return 2 ;; esac
        shift 2
    done
    sf_edit_begin || return; work=$SF_EDIT_WORK
    trap 'sf_remove_tree "$work"' EXIT
    [[ -n $channel ]] || channel=$(jq -r .core.channel "$SF_EDIT_STATE")
    [[ $channel == pre || $channel == stable || $channel == pinned ]] || return 2
    if [[ $channel == pinned && -z $version ]]; then version=$(jq -r '.core.pinnedVersion // .core.version' "$SF_EDIT_STATE"); fi
    sf_release_metadata "$channel" "$version" "$work/release.json" || { sf_fail '读取 Release 失败。'; return 1; }
    version=$(jq -r '.tag_name|ltrimstr("v")' "$work/release.json")
    old=$(jq -r .core.version "$SF_EDIT_STATE"); direction=$(sf_version_direction "$old" "$version") || return
    sf_msg "核心：$old → $version；目标频道：$channel；方向：$direction"
    if [[ $direction == downgrade && $consent != --yes ]]; then sf_confirm '目标核心版本更低。确认验证并降级？' || return; fi
    if [[ $direction == same ]]; then archive=$(jq -r '.archiveSha256//""' "$SFXH_VAR/cores/$(jq -r .core.id "$SF_EDIT_STATE")/metadata.json" 2>/dev/null) || archive=''; fi
    core=$(sf_core_download "$work/release.json" "$work" inspect "$archive" "$consent") || return
    [[ ! -f $work/archive-change-confirmed ]] || consent=--yes
    if [[ $direction == same && $core != "$(jq -r .core.id "$SF_EDIT_STATE")" && $consent != --yes ]]; then
        sf_confirm '相同版本标签的二进制摘要发生变化。确认验证并替换此核心？' || return
    fi
    jq --arg core "$core" --arg version "$version" --arg channel "$channel" '.core={id:$core,version:$version,channel:$channel,pinnedVersion:(if $channel=="pinned" then $version else null end)}' "$SF_EDIT_STATE" > "$work/state.json" || return
    sf_tx_apply "$work/state.json" '更新核心'
)
sf_core_rollback() (
    local id='' entry work version i=0 mode=online previous=0 current
    while (($#)); do
        case "$1" in --offline) mode=offline ;; --previous) previous=1 ;; *) [[ -z $id ]] || return 2; id=$1 ;; esac
        shift
    done
    local -a ids=() labels=()
    sf_edit_begin || return; work=$SF_EDIT_WORK
    trap 'sf_remove_tree "$work"' EXIT
    while IFS= read -r entry; do ids+=("$entry"); ((i+=1)); labels+=("$i. $entry"); done < <(
      find "$SFXH_VAR/cores" -mindepth 2 -maxdepth 2 -name metadata.json -exec jq -r 'select(.verified==true)|.id' {} \; | sort -Vr)
    ((${#ids[@]})) || { sf_fail '没有验证成功的归档核心。'; return 1; }
    if ((previous)); then
        [[ -z $id ]] || return 2
        current=$(jq -r .core.id "$SF_EDIT_STATE")
        while IFS= read -r entry; do
            version=$(cat "$entry")
            if [[ $version != "$current" && " ${ids[*]} " == *" $version "* ]]; then id=$version; break; fi
        done < <(find "$SFXH_ETC/generations" -mindepth 2 -maxdepth 2 -name core-id | sort -r)
        [[ -n $id ]] || { sf_fail '没有上一已验证核心可回滚。'; return 1; }
    fi
    if [[ -z $id ]]; then
        sf_ask_choice '选择历史核心（保留当前节点和出口配置）' "${labels[@]}" '0. 返回' || return
        [[ $SF_REPLY != 0 ]] || return 130
        id=${ids[SF_REPLY-1]}
    fi
    [[ " ${ids[*]} " == *" $id "* ]] || { sf_usage_error '请指定已验证的完整核心归档 ID。'; return 2; }
    sf_core_verify_archive "$id" || return
    version=$(jq -r .version "$SFXH_VAR/cores/$id/metadata.json")
    jq --arg id "$id" --arg version "$version" '.core={id:$id,version:$version,channel:"pinned",pinnedVersion:$version}' "$SF_EDIT_STATE" > "$work/state.json" && sf_tx_apply "$work/state.json" '回滚核心' "$mode"
)
sf_status() {
    local state g role health status='未运行' running='—'
    sf_msg 'SF-Xray-Hop'
    sf_msg "脚本版本：$SFXH_VERSION"
    if [[ -f $SFXH_CODE/source.json ]]; then sf_msg "管理器源码：$(jq -r '.commit//"离线包"' "$SFXH_CODE/source.json")"; fi
    if ! sf_installed; then sf_msg '安装状态：尚未安装'; return 0; fi
    state=$(sf_state) || return; g=$(basename "$(dirname "$state")")
    role=$(sf_role_label "$(sf_role "$state")")
    if systemctl is-active --quiet xray.service; then status='运行中（不代表公网可达）'; running=$(sf_running_core_version) || running='—'; fi
    sf_os_read >/dev/null 2>&1 || :
    sf_msg "当前机器：$role（$(jq -r .node.name "$state")）"
    sf_msg "操作系统：$SF_OS_ID $SF_OS_VERSION"
    sf_msg "本机地址：$(jq -r '.node.address+":"+(.node.port|tostring)' "$state")"
    sf_msg "运行核心：$running；配置核心：$(jq -r .core.version "$state")；频道：$(jq -r .core.channel "$state")"
    sf_msg "服务状态：$status"
    sf_msg "本机 RTT：$(jq -r '.encryption.rtt+"-RTT"' "$state")；SNI：$(jq -r .reality.serverName "$state")"
    sf_msg "直连路径：设备 → $(jq -r .node.name "$state") → Internet"
    if jq -e '.nextHop!=null' "$state" >/dev/null; then
        sf_msg "出口地址：$(jq -r '.nextHop.address+":"+(.nextHop.port|tostring)' "$state")"
        sf_msg "链式路径：设备 → $(jq -r .node.name "$state") → $(sf_jq -r 'include "model"; downstream_name' "$state") → Internet"
        sf_msg "下游 RTT：$(jq -r '.nextHop.encryption|split(".")[2]' "$state")"
    elif [[ $(sf_role "$state") == exit ]]; then sf_msg '链式状态：用途为出口 B，入口连接状态未知；可达性见最近检测'
    else sf_msg '链式状态：尚未启用'; fi
    health=$SFXH_VAR/cache/health.json
    if [[ -f $health ]] && jq -e --arg g "$g" '.generation==$g' "$health" >/dev/null; then
        sf_msg "最近检测：$(jq -r '.checkedAt+" / "+(if .status=="failed" then "失败" elif .status=="unverified-offline" then "离线恢复，出口未验证" else "本机协议通过（历史结果）" end)' "$health")"
    else sf_msg '最近检测：未检测'; fi
    if [[ -r /proc/meminfo ]]; then
        awk '/MemTotal:/{total=$2}/MemAvailable:/{avail=$2}END{if(total>0)printf "内存：%.0f / %.0f MiB（已用 / 总计）\n",(total-avail)/1024,total/1024}' /proc/meminfo >&2
    fi
}
sf_logs() { local file; for file in "$SFXH_LOG/manager/manager.log" "$SFXH_LOG/core/core.log"; do [[ ! -f $file ]] || tail -n 100 "$file" | sf_redact; done; }
sf_uninstall() (
    local purge=--purge path resolved consent='' answer unit record partial=0 uid
    while (($#)); do case "$1" in --purge) purge=--purge ;; --keep-data) purge='' ;; --yes) consent=1 ;; *) return 2 ;; esac; shift; done
    if [[ -z $consent ]]; then
        sf_tty || { sf_usage_error '非交互卸载需要 --yes。'; return 2; }
        sf_msg '完整卸载将删除本机脚本、核心、身份凭据、配置和私密备份；远端及客户端副本不会删除。'
        [[ $purge == --purge ]] || sf_msg '你显式选择了 --keep-data，本次保留配置与脚本目录。'
        printf '输入 UNINSTALL 确认，回车取消：' >&2
        IFS= read -r answer || return 130
        [[ $answer == UNINSTALL ]] || return 130
    fi
    sf_lock || return
    # Validate every destructive root before stopping any service.
    for path in "$SFXH_ETC" "$SFXH_VAR" "$SFXH_RUN" "$SFXH_LOG" "$SFXH_INSTALL" "$(dirname "$SFXH_UNIT")" "$SFXH_BIN"; do
        resolved=$(realpath -m -- "$path") || { sf_unlock; return 1; }
        [[ $resolved == "$path" && $path != / && ! -L $path ]] || { sf_fail '卸载路径不是预期普通目录，未删除。'; sf_unlock; return 1; }
    done
    [[ -f $SFXH_ETC/owner && $(cat "$SFXH_ETC/owner") == SF-Xray-Hop ]] || { sf_fail '未找到本项目所有权标记。'; return 1; }
    if [[ -e $SFXH_UNIT ]]; then
        grep -q 'SF-Xray-Hop managed' "$SFXH_UNIT" || { sf_fail '服务所有权不匹配。'; return 1; }
    elif [[ ! -f $SFXH_ETC/uninstalled ]]; then sf_fail '服务所有权不匹配。'; return 1; fi
    [[ ! -L $SFXH_UNIT ]] || { sf_unlock; return 1; }
    for record in "$SFXH_RUN/probes/"sfxh-probe-*.service; do
        [[ -f $record && ! -L $record ]] || continue
        unit=${record##*/}
        [[ $unit =~ ^sfxh-probe-[a-f0-9]{16}\.service$ ]] || { sf_unlock; return 1; }
        if [[ $(systemctl show "$unit" -p Description --value 2>/dev/null) == 'SF-Xray-Hop owned temporary probe' ]]; then
            systemctl stop "$unit" || { sf_unlock; return 1; }
        elif [[ $(systemctl show "$unit" -p LoadState --value 2>/dev/null) != not-found ]]; then
            sf_msg "临时单元 $unit 所有权不符，保留该单元。"; partial=1
        fi
    done
    if [[ -f $SFXH_UNIT ]]; then systemctl disable --now xray.service >/dev/null 2>&1 || { sf_unlock; return 1; }; fi
    touch "$SFXH_ETC/uninstalled" || { sf_unlock; return 1; }
    rm -f -- "$SFXH_UNIT" || { sf_unlock; return 1; }
    systemctl daemon-reload || { sf_unlock; return 1; }
    for path in "$SFXH_BIN/sfxh" "$SFXH_BIN/sf-xray-hop"; do
        if [[ $(readlink "$path" 2>/dev/null) == "$SFXH_INSTALL/sf-xray-hop" ]]; then rm -f -- "$path" || { sf_unlock; return 1; }; fi
    done
    # Exact, resolved managed roots only; no computed traversal or shared packages.
    if [[ $purge == --purge ]]; then
        for path in "$SFXH_ETC" "$SFXH_VAR" "$SFXH_RUN" "$SFXH_LOG" "$SFXH_INSTALL"; do
            resolved=$(realpath -m -- "$path") || { sf_unlock; return 1; }
            [[ $resolved == "$path" && $path != / ]] || { sf_unlock; return 1; }
        done
        # Only delete the account created by this installation, without a home tree.
        if [[ ${SFXH_TEST_MODE:-0} != 1 ]] && getent passwd sfxray >/dev/null; then
            uid=$(jq -r '.serviceUid//empty' "$SFXH_ETC/ownership.json" 2>/dev/null) || uid=''
            if [[ -z $uid || $(id -u sfxray) != "$uid" || $(getent passwd sfxray | cut -d: -f6-7) != /nonexistent:/usr/sbin/nologin ]] || pgrep -u sfxray >/dev/null; then
                sf_msg '专用用户所有权或空闲状态无法确认，保留该用户；继续删除本项目私密文件。'; partial=1
            else
                userdel sfxray || partial=1
                if getent group sfxray >/dev/null && [[ -z $(getent group sfxray | cut -d: -f4) ]]; then groupdel sfxray || partial=1; fi
            fi
        fi
        rm -rf -- "$SFXH_ETC" "$SFXH_VAR" "$SFXH_RUN" "$SFXH_LOG" "$SFXH_INSTALL" || { sf_unlock; return 1; }
        sf_msg '本项目文件和私密备份已清除；共享依赖、SSH、其他服务及外部副本保持。不是存储介质安全擦除。'
    else
        sf_msg "服务和命令入口已卸载。私密配置、备份和管理程序保留在 $SFXH_ETC 与 $SFXH_INSTALL。"
    fi
    sf_unlock
    return "$partial"
)
