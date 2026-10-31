#!/usr/bin/env bash
# Explicit host-level tuning; never called by install unless --bbr on is supplied.
sf_bbr_paths() {
    SF_BBR_SYSCTL=${SFXH_ETC%/sf-xray-hop}/sysctl.d/90-sf-xray-hop.conf
    SF_BBR_MODULE=${SFXH_ETC%/sf-xray-hop}/modules-load.d/90-sf-xray-hop.conf
    SF_BBR_OWNER=$SFXH_ETC/ownership.json
}
sf_bbr_status() {
    sf_bbr_paths
    sf_msg "TCP 拥塞控制：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')；默认队列：$(sysctl -n net.core.default_qdisc 2>/dev/null || printf '未知')"
    if [[ -f $SF_BBR_OWNER ]] && jq -e '.tuning.bbr!=null' "$SF_BBR_OWNER" >/dev/null; then
        sf_msg 'BBR：存在本项目管理记录（off 可恢复原值）。'
    else sf_msg 'BBR：未由本项目接管；默认不开启。'; fi
}
sf_bbr_restore() {
    local record cc qdisc file expected current temp
    sf_bbr_paths
    [[ -f $SF_BBR_OWNER ]] || return 0
    record=$(jq -c '.tuning.bbr // empty' "$SF_BBR_OWNER") || return
    [[ -n $record ]] || return 0
    cc=$(jq -er '.originalCC|select(test("^[a-zA-Z0-9_-]+$"))' <<< "$record") || return
    qdisc=$(jq -er '.originalQdisc|select(test("^[a-zA-Z0-9_-]+$"))' <<< "$record") || return
    # Only touch exact owned files; external edits are never silently discarded.
    for file in "$SF_BBR_SYSCTL" "$SF_BBR_MODULE"; do
        [[ ! -L $file ]] || { sf_fail 'BBR 文件变为符号链接，保留管理记录。'; return 1; }
        [[ ! -e $file ]] || [[ -f $file ]] || return 1
        if [[ $file == "$SF_BBR_SYSCTL" ]]; then expected=$(jq -r .sysctlSha256 <<< "$record"); else expected=$(jq -r .moduleSha256 <<< "$record"); fi
        [[ ! -f $file || $(sf_hash "$file") == "$expected" ]] || { sf_fail "BBR 文件被外部修改，未覆盖：$file"; return 1; }
    done
    current=$(sysctl -n net.ipv4.tcp_congestion_control) || return
    [[ $current == bbr || $current == "$cc" ]] || { sf_fail '拥塞控制已被其他工具修改，未覆盖。'; return 1; }
    current=$(sysctl -n net.core.default_qdisc) || return
    [[ $current == fq || $current == "$qdisc" ]] || { sf_fail '默认队列已被其他工具修改，未覆盖。'; return 1; }
    # Keep the journal until both runtime settings and persistent files recover.
    sysctl -q -w "net.ipv4.tcp_congestion_control=$cc" || return
    sysctl -q -w "net.core.default_qdisc=$qdisc" || return
    [[ $(sysctl -n net.ipv4.tcp_congestion_control) == "$cc" && $(sysctl -n net.core.default_qdisc) == "$qdisc" ]] || return 1
    rm -f -- "$SF_BBR_SYSCTL" "$SF_BBR_MODULE" || return
    temp=$(mktemp "$SFXH_ETC/bbr-owner.XXXXXXXX") || return
    jq 'del(.tuning.bbr)' "$SF_BBR_OWNER" > "$temp" && sf_atomic_json "$SF_BBR_OWNER" "$temp"
    local rc=$?; rm -f -- "$temp"; return "$rc"
}
sf_tune_bbr() (
    local action=${1:-status} work cc qdisc available release major minor file pending=0
    [[ $# -le 1 && ($action == on || $action == off || $action == status) ]] || return 2
    sf_root && sf_installed || return 2
    sf_bbr_paths
    if [[ $action == status ]]; then sf_bbr_status; return; fi
    sf_lock || return
    work=$(sf_temp) || { sf_unlock; return 1; }
    sf_bbr_finish() {
        local rc=$?
        if ((pending)); then sf_bbr_restore || sf_msg 'BBR 恢复未完成；管理记录已保留，请运行 sfxh tune bbr off 重试。'; fi
        sf_remove_tree "$work"; sf_unlock; return "$rc"
    }
    trap sf_bbr_finish EXIT
    trap 'exit 130' INT TERM HUP
    if [[ $action == off ]]; then sf_bbr_restore || return; sf_msg '已恢复本项目开启 BBR 前的默认值；其他配置保持。'; return; fi
    [[ -f $SF_BBR_OWNER && ! -L $SF_BBR_OWNER ]] && jq -e '.project=="SF-Xray-Hop"' "$SF_BBR_OWNER" >/dev/null || return 1
    if jq -e '.tuning.bbr!=null' "$SF_BBR_OWNER" >/dev/null; then
        sf_msg '已有 BBR 管理记录；请先检查状态，或运行 tune bbr off 后重试。'; return 1
    fi
    for file in "$SF_BBR_SYSCTL" "$SF_BBR_MODULE"; do
        [[ ! -e $file && ! -L $file ]] || { sf_fail "拒绝覆盖现有文件：$file"; return 1; }
        [[ ! -L ${file%/*} ]] || return 1
    done
    if [[ ${SFXH_TEST_MODE:-0} != 1 ]]; then
        if systemd-detect-virt --container --quiet || [[ -e /proc/user_beancounters ]]; then
            sf_fail '共享内核容器不在受管理 BBR 支持范围，请在宿主机配置。'; return 1
        fi
    fi
    release=$(uname -r); IFS=. read -r major minor _ <<< "$release"
    [[ $major =~ ^[0-9]+$ && $minor =~ ^[0-9]+$ ]] && ((major>4 || (major==4 && minor>=9))) || { sf_fail 'BBR 需要 Linux 4.9 或更高；不会替换内核或重启。'; return 1; }
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control) || return
    if [[ " $available " != *' bbr '* ]]; then
        command -v modprobe >/dev/null || { sf_fail '缺少 modprobe（kmod），无法加载 tcp_bbr。'; return 1; }
        modprobe tcp_bbr || { sf_fail '内核不提供 tcp_bbr；未修改 sysctl。'; return 1; }
        available=$(sysctl -n net.ipv4.tcp_available_congestion_control) || return
    fi
    [[ " $available " == *' bbr '* ]] || { sf_fail '内核没有可用的 BBR。'; return 1; }
    cc=$(sysctl -n net.ipv4.tcp_congestion_control) && qdisc=$(sysctl -n net.core.default_qdisc) || return
    printf '# Managed by SF-Xray-Hop; restore with sfxh tune bbr off\nnet.ipv4.tcp_congestion_control = bbr\nnet.core.default_qdisc = fq\n' > "$work/sysctl"
    printf '# Managed by SF-Xray-Hop\ntcp_bbr\n' > "$work/module"
    jq --arg cc "$cc" --arg qdisc "$qdisc" --arg sysctl "$(sf_hash "$work/sysctl")" --arg module "$(sf_hash "$work/module")" \
      '.tuning.bbr={originalCC:$cc,originalQdisc:$qdisc,sysctlSha256:$sysctl,moduleSha256:$module}' "$SF_BBR_OWNER" > "$work/owner.json" || return
    sf_atomic_json "$SF_BBR_OWNER" "$work/owner.json" || return
    pending=1
    mkdir -p "${SF_BBR_SYSCTL%/*}" "${SF_BBR_MODULE%/*}" || return
    install -m 644 "$work/sysctl" "$SF_BBR_SYSCTL" && install -m 644 "$work/module" "$SF_BBR_MODULE" || return
    sysctl -q -w net.core.default_qdisc=fq && sysctl -q -w net.ipv4.tcp_congestion_control=bbr || return
    [[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr && $(sysctl -n net.core.default_qdisc) == fq ]] || return 1
    pending=0
    sf_msg '已开启受管理 BBR + fq；仅影响系统默认值，不重启服务、不替换内核。'
)
