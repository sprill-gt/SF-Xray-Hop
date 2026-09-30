#!/usr/bin/env bash
sf_detect_address() {
    local a b
    a=$(curl -4 --fail --silent --proxy '' --noproxy '*' --connect-timeout 5 --max-time 8 https://api.ipify.org) || a=''
    b=$(curl -4 --fail --silent --proxy '' --noproxy '*' --connect-timeout 5 --max-time 8 https://icanhazip.com | tr -d '\r\n') || b=''
    if [[ -n $a && $a == "$b" && $a =~ ^[0-9.]+$ ]] && sf_host_valid "$a"; then printf '%s\n' "$a"; else return 1; fi
}
sf_deploy_manager() {
    local release
    if [[ -e $SFXH_UNIT ]] && ! grep -q 'SF-Xray-Hop managed' "$SFXH_UNIT"; then sf_fail '拒绝覆盖未知 service。'; return 1; fi
    if ! [[ -f $SFXH_ETC/owner ]]; then
        if getent passwd sfxray >/dev/null; then sf_fail 'sfxray 用户已经存在，拒绝接管。'; return 1; fi
        useradd --system --user-group --home-dir /nonexistent --shell /usr/sbin/nologin sfxray || return
        printf '%s\n' SF-Xray-Hop > "$SFXH_ETC/owner" || return
    elif ! getent passwd sfxray >/dev/null; then
        useradd --system --user-group --home-dir /nonexistent --shell /usr/sbin/nologin sfxray || return
    fi
    jq -n --argjson uid "$(id -u sfxray)" --arg install "$SFXH_INSTALL" --arg config "$SFXH_ETC" \
      '{project:"SF-Xray-Hop",serviceUid:$uid,installation:$install,configuration:$config,firewallRules:[],scheduledTasks:[]}' > "$SFXH_ETC/ownership.json" || return
    chmod 600 "$SFXH_ETC/ownership.json" || return
    if [[ $SFXH_CODE != "$SFXH_INSTALL" ]]; then
        release=$(sf_manager_stage "$SFXH_CODE") && sf_manager_activate "$release" || return
    fi
    mkdir -p "$SFXH_BIN" || return
    ln -sfn "$SFXH_INSTALL/sf-xray-hop" "$SFXH_BIN/sf-xray-hop" || return
    ln -sfn "$SFXH_INSTALL/sf-xray-hop" "$SFXH_BIN/sfxh" || return
    ln -sfn active/state.json "$SFXH_ETC/state.json" || return
    ln -sfn active/config.json "$SFXH_ETC/config.json" || return
    chown root:root "$SFXH_LOG" "$SFXH_LOG/manager" && chmod 711 "$SFXH_LOG" && chmod 700 "$SFXH_LOG/manager" || return
    chown sfxray:sfxray "$SFXH_LOG/core" && chmod 700 "$SFXH_LOG/core" || return
    install -m 644 "$SFXH_CODE/systemd/xray.service" "$SFXH_UNIT" || return
    systemd-analyze verify "$SFXH_UNIT" 2>/dev/null || { sf_fail 'systemd unit 验证失败。'; return 1; }
    systemctl daemon-reload && systemctl enable xray.service >/dev/null 2>&1
}
sf_build_initial_state() {
    local binary=$1 work=$2 name=$3 address=$4 port=$5 domain=$6 core=$7 version=$8 channel=$9 rtt=${10}
    local node_uuid direct_uuid relay_uuid
    node_uuid=$("$binary" uuid) && direct_uuid=$("$binary" uuid) && relay_uuid=$("$binary" uuid) || return
    [[ -n $name ]] || name="node-${node_uuid:0:8}"
    printf '%s\0' "$node_uuid" "$name" "$address" "$port" "$direct_uuid" "$relay_uuid" "$domain" "$(sf_random)" "/$(sf_random)" "$core" "$version" "$channel" |
      jq -Rs --slurpfile enc "$work/encryption.json" --slurpfile keys "$work/reality-keys.json" --argjson source "$(sf_source_info)" '
        split("\u0000") as $a | {schemaVersion:2,
        node:{id:$a[0],name:$a[1],address:$a[2],port:($a[3]|tonumber)},
        identities:{direct:{id:$a[4],email:"sf-xray-hop-direct"},relay:{id:$a[5],email:"sf-xray-hop-relay"}},
        encryption:$enc[0], reality:($keys[0]+{target:($a[6]+":443"),serverName:$a[6],shortId:$a[7]}),
        fingerprint:"chrome",xhttp:{path:$a[8],mode:"auto"},nextHop:null,
        presentation:{role:"standalone",downstreamName:null,downstreamNameSource:null,entry:null},
        core:{id:$a[9],version:$a[10],channel:$a[11],pinnedVersion:(if $a[11]=="pinned" then $a[10] else null end)},
        installationSource:$source}' > "$work/base.json" || return
    sf_rtt_values "$work/base.json" "$rtt" "$work/state.json"
}
sf_install() (
    local address='' port=443 rtt=0 target='' name='' channel=pre version='' work core binary domain
    while (($#)); do
        [[ $# -ge 2 ]] || { sf_usage_error '安装参数缺少值。'; return 2; }
        case "$1" in
            --address) address=$2 ;; --port) port=$2 ;; --rtt) rtt=$2 ;; --target) target=$2 ;;
            --name) name=$2 ;; --channel) channel=$2 ;; --version) version=${2#v}; channel=pinned ;;
            *) sf_usage_error "未知安装选项：$1"; return 2 ;;
        esac
        shift 2
    done
    if sf_installed; then sf_msg '本机已安装；身份、名称、用途、下游和更新频道保持不变。运行 sfxh 管理。'; return 0; fi
    sf_msg '步骤 1/3：检查系统与安装环境'
    sf_platform_check && sf_existing_check || return
    sf_lock || return
    sf_dependencies && sf_dirs || return
    sf_existing_check || return
    if [[ -f $SFXH_ETC/uninstalled && -L $SFXH_ETC/active ]]; then
        sf_msg '发现卸载时保留的配置；正在恢复原有身份和出口。安装选项不覆盖保留配置。'
        work=$(sf_temp) || return
        trap 'sf_remove_tree "$work"' EXIT
        cp -- "$(sf_state)" "$work/state.json" || return
        sf_deploy_manager && sf_tx_apply "$work/state.json" '恢复保留的安装' || return
        rm -f -- "$SFXH_ETC/uninstalled"
        sf_msg '已恢复原有安装，连接凭据保持不变。'
        return 0
    fi
    while :; do
        if [[ -z $port ]]; then
            if sf_tty; then sf_ask_text '监听端口' 443 || return; port=$SF_REPLY; else port=443; fi
        fi
        if sf_port_free "$port"; then break; fi
        sf_tty || return 2
        port=''
    done
    [[ $rtt == 0 || $rtt == 1 ]] || return 2
    if [[ -z $target ]]; then
        target=$(sf_target_default) || return
    fi
    [[ $channel == pre || $channel == stable || $channel == pinned ]] || return 2
    [[ $channel != pinned || -n $version ]] || { sf_usage_error 'pinned 频道需要 --version。'; return 2; }
    if [[ -z $address ]]; then
        address=$(sf_detect_address) || address=''
        if [[ -z $address ]]; then
            sf_tty || { sf_fail '无法确定公网地址，请提供 --address。'; return 2; }
            sf_ask_text '用于分享的公网 IP 或域名' '' || return; address=$SF_REPLY
        fi
    fi
    until sf_host_valid "$address"; do
        sf_fail '公网地址格式无效。' || :
        sf_tty || return 2
        sf_ask_text '用于分享的公网 IP 或域名' '' || return; address=$SF_REPLY
    done
    [[ -z $name ]] || sf_safe_name "$name" || return 2
    work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"' EXIT
    sf_msg '步骤 2/3：下载核心、生成身份并检测伪装目标'
    sf_release_metadata "$channel" "$version" "$work/release.json" || { sf_fail '无法读取官方 Release。'; return 1; }
    core=$(sf_core_download "$work/release.json" "$work" initialize) || return
    binary=$(sf_core_path "$core") || return
    version=$(jq -r '.tag_name|ltrimstr("v")' "$work/release.json")
    # Placeholder is never activated: each selected target must pass a real handshake.
    sf_build_initial_state "$binary" "$work" "$name" "$address" "$port" www.example.com "$core" "$version" "$channel" "$rtt" || return
    while ! domain=$(sf_target_select "$binary" "$target" "$work" "$work/state.json"); do
        sf_tty || return 1
        sf_msg '保留已填写的端口、RTT 和生成参数；可更换目标重新测试。'
        sf_ask_text '输入目标域名或 auto，输入0返回' '' || return
        target=$SF_REPLY
    done
    jq --arg domain "$domain" '.reality.target=($domain+":443")|.reality.serverName=$domain' "$work/state.json" > "$work/selected.json" || return
    mv -f "$work/selected.json" "$work/state.json" && sf_validate_state "$work/state.json" || return
    sf_msg '步骤 3/3：安装服务并验证本机连接'
    sf_deploy_manager || return
    sf_tx_apply "$work/state.json" '安装本机' || return
    sf_firewall_note
    sf_msg '本机安装完成，可直接使用；运行 sfxh 管理，菜单1可按需开启链式。'
    if sf_tty; then sf_view direct; else sf_msg '非交互安装不输出访问凭据；主动运行 sfxh view direct 查看。'; fi
)
