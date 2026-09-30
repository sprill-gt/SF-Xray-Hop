#!/usr/bin/env bash
sf_target_default() {
    local domain
    while IFS= read -r domain; do
        [[ -n $domain && $domain != \#* ]] || continue
        sf_domain "$domain" || { sf_fail '默认 REALITY 目标格式无效。'; return 2; }
        printf '%s\n' "$domain"
        return 0
    done < "$SFXH_CODE/data/reality-targets.txt"
    sf_fail '未配置默认 REALITY 目标。'
}
sf_target_check() {
    local binary=$1 domain=$2 work=$3 target
    target=$domain:443
    sf_domain "$domain" || { sf_fail '请输入有效的 REALITY 目标域名。'; return 2; }
    timeout 5 getent ahosts "$domain" > "$work/dns.txt" || { sf_fail 'REALITY 目标 DNS 失败。'; return 1; }
    # Fixed port, validated DNS name. No command interpolation into a shell.
    timeout 5 bash -c 'exec 3<>/dev/tcp/"$1"/443' bash "$domain" 2>/dev/null || { sf_fail 'REALITY 目标 TCP 443 不通。'; return 1; }
    timeout 10 openssl s_client -connect "$target" -servername "$domain" -verify_hostname "$domain" -verify_return_error -tls1_3 -alpn h2 </dev/null > "$work/tls.txt" 2>&1 || { sf_fail 'REALITY 目标证书或 TLS 1.3 验证失败。'; return 1; }
    grep -q 'ALPN protocol: h2' "$work/tls.txt" || { sf_fail 'REALITY 目标没有协商 H2。'; return 1; }
    sf_probe_tls "$binary" "$domain" "$work/tls-ping.txt" || return 1
    awk '/Pinging with SNI/{active=1} active{print}' "$work/tls-ping.txt" > "$work/tls-sni.txt"
    grep -q 'Handshake succeeded' "$work/tls-sni.txt" && grep -q 'TLS 1.3' "$work/tls-sni.txt" || { sf_fail 'Xray 的 SNI TLS 检测未通过。'; return 1; }
}
sf_target_select() {
    local binary=$1 requested=$2 work=$3 baseline=${4:-} domain
    if [[ $requested != auto ]]; then sf_target_candidate "$binary" "$requested" "$work" "$baseline" || return; printf '%s\n' "$requested"; return; fi
    while IFS= read -r domain; do
        [[ -n $domain && $domain != \#* ]] || continue
        sf_msg "检测 REALITY 候选：$domain"
        if sf_target_candidate "$binary" "$domain" "$work" "$baseline"; then printf '%s\n' "$domain"; return 0; fi
    done < "$SFXH_CODE/data/reality-targets.txt"
    sf_fail '没有通过检测的 REALITY 目标；请改用手动域名，当前配置未改变。'
}
sf_target_candidate() {
    local binary=$1 domain=$2 work=$3 baseline=$4
    sf_target_check "$binary" "$domain" "$work" || return
    [[ -n $baseline ]] || return 0
    jq --arg domain "$domain" '.reality.target=($domain+":443")|.reality.serverName=$domain' "$baseline" > "$work/target-state.json" || return
    sf_probe_candidate "$work/target-state.json" "$binary" "$binary" "$work/target-probe"
}
