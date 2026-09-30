#!/usr/bin/env bash
sf_os_read() {
    local file=${1:-/etc/os-release} key value
    SF_OS_ID='' SF_OS_VERSION='' SF_OS_SUPPORT=target
    [[ -r $file ]] || return 2
    while IFS='=' read -r key value; do
        value=${value%$'\r'}; value=${value#\"}; value=${value%\"}; value=${value#\'}; value=${value%\'}
        case "$key" in ID) SF_OS_ID=$value ;; VERSION_ID) SF_OS_VERSION=$value ;; esac
    done < "$file"
    if [[ $SF_OS_ID == debian && $SF_OS_VERSION =~ ^(12|13)(\.[0-9]+)*$ ]] ||
       [[ $SF_OS_ID == ubuntu && $SF_OS_VERSION =~ ^24\.04(\.[0-9]+)*$ ]]; then return 0; fi
    if [[ $SF_OS_ID == ubuntu && $SF_OS_VERSION =~ ^22\.04(\.[0-9]+)*$ ]]; then
        SF_OS_SUPPORT=experimental
        return 0
    fi
    sf_usage_error "不支持的系统：$SF_OS_ID $SF_OS_VERSION；支持 Debian 12/13 和 Ubuntu 24.04。"
}
sf_platform_check() {
    sf_root || return
    sf_os_read || return
    [[ $(uname -m) == x86_64 ]] || { sf_usage_error 'v1 仅支持 amd64。'; return 2; }
    [[ $(cat /proc/1/comm) == systemd ]] && command -v systemctl >/dev/null || { sf_fail '需要运行 systemd 的 Linux VPS。'; return 2; }
    systemctl show --property=Version --value >/dev/null 2>&1 || { sf_fail '无法访问 systemd 管理接口。'; return 1; }
    local free
    free=$(LC_ALL=C df -Pk /var | awk 'NR==2 {print $4}')
    [[ $free =~ ^[0-9]+$ ]] && ((free >= 524288)) || { sf_fail '需要至少 512 MiB 可用磁盘空间。'; return 1; }
    sf_msg "系统检查通过：$SF_OS_ID $SF_OS_VERSION / amd64"
    if [[ $SF_OS_SUPPORT == experimental ]]; then sf_msg 'Ubuntu 22.04 当前为实验兼容，验证结果请见 docs/testing.md。'; fi
}
sf_dependencies() {
    local pkg status log code
    local -a missing=()
    for pkg in bash jq curl ca-certificates unzip openssl coreutils util-linux iproute2 procps iputils-ping; do
        status=$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null) || status=''
        [[ $status == 'install ok installed' ]] || missing+=("$pkg")
    done
    ((${#missing[@]})) || return 0
    log=$(mktemp) || return
    sf_msg "正在安装必要依赖：${missing[*]}"
    LC_ALL=C DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get -o DPkg::Lock::Timeout=60 -o APT::Update::Error-Mode=any update >"$log" 2>&1
    code=$?
    if (( code == 0 )); then
        LC_ALL=C DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get -o DPkg::Lock::Timeout=60 install -y --no-install-recommends "${missing[@]}" >>"$log" 2>&1
        code=$?
    fi
    if ((code)); then
        if grep -Eq 'lock|another process' "$log"; then sf_msg 'APT 正被其他任务使用；没有删除锁。'
        elif grep -Eq 'Unable to locate|no installation candidate' "$log"; then sf_msg '官方软件源中缺少必要软件包，请检查软件源配置。'
        else sf_msg '软件源更新或依赖安装失败，请检查系统网络和 APT。'; fi
        rm -f -- "$log"; return 1
    fi
    rm -f -- "$log"
}
sf_existing_check() {
    local f
    if [[ -e $SFXH_ETC/owner ]]; then
        [[ $(cat "$SFXH_ETC/owner") == SF-Xray-Hop ]] || { sf_fail '发现未知管理目录。'; return 1; }
        sf_installed && { sf_fail '本机已安装；请进入 sfxh 管理。'; return 1; }
        return 0
    fi
    for f in /usr/local/bin/xray /usr/bin/xray /etc/xray /usr/local/etc/xray /etc/systemd/system/xray.service /lib/systemd/system/xray.service /usr/lib/systemd/system/xray.service; do
        [[ ! -e $f && ! -L $f ]] || { sf_fail "发现已有 Xray：$f；v1 不接管。"; return 1; }
    done
    if systemctl cat xray.service >/dev/null 2>&1 || pgrep -x xray >/dev/null 2>&1; then sf_fail '发现已有 Xray 服务或进程，停止安装。'; return 1; fi
}
sf_port_free() {
    [[ ${#1} -le 5 && $1 =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)) || { sf_usage_error '端口必须在1至65535之间。'; return 2; }
    [[ -z $(ss -H -ltn "sport = :$1") ]] || { sf_fail "TCP $1 已被占用。"; return 1; }
}
sf_firewall_note() {
    sf_msg '请在系统和云厂商防火墙中放行所选 TCP 端口；SSH 规则保持原样。'
    if command -v ufw >/dev/null; then LC_ALL=C ufw status 2>/dev/null | head -n 1 >&2; fi
    if command -v nft >/dev/null && nft list ruleset 2>/dev/null | grep -q 'hook input'; then sf_msg '检测到 nftables 入站规则，请核对端口。'; fi
}
