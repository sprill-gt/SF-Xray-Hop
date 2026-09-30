#!/usr/bin/env bash
SFXH_VERSION=0.2.2
SFXH_BASELINE=26.9.9
sf_paths() {
    local prefix=''
    if [[ ${SFXH_TEST_MODE:-0} == 1 ]]; then prefix=${SFXH_TEST_ROOT:?test root required}; fi
    SFXH_ETC=$prefix/etc/sf-xray-hop
    SFXH_VAR=$prefix/var/lib/sf-xray-hop
    SFXH_LOG=$prefix/var/log/sf-xray-hop
    SFXH_RUN=$prefix/run/sf-xray-hop
    SFXH_LOCK=$prefix/run/lock/sf-xray-hop.lock
    SFXH_UNIT=$prefix/etc/systemd/system/xray.service
    SFXH_INSTALL=$prefix/usr/local/lib/sf-xray-hop
    SFXH_BIN=$prefix/usr/local/bin
    export SFXH_ETC SFXH_VAR SFXH_LOG SFXH_RUN
}
sf_msg() { printf '%s\n' "$*" >&2; }
sf_fail() { sf_msg "错误：$*"; return 1; }
sf_usage_error() { sf_msg "输入错误：$*"; return 2; }
sf_tty() { [[ -t 0 && -t 2 ]]; }
sf_root() { [[ ${SFXH_TEST_MODE:-0} == 1 || $EUID == 0 ]] || { sf_fail '请使用 sudo 运行。'; return 2; }; }
sf_now() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
sf_random() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n'; }
sf_hash() { sha256sum -- "$1" | cut -d ' ' -f 1; }
sf_jq() { jq -L "$SFXH_CODE/templates" "$@"; }
sf_redact() {
    LC_ALL=C sed -E \
        -e 's|vless://[^[:space:]]+|[链接已隐藏]|g' \
        -e 's/[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}/[身份已隐藏]/g' \
        -e 's/[A-Za-z0-9_+=\/-]{32,}/[敏感值已隐藏]/g' \
        -e 's/[[:cntrl:]]//g'
}
sf_event() {
    [[ -d $SFXH_LOG/manager ]] || return 0
    local file=$SFXH_LOG/manager/manager.log
    if [[ -f $file ]] && (( $(wc -c < "$file") > 1048576 )); then
        mv -f -- "$file.2" "$file.3" 2>/dev/null || :
        mv -f -- "$file.1" "$file.2" 2>/dev/null || :
        mv -f -- "$file" "$file.1" || return
    fi
    printf '%s %s\n' "$(sf_now)" "$*" | sf_redact >> "$file"
    chmod 600 "$file"
}
sf_atomic_json() {
    local dest=$1 input=$2 temp
    temp="${dest}.tmp.$(sf_random)"
    jq -e . "$input" > "$temp" || { rm -f -- "$temp"; return 1; }
    chmod 600 "$temp" && sf_sync "$temp" && mv -f -- "$temp" "$dest" && sf_sync "$(dirname -- "$dest")"
}
sf_sync() { [[ ${SFXH_TEST_MODE:-0} == 1 ]] || sync -f "$1"; }
sf_require_space() {
    local path=$1 minimum=${2:-524288} free
    while [[ ! -d $path && $path != / ]]; do path=$(dirname -- "$path"); done
    free=$(LC_ALL=C df -Pk -- "$path" | awk 'NR==2{print $4}') || return
    [[ $free =~ ^[0-9]+$ ]] && ((free >= minimum)) || {
        sf_fail "磁盘空间不足：需要至少 $((minimum/1024)) MiB；尚未修改运行配置。"; return 1;
    }
}
sf_remove_tree() {
    local resolved
    [[ -e $1 || -L $1 ]] || return 0
    resolved=$(realpath -m -- "$1") || return
    case "$resolved" in
        "$SFXH_ETC"/*|"$SFXH_VAR"/*|"$SFXH_RUN"/*) rm -rf -- "$1" ;;
        *) sf_fail '拒绝清理管理目录以外的路径。' ;;
    esac
}
sf_dirs() {
    mkdir -p "$SFXH_ETC/generations" "$SFXH_ETC/backups" "$SFXH_RUN" "$SFXH_VAR/cores" "$SFXH_VAR/cache" "$SFXH_LOG/manager" "$SFXH_LOG/core" "$(dirname -- "$SFXH_LOCK")" || return
    chmod 700 "$SFXH_ETC" "$SFXH_ETC/generations" "$SFXH_ETC/backups" "$SFXH_RUN" "$SFXH_VAR/cache" "$SFXH_LOG/manager" "$SFXH_LOG/core" || return
    # Root owns this traversal-only parent; the service cannot replace manager logs.
    chmod 711 "$SFXH_LOG" || return
    chmod 755 "$SFXH_VAR" "$SFXH_VAR/cores"
}
sf_lock() {
    # Nested transactions inherit this open file description. Only its owner may
    # unlock it; children merely release their local nesting level.
    if [[ -n ${SF_LOCK_FD:-} && -n ${SF_LOCK_OWNER:-} ]]; then
        SF_LOCK_DEPTH=$((${SF_LOCK_DEPTH:-1}+1)); return 0
    fi
    mkdir -p -- "$(dirname -- "$SFXH_LOCK")" || return
    exec {SF_LOCK_FD}>"$SFXH_LOCK" || return
    flock -w 10 "$SF_LOCK_FD" || { exec {SF_LOCK_FD}>&-; unset SF_LOCK_FD; sf_fail '另一个管理操作正在进行，请稍后重试。'; return 1; }
    SF_LOCK_OWNER=$BASHPID; SF_LOCK_DEPTH=1
}
sf_unlock() {
    [[ -n ${SF_LOCK_FD:-} ]] || return 0
    if ((${SF_LOCK_DEPTH:-1}>1)); then SF_LOCK_DEPTH=$((SF_LOCK_DEPTH-1)); return 0; fi
    [[ ${SF_LOCK_OWNER:-} != "$BASHPID" ]] || flock -u "$SF_LOCK_FD"
    exec {SF_LOCK_FD}>&-; unset SF_LOCK_FD SF_LOCK_OWNER SF_LOCK_DEPTH
}
sf_probe_close_locks() {
    # Closing an inherited descriptor (without flock -u) leaves the parent's lock intact.
    [[ -z ${SF_LOCK_FD:-} ]] || exec {SF_LOCK_FD}>&-
    [[ -z ${install_fd:-} ]] || exec {install_fd}>&-
    unset SF_LOCK_FD SF_LOCK_OWNER SF_LOCK_DEPTH install_fd
    return 0
}
sf_generation() {
    local id
    [[ -L $SFXH_ETC/active ]] || return 1
    id=$(readlink "$SFXH_ETC/active") || return
    [[ $id =~ ^generations/[a-zA-Z0-9_-]+$ ]] || return 1
    [[ -d $SFXH_ETC/$id ]] || return 1
    printf '%s\n' "$SFXH_ETC/$id"
}
sf_state() { local g; g=$(sf_generation) || { sf_fail '本机尚未安装。'; return 1; }; printf '%s/state.json\n' "$g"; }
sf_current_core() { local state; state=$(sf_state) || return; sf_core_path "$(jq -r .core.id "$state")"; }
sf_installed() { [[ -f $SFXH_ETC/owner && -L $SFXH_ETC/active && ! -e $SFXH_ETC/uninstalled ]]; }
sf_temp() { mkdir -p -- "$SFXH_ETC/tmp" && chmod 700 "$SFXH_ETC/tmp" && mktemp -d "$SFXH_ETC/tmp/work.XXXXXXXX"; }
sf_normalize_version() { printf '%s\n' "${1#v}"; }
sf_safe_name() {
    printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || return 1
    sf_jq -en --arg name "$1" 'include "model"; $name|display_name' >/dev/null 2>&1
}
sf_domain() {
    local label
    local -a labels
    [[ ${#1} -le 253 && $1 == *.* && $1 != *..* && $1 != *. && $1 =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    IFS=. read -r -a labels <<< "$1"
    for label in "${labels[@]}"; do
        [[ ${#label} -ge 1 && ${#label} -le 63 && $label != -* && $label != *- ]] || return 1
    done
}
sf_host_valid() {
    local value=$1 part
    if [[ $value == *:* ]]; then
        [[ $value =~ ^[0-9A-Fa-f:]+$ && $value != *:::* && $value != :: ]] || return 1
        local remaining=$value count=0 compressed=0
        if [[ $value == *::* ]]; then
            compressed=1; remaining=${value/::/:}
            [[ $remaining != *::* ]] || return 1
        else [[ $value != :* && $value != *: ]] || return 1; fi
        local -a groups
        IFS=: read -r -a groups <<< "$remaining"
        for part in "${groups[@]}"; do
            [[ -n $part ]] || continue
            [[ $part =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
            ((count+=1))
        done
        (( (compressed && count<8) || (!compressed && count==8) ))
    elif [[ $value =~ ^[0-9.]+$ ]]; then
        local -a octets; IFS=. read -r -a octets <<< "$value"
        [[ ${#octets[@]} == 4 ]] || return 1
        for part in "${octets[@]}"; do [[ $part =~ ^(0|[1-9][0-9]{0,2})$ ]] && ((10#$part <= 255)) || return 1; done
    else sf_domain "$value"; fi
}
