#!/usr/bin/env bash
sf_probe_data() {
    if [[ ${SFXH_TEST_MODE:-0} == 1 && -n ${SFXH_PROBES_FILE:-} ]]; then printf '%s\n' "$SFXH_PROBES_FILE"; else printf '%s/data/probes.json\n' "$SFXH_CODE"; fi
}
sf_local_port() {
    local port tries
    for tries in {1..20}; do
        port=$((20000 + $(od -An -N2 -tu2 /dev/urandom) % 40000))
        if ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then printf '%s\n' "$port"; return 0; fi
    done
    return 1
}
sf_wait_port() {
    local port=$1 pid=$2 i
    for i in {1..40}; do
        kill -0 "$pid" 2>/dev/null || return 1
        if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then return 0; fi
        sleep 0.1
    done
    return 1
}
sf_stop_probe() {
    if [[ ${2:-} =~ ^sfxh-probe-[a-f0-9]{16}\.service$ ]]; then
        if timeout 8 systemctl stop "$2" >/dev/null 2>&1 || [[ $(systemctl show "$2" -p LoadState --value 2>/dev/null) == not-found ]]; then
            rm -f -- "$SFXH_RUN/probes/$2"
        else sf_msg '临时探测尚未确认停止，保留归属记录供卸载处理；服务本身有运行时限。'; fi
    fi
    [[ -n ${1:-} ]] || return 0
    kill "$1" 2>/dev/null || :
    wait "$1" 2>/dev/null || :
}
sf_probe_start() {
    local binary=$1 config=$2 log=$3 seconds=$4
    shift 4
    binary=$(realpath -- "$binary") || return
    [[ $binary != *:* && $binary != *[[:space:]]* && $config != *:* && $config != *[[:space:]]* ]] || return 2
    SF_PROBE_UNIT="sfxh-probe-$(sf_random).service"
    mkdir -p "$SFXH_RUN/probes" && chmod 700 "$SFXH_RUN/probes" || return
    printf '%s\n' "$binary" > "$SFXH_RUN/probes/$SF_PROBE_UNIT" || return
    local -a options=(--quiet --wait --pipe --collect --service-type=exec --unit "$SF_PROBE_UNIT"
        -p 'Description=SF-Xray-Hop owned temporary probe'
        -p DynamicUser=yes -p NoNewPrivileges=yes -p CapabilityBoundingSet= -p AmbientCapabilities=
        -p ProtectSystem=strict -p ProtectHome=yes -p PrivateTmp=yes -p UMask=0077
        -p "RuntimeMaxSec=${seconds}s" -p TimeoutStopSec=3 -p KillMode=control-group
        -p "BindReadOnlyPaths=$binary:/tmp/sfxh-probe-core")
    if [[ -n $config ]]; then
        options+=(-p "LoadCredential=config.json:$(realpath -- "$config")")
        set -- run -config "/run/credentials/$SF_PROBE_UNIT/config.json"
    fi
    (sf_probe_close_locks; systemd-run "${options[@]}" -- /usr/bin/env /tmp/sfxh-probe-core "$@" 2>&1 | sf_redact > "$log") &
    SF_PROBE_PID=$!
}
sf_probe_tls() (
    local pid='' unit='' result
    trap 'sf_stop_probe "$pid" "$unit"' EXIT
    trap 'exit 130' INT TERM HUP
    sf_probe_start "$1" '' "$3" 20 tls ping "$2" || return
    pid=$SF_PROBE_PID; unit=$SF_PROBE_UNIT
    wait "$pid"; result=$?
    return "$result"
)
sf_probe_profile() (
    sf_probe_close_locks
    local binary=$1 profile=$2 work=$3 result=$4 exit_url=${5:-} port pid='' unit='' url ip='' endpoint='' attempts=0 successes=0 data code http sample family digest
    mkdir -p "$work" || return
    trap 'sf_stop_probe "$pid" "$unit"' EXIT
    trap 'exit 130' INT TERM HUP
    port=$(sf_local_port) || return
    sf_client_config "$profile" "$work/client.json" "$port" && sf_core_test "$binary" "$work/client.json" "$work/config-test.log" || return
    sf_probe_start "$binary" "$work/client.json" "$work/client.log" 150 || return
    pid=$SF_PROBE_PID; unit=$SF_PROBE_UNIT
    sf_wait_port "$port" "$pid" || { sf_fail '本机探测客户端未能启动。'; return 1; }
    data=$(sf_probe_data)
    while IFS= read -r url; do
        ((attempts+=1))
        code=0
        http=$(curl --fail --silent --proxy "http://127.0.0.1:$port" --noproxy '' --connect-timeout 5 --max-time 12 --proto '=https' "$url" -o /dev/null -w '%{http_code}' 2>/dev/null) || code=$?
        if ((code==0)); then successes=1; endpoint=$url; break; fi
        if [[ $http =~ ^[45][0-9][0-9]$ ]]; then sf_msg "HTTPS 检测站返回 HTTP $http；尝试备用站。"; fi
    done < <(jq -r '.https[]' "$data")
    if ((successes==0)); then sf_fail 'HTTPS 未完成：可能为代理连接、目标站或 TLS 失败；不据此断言核心损坏。'; return 1; fi
    if [[ -n $exit_url ]]; then printf '%s\n' "$exit_url" > "$work/exit-urls"; else jq -r '.exit[]' "$data" > "$work/exit-urls"; fi
    : > "$work/exit-samples"
    while IFS= read -r url; do
        [[ $url == https://* ]] || return 2
        for sample in 1 2 3; do
            ip=$(curl --fail --silent --proxy "http://127.0.0.1:$port" --noproxy '' --connect-timeout 5 --max-time 8 --proto '=https' "$url" 2>/dev/null | tr -d '\r\n') || ip=''
            if [[ $ip =~ ^[0-9A-Fa-f.:]+$ ]] && sf_host_valid "$ip"; then printf '%s\n' "${ip,,}" >> "$work/exit-samples"; else break; fi
        done
        [[ ! -s $work/exit-samples ]] || { exit_url=$url; break; }
    done < "$work/exit-urls"
    [[ -s $work/exit-samples ]] || { sf_fail '出口未确认：HTTPS 已通过，但出口查询站未提供可比较的 IP；未提交配置。'; return 1; }
    ip=$(head -n 1 "$work/exit-samples"); family=4; [[ $ip != *:* ]] || family=6
    digest=$(jq -cS . "$profile" | sha256sum | cut -d ' ' -f1) || return
    jq -n --arg ip "$ip" --arg endpoint "$endpoint" --arg exitEndpoint "$exit_url" --arg at "$(sf_now)" --arg digest "$digest" \
       --argjson family "$family" --argjson attempts "$attempts" --rawfile samples "$work/exit-samples" \
       '{status:"pass",scope:"local-client-protocol",observedAt:$at,profileSha256:$digest,https:{successes:1,attempts:$attempts,endpoint:$endpoint},
         exitIp:$ip,exit:{endpoint:$exitEndpoint,family:$family,ips:($samples|split("\n")|map(select(length>0))|unique)}}' > "$result"
)
sf_exit_compare() {
    local expected=$1 actual=$2 output=$3
    jq -n --argjson checkedAt "$(date +%s)" --slurpfile e "$expected" --slurpfile a "$actual" '
      def valid:
        try (type=="object" and (.exit|type)=="object" and
          (.exit.endpoint|type)=="string" and (.exit.endpoint|startswith("https://")) and
          (.exit.family==4 or .exit.family==6) and (.exit.ips|type)=="array" and
          (.exit.ips|length)>0 and all(.exit.ips[]; type=="string" and length>0)) catch false;
      def time: try (.observedAt|fromdateiso8601) catch null;
      ($e[0]|valid) as $ev | ($a[0]|valid) as $av |
      ($e[0]|time) as $et | ($a[0]|time) as $at |
      $e[0].exit as $e | $a[0].exit as $a |
      (if $ev and $av then ($a.ips-$e.ips|unique) else [] end) as $unknown |
      (if ($ev and $av)|not then "invalid-samples"
        elif $a.endpoint!=$e.endpoint or $a.family!=$e.family then "different-endpoint-or-family"
        elif $et==null or $at==null then "missing-sample-time"
        elif $checkedAt-$et>600 or $checkedAt-$at>600 or $et-$checkedAt>30 or $at-$checkedAt>30 then "stale-samples"
        elif ($at-$et|fabs)>300 then "stale-samples"
        elif ($unknown|length)==0 then "all-observed-expected"
        elif ($a.ips-$unknown|length)==0 then "no-common-address"
        else "unexpected-address" end) as $reason |
      {status:(if $reason=="all-observed-expected" then "confirmed"
        elif $reason=="no-common-address" then "mismatch" else "unconfirmed" end),
       reason:$reason,unexpected:$unknown,expected:$e,observed:$a,
       scope:"同检测站、同地址族、有限时间窗内的全部观测样本；不证明全流量无泄漏"}' > "$output" || return
    jq -e '.status=="confirmed"' "$output" >/dev/null || {
        sf_fail '出口未确认：完整中转路径与独立基准不符或无法比较；可能为错误路由、动态出口或检测站问题，停止提交。'; return 1;
    }
}
sf_probe_state() (
    sf_probe_close_locks
    local state=$1 binary=$2 address=$3 port=$4 work=$5 output=$6 which expected='' endpoint='' digest
    mkdir -p "$work" || return
    if jq -e '.nextHop!=null' "$state" >/dev/null; then
        jq .nextHop "$state" > "$work/next-hop.json" || return
        digest=$(jq -cS . "$work/next-hop.json" | sha256sum | cut -d ' ' -f1) || return
        expected=$work/next-hop-result.json
        if [[ -f ${SF_EXPECT_EXIT_RESULT:-} ]] && jq -e --arg hash "$digest" '.profileSha256==$hash and .status=="pass"' "$SF_EXPECT_EXIT_RESULT" >/dev/null; then
            cp "$SF_EXPECT_EXIT_RESULT" "$expected" || return
        else
            sf_msg '正在独立测量下游出口基准……'
            sf_probe_profile "$binary" "$work/next-hop.json" "$work/next-hop" "$expected" || return
        fi
        endpoint=$(jq -r .exit.endpoint "$expected")
    fi
    for which in direct relay; do
        sf_msg "正在测试$(if [[ $which == direct ]]; then printf '本机直连'; else printf '中转线路'; fi)的握手、HTTPS 和出口……"
        sf_profile "$state" "$which" | jq --arg host "$address" --argjson port "$port" '.address=$host|.port=$port' > "$work/$which.json" || return
        sf_probe_profile "$binary" "$work/$which.json" "$work/$which" "$work/$which-result.json" "$endpoint" || return
        if [[ $which == direct && -z $expected ]]; then expected=$work/direct-result.json; endpoint=$(jq -r .exit.endpoint "$expected"); fi
    done
    sf_exit_compare "$expected" "$work/relay-result.json" "$work/exit-verification.json" || return
    jq -n --slurpfile direct "$work/direct-result.json" --slurpfile relay "$work/relay-result.json" --slurpfile verification "$work/exit-verification.json" --arg at "$(sf_now)" \
      '{checkedAt:$at,scope:"本机协议探测；公网设备尚未验证",direct:$direct[0],relay:$relay[0],exitVerification:$verification[0]}' > "$output"
)
sf_probe_candidate() (
    sf_probe_close_locks
    local state=$1 server_binary=$2 client_binary=$3 work=$4 pid='' unit='' port
    mkdir -p "$work" || return
    trap 'sf_stop_probe "$pid" "$unit"' EXIT
    trap 'exit 130' INT TERM HUP
    port=$(sf_local_port) || return
    sf_render "$state" "$work/original.json" || return
    jq --argjson port "$port" '.inbounds[0].listen="127.0.0.1"|.inbounds[0].port=$port' "$work/original.json" > "$work/server.json" || return
    sf_core_test "$server_binary" "$work/server.json" "$work/server-test.log" || return
    sf_probe_start "$server_binary" "$work/server.json" "$work/server.log" 480 || return
    pid=$SF_PROBE_PID; unit=$SF_PROBE_UNIT
    sf_wait_port "$port" "$pid" || { sf_fail '候选核心实际启动失败。'; return 1; }
    sf_probe_state "$state" "$client_binary" 127.0.0.1 "$port" "$work/clients" "$work/result.json"
)
sf_health_current() (
    sf_probe_close_locks
    local state binary work generation
    state=$(sf_state) || return
    binary=$(sf_current_core) || return
    generation=$(basename "$(dirname "$state")")
    work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"' EXIT
    if sf_probe_state "$state" "$binary" 127.0.0.1 "$(jq -r .node.port "$state")" "$work" "$work/health.json"; then
        jq --arg generation "$generation" '.generation=$generation' "$work/health.json" > "$work/dated.json"
        sf_atomic_json "$SFXH_VAR/cache/health.json" "$work/dated.json" || return
        sf_msg "本机直连出口：$(jq -r .direct.exitIp "$work/health.json")"
        sf_msg "中转线路出口：$(jq -r .relay.exitIp "$work/health.json")"
        sf_msg '本机协议检测通过；请再从手机／电脑验证公网接入。'
    else
        jq -n --arg at "$(sf_now)" --arg generation "$generation" '{checkedAt:$at,generation:$generation,status:"failed"}' > "$work/failure.json"
        sf_atomic_json "$SFXH_VAR/cache/health.json" "$work/failure.json"
        return 1
    fi
)
sf_chain_test() (
    local state binary work
    state=$(sf_state) || return; binary=$(sf_current_core) || return
    jq -e '.nextHop!=null' "$state" >/dev/null || { sf_fail '尚未设置出口。'; return 1; }
    work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"' EXIT
    jq .nextHop "$state" > "$work/profile.json"
    sf_probe_profile "$binary" "$work/profile.json" "$work/probe" "$work/result.json" || return
    sf_msg "下游代理与 HTTPS 通过，观察出口：$(jq -r .exitIp "$work/result.json")"
    sf_network_metrics "$(jq -r .address "$work/profile.json")" "$(jq -r .port "$work/profile.json")" "$work"
)
sf_network_metrics() {
    local host=$1 port=$2 work=$3 start end time=null ip line loss=null rtt_min=null rtt_mean=null rtt_max=null rtt_mdev=null
    ip=$(timeout 5 getent ahosts "$host" | awk 'NR==1{print $1}') || ip=''
    if [[ -z $ip ]]; then
        sf_msg 'TCP 耗时／ICMP：—（DNS 未完成）'
        printf '{"tcpConnectMs":null,"icmp":null}\n' > "$work/network.json"
        return 0
    fi
    start=$EPOCHREALTIME
    if timeout 5 bash -c 'exec 3<>/dev/tcp/"$1"/"$2"' bash "$ip" "$port" 2>/dev/null; then
        end=$EPOCHREALTIME
        time=$(awk -v start="$start" -v end="$end" 'BEGIN{printf "%.2f",(end-start)*1000}')
        sf_msg "TCP 连接耗时：$time ms（不含 DNS，含本机探测开销）"
    else sf_msg 'TCP 连接：失败'; fi
    LC_ALL=C timeout 12 ping -n -c 5 -W 1 "$ip" > "$work/ping.txt" 2>&1 || :
    if grep -Eq ', [1-5] received' "$work/ping.txt"; then
        loss=$(sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p' "$work/ping.txt")
        line=$(sed -nE 's/.* = ([0-9.]+\/[0-9.]+\/[0-9.]+\/[0-9.]+) ms.*/\1/p' "$work/ping.txt")
        IFS=/ read -r rtt_min rtt_mean rtt_max rtt_mdev <<< "$line"
        sf_msg "ICMP RTT：平均 $rtt_mean ms，最小 $rtt_min ms，最大 $rtt_max ms"
        sf_msg "ICMP 抖动（mdev）：$rtt_mdev ms；5次样本丢包：$loss%（不是 HTTPS 失败率）"
    else sf_msg 'ICMP RTT／抖动／丢包：—（未获应答，无法区分禁止 ICMP 与丢包）'; fi
    jq -n --arg at "$(sf_now)" --argjson tcp "$time" --argjson loss "${loss:-null}" \
      --argjson min "${rtt_min:-null}" --argjson mean "${rtt_mean:-null}" --argjson max "${rtt_max:-null}" --argjson jitter "${rtt_mdev:-null}" \
      '{checkedAt:$at,tcpConnectMs:$tcp,icmp:{sampleCount:5,lossPercent:$loss,minMs:$min,meanMs:$mean,maxMs:$max,mdevMs:$jitter}}' > "$work/network.json"
}
sf_doctor() (
    local state binary work fail=0
    sf_platform_check || return
    state=$(sf_state) || return; binary=$(sf_current_core) || return
    work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"' EXIT
    sf_validate_state "$state" && sf_generation_integrity "$(dirname "$state")" && sf_core_verify_archive "$(jq -r .core.id "$state")" || return
    sf_core_security "$binary" || return
    sf_core_test "$binary" "$(dirname "$state")/config.json" "$work/config-test.log" || return
    systemctl is-active --quiet xray.service || { sf_msg '失败：xray.service 未运行'; fail=1; }
    [[ -n $(ss -H -ltn "sport = :$(jq -r .node.port "$state")") ]] || { sf_msg '失败：未检测到监听'; fail=1; }
    sf_target_check "$binary" "$(jq -r .reality.serverName "$state")" "$work" || fail=1
    sf_health_current || fail=1
    if jq -e '.nextHop!=null' "$state" >/dev/null; then sf_chain_test || fail=1; fi
    sf_firewall_note
    if ((fail)); then sf_fail '诊断存在未通过项。'; else sf_msg '本机诊断通过；公网设备接入仍需独立验证。'; fi
    return "$fail"
)
