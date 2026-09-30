#!/usr/bin/env bash
sf_uri_encode() {
    sf_jq -er 'include "model"; select(valid_profile) |
      "vless://" + .id + "@" + (if (.address|contains(":")) then "["+.address+"]" else .address end) + ":"+(.port|tostring) + "?" +
      (["encryption="+(.encryption|@uri),"flow="+(.flow|@uri),"type=xhttp","security=reality",
        "sni="+(.serverName|@uri),"fp="+.fingerprint,"pbk="+(.password|@uri),"sid="+.shortId,
        "path="+(.path|@uri),"mode=auto"]|join("&")) + "#"+(.remark|@uri)' "$1"
}
sf_uri_decode_component() {
    local LC_ALL=C input=$1 result='' chunk hex i=0
    while ((i<${#input})); do
        chunk=${input:i:1}
        if [[ $chunk == '%' ]]; then
            hex=${input:i+1:2}
            [[ ${#hex} == 2 && $hex =~ ^[[:xdigit:]]{2}$ ]] || return 1
            ((16#$hex >= 32 && 16#$hex != 127)) || return 1
            printf -v chunk '%b' "\\x$hex"
            ((i+=3))
        else
            [[ ! $chunk =~ [[:cntrl:]] ]] || return 1
            ((i+=1))
        fi
        result+=$chunk
    done
    printf '%s' "$result" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || return 1
    SF_DECODED=$result
}
sf_uri_parse() {
    local file=$1 out=$2 uri authority query fragment='' id hostport host port pair key value
    local -A fields=()
    [[ $(wc -c < "$file") -le 65536 ]] || { sf_fail '链接超过允许长度。'; return 2; }
    IFS= read -r uri < "$file" || [[ -n $uri ]] || return 2
    uri=${uri%$'\r'}
    [[ $(awk 'END {print NR}' "$file") -le 1 && $uri != *[[:space:]]* && $uri == vless://* ]] || { sf_fail '请提供单行标准 VLESS 链接。'; return 2; }
    if [[ $uri == *'#'* ]]; then fragment=${uri#*#}; uri=${uri%%#*}; fi
    [[ $uri == *'?'* ]] || { sf_fail '链接缺少协议参数。'; return 2; }
    authority=${uri#vless://}; query=${authority#*\?}; authority=${authority%%\?*}
    [[ $authority == *@* ]] || return 2
    id=${authority%%@*}; hostport=${authority#*@}
    if [[ $hostport == \[* ]]; then
        [[ $hostport =~ ^\[([^]]+)\]:([0-9]+)$ ]] || return 2
        host=${BASH_REMATCH[1]}; port=${BASH_REMATCH[2]}
    else
        [[ $hostport =~ ^([^:]+):([0-9]+)$ ]] || return 2
        host=${BASH_REMATCH[1]}; port=${BASH_REMATCH[2]}
    fi
    sf_host_valid "$host" && [[ ${#port} -le 5 ]] && ((10#$port>0 && 10#$port<=65535)) || { sf_fail '链接地址或端口不合法。'; return 2; }
    local -a pairs
    IFS='&' read -r -a pairs <<< "$query"
    [[ $query != *'&' ]] || return 2
    for pair in "${pairs[@]}"; do
        [[ $pair == *=* ]] || return 2
        sf_uri_decode_component "${pair%%=*}" || return 2; key=$SF_DECODED
        case "$key" in encryption|flow|type|security|sni|fp|pbk|sid|path|mode) ;; *) sf_fail '链接包含本版本未支持的参数。'; return 2 ;; esac
        [[ ! -v fields[$key] ]] || { sf_fail '链接含有重复参数。'; return 2; }
        sf_uri_decode_component "${pair#*=}" || { sf_fail '链接编码无效。'; return 2; }; fields[$key]=$SF_DECODED
    done
    for key in encryption flow type security sni fp pbk sid path mode; do
        [[ -v fields[$key] ]] || { sf_fail "链接缺少 $key。"; return 2; }
    done
    sf_uri_decode_component "$fragment" || return 2; fragment=$SF_DECODED
    sf_domain "${fields[sni]}" || { sf_fail 'REALITY SNI 必须是有效域名。'; return 2; }
    printf '%s\0' "$host" "$((10#$port))" "$id" "${fields[encryption]}" "${fields[flow]}" "${fields[type]}" "${fields[security]}" "${fields[sni]}" "${fields[fp]}" "${fields[pbk]}" "${fields[sid]}" "${fields[path]}" "${fields[mode]}" "$fragment" |
      jq -Rs 'split("\u0000") | {address:.[0],port:(.[1]|tonumber),id:.[2],encryption:.[3],flow:.[4],network:.[5],security:.[6],serverName:.[7],fingerprint:.[8],password:.[9],shortId:.[10],path:.[11],mode:.[12],remark:.[13]}' > "$out" || return
    sf_jq -e 'include "model"; valid_profile' "$out" >/dev/null 2>&1 || { sf_fail '链接协议组合不符合 SF-Xray-Hop v1 基线。'; return 2; }
}
sf_read_uri() {
    local dest=$1 line
    if sf_tty; then
        sf_msg '请粘贴出口机的中转专用链接（隐藏输入，输入0返回）：'
        IFS= read -rs line || return 1; sf_msg ''
        [[ $line != 0 ]] || return 130
        printf '%s\n' "$line" > "$dest"
    else
        # Never pass credentials through argv or shell history.
        head -c 65538 > "$dest"
        [[ -s $dest ]] || { sf_usage_error '请通过标准输入提供单行 VLESS 链接。'; return 2; }
    fi
    chmod 600 "$dest"
}
sf_view() (
    sf_root || return
    local state mode=${1:-direct} which=${2:-direct} temp role
    state=$(sf_state) || return
    role=$(sf_role "$state") || return
    if [[ $mode == relay || $mode == chain || ($mode == json && $which == relay) ]]; then
        case "$role" in
            standalone) sf_msg '链式尚未启用；运行 sfxh guide，或主菜单选择1。'; return 2 ;;
            exit)
                sf_msg '本机是出口 B；设备链式链接应在入口 A 上查看。对接链接请进入链式引导。'
                if jq -e '.presentation.entry!=null' "$state" >/dev/null; then
                    sf_msg "你登记的入口：$(jq -r '.presentation.entry.address' "$state")（用户登记，未证明已连接）"
                else sf_msg '尚未登记入口地址；本机无法生成另一台机器的设备链接。'; fi
                return 2 ;;
        esac
    fi
    if [[ $mode == handoff && $role != exit ]]; then sf_fail '对接链接只在明确设为出口后提供。'; return 2; fi
    [[ $mode != chain && $mode != handoff ]] || mode=relay
    temp=$(sf_temp) || return
    trap 'sf_remove_tree "$temp"' EXIT
    if [[ $mode == json ]]; then
        [[ $which == direct || $which == relay ]] || return 2
        sf_profile "$state" "$which" > "$temp/profile.json" && sf_client_config "$temp/profile.json" "$temp/client.json" && cat "$temp/client.json"
        return $?
    fi
    [[ $mode == direct || $mode == relay ]] || return 2
    for which in direct relay; do
        [[ $mode == all || $mode == "$which" ]] || continue
        if [[ $which == direct ]]; then sf_msg '本机直连链接（直接从本机出口／应急使用）'
        elif jq -e '.nextHop!=null' "$state" >/dev/null; then sf_msg '双机连接链接（供手机／电脑日常使用）'
        else sf_msg '中转专用链接（交给入口机；当前从本机出口）'; fi
        sf_profile "$state" "$which" > "$temp/profile.json" && sf_uri_encode "$temp/profile.json" || return
    done
)
