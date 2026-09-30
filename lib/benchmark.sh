#!/usr/bin/env bash
sf_bench_bytes() {
    local direction=$1 rate=$2 data=$3 bytes limit
    [[ $direction == download || $direction == upload ]] || return 2
    [[ $rate == 100 || $rate == 150 || $rate == 200 ]] || return 2
    bytes=$((rate * 1000000 / 8 * 6))
    if [[ $direction == download ]]; then
        limit=$(jq -er '.performance.downloadMaxBytes | select(type=="number" and floor==. and .>0 and .<=150000000)' "$data") || {
            sf_fail '测速端点下载上限无效，未发起压力请求。'; return 2;
        }
        ((bytes<=limit)) || bytes=$limit
    fi
    printf '%s\n' "$bytes"
}
sf_bench_notice() {
    local data total=0 bytes rate direction megabytes
    data=$(sf_probe_data) || return
    for rate in 100 150 200; do
        for direction in download upload; do
            bytes=$(sf_bench_bytes "$direction" "$rate" "$data") || return
            total=$((total+bytes))
        done
    done
    megabytes=$(LC_ALL=C awk -v total="$total" 'BEGIN{printf "%.1f",total/1000000}') || return
    sf_msg "本机自检负载：100／150／200 Mbps；每级每方向最多8秒；下载按端点上限裁剪，当前六阶段正常载荷约${megabytes} MB，超时限速预算约900 MB，协议和转发开销另计。"
    sf_msg '额外客户端也消耗本机CPU；正式容量应由独立设备测试。本次分开记录正式服务、整机CPU与steal。'
}
sf_bench_transfer() {
    local direction=$1 proxy=$2 url=$3 bytes=$4 rate=$5 work=$6 rc=0 length type received
    local -a options=(--fail --silent --proxy "$proxy" --noproxy '' --connect-timeout 3 --max-time 8 --limit-rate "$rate" --proto '=https' -o /dev/null -D "$work/headers")
    if [[ $direction == download ]]; then
        curl "${options[@]}" --max-filesize "$bytes" -w '{"bytes":%{size_download},"seconds":%{time_total},"http":"%{http_code}"}\n' "$url?bytes=$bytes" > "$work/raw.json" || rc=$?
    else
        head -c "$bytes" /dev/zero | curl "${options[@]}" -X POST --upload-file - -H "Content-Length: $bytes" -H 'Transfer-Encoding:' -H 'Content-Type: application/octet-stream' -w '{"bytes":%{size_upload},"seconds":%{time_total},"http":"%{http_code}"}\n' "$url" > "$work/raw.json" || rc=$?
    fi
    length=$(awk 'tolower($1)=="content-length:"{v=$2}END{gsub("\r","",v);print v}' "$work/headers")
    type=$(awk 'tolower($1)=="content-type:"{v=$2}END{gsub("\r","",v);print tolower(v)}' "$work/headers")
    received=$(awk 'tolower($1)=="cf-meta-upload-bytes:"{v=$2}END{gsub("\r","",v);print v}' "$work/headers")
    [[ $length =~ ^[0-9]+$ ]] || length=null
    [[ $received =~ ^[0-9]+$ ]] || received=null
    jq --arg type "$type" --argjson length "$length" --argjson received "$received" '.+{contentType:$type,contentLength:$length,serverReceivedBytes:$received}' "$work/raw.json"
    return "$rc"
}
sf_bench_snapshot() {
    local total busy steal wall used available group main usage=null rss=null member value sum=0 seen=0
    read -r total busy steal < <(awk '/^cpu /{s=0;for(i=2;i<=9;i++)s+=$i;print s,s-$5-$6-$9,$9}' /proc/stat)
    wall=$(awk '{printf "%.0f",$1*1000000}' /proc/uptime)
    read -r used available < <(awk '/MemTotal:/{t=$2}/MemAvailable:/{a=$2}END{print t-a,a}' /proc/meminfo)
    group=$(systemctl show xray.service --property=ControlGroup --value 2>/dev/null) || group=''
    main=$(systemctl show xray.service --property=MainPID --value 2>/dev/null) || main=0
    if [[ $group == /* && $group != *..* && -r /sys/fs/cgroup$group/cpu.stat ]]; then
        usage=$(awk '$1=="usage_usec"{print $2}' "/sys/fs/cgroup$group/cpu.stat")
        while read -r member; do
            value=$(awk '/^VmRSS:/{print $2}' "/proc/$member/status" 2>/dev/null) || value=''
            if [[ $value =~ ^[0-9]+$ ]]; then ((sum+=value)); seen=1; fi
        done < "/sys/fs/cgroup$group/cgroup.procs"
        ((seen==0)) || rss=$sum
    fi
    [[ $usage =~ ^[0-9]+$ ]] || usage=null
    [[ $main =~ ^[0-9]+$ ]] || main=0
    jq -n --argjson wall "$wall" --argjson total "$total" --argjson busy "$busy" --argjson steal "$steal" --argjson usage "$usage" --argjson rss "$rss" \
       --argjson main "$main" --argjson used "$used" --argjson available "$available" \
       '{wallUs:$wall,hostTotal:$total,hostBusy:$busy,hostSteal:$steal,serviceCpuUs:$usage,serviceRssKiB:$rss,servicePid:$main,hostUsedRamKiB:$used,availableRamKiB:$available}'
}
sf_benchmark() (
    local which=${1:-relay} state binary work port pid='' unit='' transfer='' rate direction bytes rc data url stage generation
    [[ $which == direct || $which == relay ]] || return 2
    sf_platform_check || return
    state=$(sf_state) || return; binary=$(sf_current_core) || return
    work=$(sf_temp) || return
    sf_bench_cleanup() {
        [[ -z $transfer ]] || { kill -- "-$transfer" 2>/dev/null || :; wait "$transfer" 2>/dev/null || :; }
        sf_stop_probe "$pid" "$unit"; sf_remove_tree "$work"
    }
    trap sf_bench_cleanup EXIT
    trap 'exit 130' INT TERM HUP
    sf_bench_notice || return
    if [[ $which == relay ]] && jq -e '.nextHop!=null' "$state" >/dev/null; then
        sf_network_metrics "$(jq -r .nextHop.address "$state")" "$(jq -r .nextHop.port "$state")" "$work" || return
    else printf 'null\n' > "$work/network.json"; fi
    sf_profile "$state" "$which" | jq --argjson port "$(jq -r .node.port "$state")" '.address="127.0.0.1"|.port=$port' > "$work/profile.json" || return
    sf_probe_profile "$binary" "$work/profile.json" "$work/preflight" "$work/preflight.json" || return
    port=$(sf_local_port) || return
    sf_client_config "$work/profile.json" "$work/client.json" "$port" || return
    sf_probe_start "$binary" "$work/client.json" "$work/client.log" 100 || return
    pid=$SF_PROBE_PID; unit=$SF_PROBE_UNIT
    sf_wait_port "$port" "$pid" || return
    export -f sf_bench_transfer
    data=$(sf_probe_data)
    : > "$work/results.jsonl"
    for rate in 100 150 200; do
        for direction in download upload; do
            sf_msg "正在测试$(if [[ $direction == download ]]; then printf '下载'; else printf '上传'; fi)，目标上限 $rate Mbps……"
            url=$(jq -r --arg key "$direction" '.performance[$key]' "$data")
            [[ $url == https://* ]] || return 2
            bytes=$(sf_bench_bytes "$direction" "$rate" "$data") || return
            stage=$work/$direction-$rate
            mkdir "$stage" || return
            sf_bench_snapshot > "$stage/resources.jsonl" || return
            setsid bash -c 'sf_bench_transfer "$@"' bash "$direction" "http://127.0.0.1:$port" "$url" "$bytes" "$((rate*1000000/8))" "$stage" > "$work/transfer.json" 2>/dev/null & transfer=$!
            while kill -0 "$transfer" 2>/dev/null; do
                sf_bench_snapshot > "$stage/latest.json" || return
                cat "$stage/latest.json" >> "$stage/resources.jsonl"
                if jq -e '.availableRamKiB<65536' "$stage/latest.json" >/dev/null; then sf_fail '可用内存低于64 MiB，停止压力测试。'; return 1; fi
                sleep 1
            done
            rc=0; wait "$transfer" || rc=$?; transfer=''
            sf_bench_snapshot >> "$stage/resources.jsonl" || return
            jq -L "$SFXH_CODE/templates" -s 'include "benchmark";resource_summary' "$stage/resources.jsonl" > "$stage/resource-summary.json" || return
            if ! jq -e '.bytes>=0 and .seconds>0' "$work/transfer.json" >/dev/null 2>&1; then printf '{"bytes":0,"seconds":0,"http":0}\n' > "$work/transfer.json"; fi
            jq -L "$SFXH_CODE/templates" --arg direction "$direction" --argjson target "$rate" --argjson requested "$bytes" --argjson rc "$rc" --slurpfile resources "$stage/resource-summary.json" \
              'include "benchmark";transfer_result($direction;$target;$requested;$rc)|.+{resources:$resources[0]}' "$work/transfer.json" >> "$work/results.jsonl" || return
        done
    done
    jq -s --slurpfile network "$work/network.json" --arg profile "$which" --arg at "$(sf_now)" \
      '{checkedAt:$at,profile:$profile,scope:"本机自检负载，不能作为正式容量验收；吞吐时间包含建连",nextHopNetwork:$network[0],samples:.}' "$work/results.jsonl" > "$work/benchmark.json" || return
    sf_atomic_json "$SFXH_VAR/cache/benchmark.json" "$work/benchmark.json" || return
    jq -r '.samples[]|"\(if .direction=="download" then "下载" else "上传" end) 限速 \(.targetMbps) Mbps / 观测 \(.throughputMbps // "—") Mbps / \(if .status=="complete" then "约定字节完成" elif .status=="time-limit" then "达到时限，有效部分传输" elif .status=="time-limit-unconfirmed" then "达到时限，仅客户端送出量，服务端未确认" elif .status=="endpoint-contract-invalid" then "端点响应不符合测速约定" else "传输失败" end)\n  正式服务CPU均值/峰值 \(.resources.serviceCpuAveragePercent // "—")/\(.resources.serviceCpuPeakPercent // "—")%；整机CPU \(.resources.hostCpuAveragePercent // "—")/\(.resources.hostCpuPeakPercent // "—")%；steal \(.resources.stealAveragePercent // "—")/\(.resources.stealPeakPercent // "—")%；服务RSS均值/峰值 \(.resources.serviceRssAverageKiB // "—")/\(.resources.serviceRssPeakKiB // "—") KiB"' "$work/benchmark.json" >&2
    sf_msg '高负载也可能来自本机模拟客户端或宿主机争用；是否升级需外部设备持续测试确认。'
    jq -e 'all(.samples[];.validMeasurement)' "$work/benchmark.json" >/dev/null
)
