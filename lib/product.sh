#!/usr/bin/env bash
# Display metadata never participates in Xray routing or authentication.
sf_running_core_version() {
    local main pid exe version
    main=$(systemctl show xray.service -p MainPID --value 2>/dev/null) || return
    [[ $main =~ ^[1-9][0-9]*$ && -r /proc/$main/task/$main/children ]] || return 1
    for pid in "$main" $(cat "/proc/$main/task/$main/children"); do
        exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
        [[ $exe == "$SFXH_VAR/cores/"*/xray || $exe == "$SFXH_VAR/cores/"*'/xray (deleted)' ]] || continue
        # Read the entire small version response. Under pipefail, head can close
        # the pipe before Xray writes its second line and turn success into 141.
        version=$(timeout 2 "/proc/$pid/exe" version 2>/dev/null) || continue
        version=${version%%$'\n'*}
        if [[ $version =~ ^Xray[[:space:]]([0-9]+\.[0-9]+\.[0-9]+) ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; return 0; fi
    done
    return 1
}
sf_role() {
    if jq -e '.schemaVersion==1 and .nextHop==null' "$1" >/dev/null &&
       [[ -f $SFXH_ETC/guide.json ]] && jq -e '.position=="exit" and .stage=="ready"' "$SFXH_ETC/guide.json" >/dev/null; then
        printf 'exit\n'
    else sf_jq -r 'include "model"; node_role' "$1"; fi
}
sf_role_label() {
    case "$1" in entry) printf '入口 A' ;; exit) printf '出口 B（入口连接状态未知）' ;; *) printf '单机' ;; esac
}
sf_import_name() {
    local name
    name=$(jq -r '(.nextHop // .)|(.remark // "")|sub("^(直连|链式|对接) \\| ";"")|sub(" · (本机直连|中转线路)$";"")' "$1") || return
    if sf_safe_name "$name"; then printf '%s\n' "$name"; else printf '下游节点\n'; fi
}
sf_normalize_state() {
    local input=$1 output=$2 old_role=standalone name
    if [[ -f $SFXH_ETC/guide.json ]] && jq -e '.position=="exit" and .stage=="ready"' "$SFXH_ETC/guide.json" >/dev/null 2>&1; then old_role='exit'; fi
    name=$(sf_import_name "$input") || return
    jq --arg role "$old_role" --arg name "$name" '
      if .schemaVersion==1 then .schemaVersion=2 | .presentation={
        role:(if .nextHop!=null then "entry" else $role end),
        downstreamName:(if .nextHop!=null then $name else null end),
        downstreamNameSource:(if .nextHop!=null then "imported" else null end),entry:null}
      else . end' "$input" > "$output"
}
sf_confirm() {
    local text=$1 answer
    sf_tty || { sf_usage_error '该操作需要明确确认；非交互调用请传入 --yes。'; return 2; }
    sf_msg "$text"
    printf '输入 yes 确认，回车取消：' >&2
    IFS= read -r answer || return 130
    [[ $answer == yes ]] || return 130
}
sf_set_role() (
    local role=$1 confirmed=${2:-} intent=metadata
    [[ $role == standalone || $role == exit ]] || { sf_usage_error '入口角色在成功配置下游后自动建立。'; return 2; }
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"; sf_unlock' EXIT
    if jq -e '.nextHop!=null' "$SF_EDIT_STATE" >/dev/null; then intent=runtime; fi
    if jq -e '.nextHop!=null' "$SF_EDIT_STATE" >/dev/null && [[ $confirmed != --yes ]]; then
        sf_confirm '改变用途将移除本机下游；已有链式身份将恢复从本机出口。远端和设备中的副本不会删除。' || return
    fi
    jq --arg role "$role" '.nextHop=null|.presentation.role=$role|.presentation.downstreamName=null|.presentation.downstreamNameSource=null' "$SF_EDIT_STATE" > "$SF_EDIT_WORK/state.json" &&
      sf_tx_apply "$SF_EDIT_WORK/state.json" '改变节点用途' online "$intent"
)
sf_set_entry() (
    local address=${1:-} name=${2:-}
    [[ -z $address ]] || sf_host_valid "$address" || { sf_usage_error '入口地址应为 IP 或域名，不包含协议及端口。'; return 2; }
    [[ -z $name ]] || sf_safe_name "$name" || return 2
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"; sf_unlock' EXIT
    [[ $(sf_role "$SF_EDIT_STATE") == exit ]] || { sf_usage_error '入口登记只用于出口节点。'; return 2; }
    jq --arg address "$address" --arg name "$name" '.presentation.entry=(if $address=="" then null else
      {address:$address,name:(if $name=="" then null else $name end),source:"user"} end)' "$SF_EDIT_STATE" > "$SF_EDIT_WORK/state.json" &&
      sf_tx_apply "$SF_EDIT_WORK/state.json" '更新用户登记的入口信息' online metadata
)
sf_set_downstream_name() (
    local name=$1
    sf_safe_name "$name" || { sf_usage_error '名称应为1–80字且不超过240字节，不得含控制或不可见字符。'; return 2; }
    sf_edit_begin || return
    trap 'sf_remove_tree "$SF_EDIT_WORK"; sf_unlock' EXIT
    jq -e '.nextHop!=null' "$SF_EDIT_STATE" >/dev/null || return 2
    jq --arg name "$name" '.presentation.downstreamName=$name|.presentation.downstreamNameSource="local"' "$SF_EDIT_STATE" > "$SF_EDIT_WORK/state.json" &&
      sf_tx_apply "$SF_EDIT_WORK/state.json" '更新本地下游别名' online metadata
)
