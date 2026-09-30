#!/usr/bin/env bash
sf_validate_state() {
    sf_jq -e 'include "model"; valid_state' "$1" >/dev/null 2>&1 || { sf_fail '状态结构或参数不受支持。'; return 1; }
    sf_host_valid "$(jq -r .node.address "$1")" || { sf_fail '本机地址格式无效。'; return 1; }
    if jq -e '.presentation.entry!=null' "$1" >/dev/null; then sf_host_valid "$(jq -r .presentation.entry.address "$1")" || { sf_fail '登记的入口地址格式无效。'; return 1; }; fi
}
sf_render() { sf_jq 'include "model"; server_config(.)' "$1" > "$2"; }
sf_profile() { sf_jq --arg which "$2" 'include "model"; public_profile(.;$which)' "$1"; }
sf_client_config() { sf_jq --argjson port "${3:-10809}" 'include "model"; client_config(.;$port)' "$1" > "$2"; }
sf_rtt_values() {
    local input=$1 mode=$2 output=$3
    [[ $mode == 0 || $mode == 1 ]] || return 2
    jq -e '(.encryption.encryption|split(".")) as $e | (.encryption.generatorDecryption|split(".")) as $d |
      ($e|length)==4 and ($d|length)==4 and $e[0]==$d[0] and $e[1]==$d[1] and
      ($e[2]=="0rtt" or $e[2]=="1rtt") and ($d[2]|test("^[1-9][0-9]*(-[1-9][0-9]*)?s$"))' "$input" >/dev/null || {
        sf_fail 'RTT 参数格式未知，保留原参数并停止。'; return 1;
    }
    jq --arg mode "$mode" '
      .encryption.rtt=$mode |
      .encryption.encryption |= (split(".") | .[2]=(if $mode=="0" then "0rtt" else "1rtt" end) | join(".")) |
      .encryption.decryption = (.encryption.generatorDecryption | split(".") | .[2]=(if $mode=="0" then .[2] else "0s" end) | join("."))
    ' "$input" > "$output"
}
sf_next_rtt_values() {
    local input=$1 mode=$2 output=$3
    [[ $mode == 0 || $mode == 1 ]] || return 2
    jq -e '.nextHop.encryption|split(".")|length==4 and
      (.[0]|test("^[A-Za-z0-9-]+$")) and (.[1]=="native" or .[1]=="xorpub" or .[1]=="random") and
      (.[2]=="0rtt" or .[2]=="1rtt") and (.[3]|test("^[A-Za-z0-9_-]{1579}$"))' "$input" >/dev/null 2>&1 || {
        sf_fail '下游 Encryption 格式未知，未修改。'; return 1;
    }
    jq --arg mode "$mode" '.nextHop.encryption|=(split(".")|.[2]=($mode+"rtt")|join("."))' "$input" > "$output"
}
