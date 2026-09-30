#!/usr/bin/env bash
sf_generation_integrity() {
    local generation=$1
    [[ -f $generation/SHA256SUMS ]] || { sf_fail '缺少配置代次校验信息。'; return 1; }
    (cd -- "$generation" && sha256sum --check --status SHA256SUMS) || { sf_fail '检测到配置或状态被外部修改，拒绝覆盖。'; return 1; }
}
sf_service_restart() (
    # A failed candidate may exhaust StartLimitBurst before rollback begins.
    # Reset only for an explicit managed restart, never in the service crash loop.
    sf_probe_close_locks
    systemctl reset-failed xray.service >/dev/null 2>&1 || :
    systemctl restart xray.service
)
sf_service_active() { systemctl is-active --quiet xray.service; }
sf_service_ready() {
    local port=$1 attempt
    for attempt in 1 2 3 4 5; do
        sleep 1
        if sf_service_active && [[ -n $(ss -H -ltn "sport = :$port") ]]; then return 0; fi
    done
    return 1
}
sf_activate() {
    local id=$1 temp=$SFXH_ETC/active.new
    [[ $id =~ ^[a-zA-Z0-9_-]+$ && -d $SFXH_ETC/generations/$id ]] || return 2
    ln -sfn -- "generations/$id" "$temp" && mv -Tf -- "$temp" "$SFXH_ETC/active" && sf_sync "$SFXH_ETC"
}
sf_process_token() {
    local pid=$1
    [[ -r /proc/$pid/stat ]] || return 1
    # Remove '(comm)' first; its spaces must not shift starttime (field 22).
    sed 's/.*) //' "/proc/$pid/stat" | awk '$1=="Z" || $1=="X" {exit 1} {print $20}'
}
sf_journal() {
    local old=$1 new=$2 stage=$3 dir=$4 owner_pid=$BASHPID
    jq -n --arg old "$old" --arg new "$new" --arg phase "$stage" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" \
       --arg token "$(sf_process_token "$owner_pid")" --argjson pid "$owner_pid" \
       '{old:$old,new:$new,phase:$phase,bootId:$boot,pid:$pid,processStart:$token}' > "$dir/journal.json" &&
    sf_atomic_json "$SFXH_ETC/transaction.json" "$dir/journal.json"
}
sf_journal_owner_alive() {
    local journal=$SFXH_ETC/transaction.json pid token boot
    pid=$(jq -er .pid "$journal") || return 1
    [[ $pid =~ ^[0-9]+$ ]] || return 1
    boot=$(jq -er .bootId "$journal") || return 1
    [[ $boot == "$(cat /proc/sys/kernel/random/boot_id)" ]] || return 1
    token=$(sf_process_token "$pid") || return 1
    [[ $token == "$(jq -r .processStart "$journal")" ]]
}
sf_recover() {
    local mode=${1:-normal} journal=$SFXH_ETC/transaction.json old phase
    [[ -f $journal ]] || return 0
    if sf_journal_owner_alive; then
        [[ $mode == boot ]] && return 0
        sf_fail '另一个配置事务仍在执行。'; return 1
    fi
    sf_lock || return
    if [[ ! -f $journal ]]; then sf_unlock; return 0; fi
    old=$(jq -er '.old' "$journal") || { sf_unlock; return 1; }
    phase=$(jq -r '.phase' "$journal")
    if [[ -n $old ]]; then
        sf_generation_integrity "$SFXH_ETC/generations/$old" && sf_activate "$old" || { sf_unlock; return 1; }
        sf_event 'RECOVERY 已恢复中断事务前的配置代次'
    else
        rm -f -- "$SFXH_ETC/active"
        sf_event 'RECOVERY 首次安装未完成，未启用候选配置'
    fi
    rm -f -- "$journal"; sf_sync "$SFXH_ETC"; sf_unlock
    if [[ $mode != boot && -n $old && $phase != metadata ]]; then sf_service_restart || return; fi
}
sf_tx_apply() (
    local candidate=$1 reason=$2 mode=${3:-online} intent=${4:-runtime} work old='' generation id binary client_binary previous core_id committed=0 switched=0 runtime_change=1 phase=switching
    [[ $mode == online || $mode == offline ]] || return 2
    [[ $intent == runtime || ($intent == metadata && $mode == online) ]] || return 2
    sf_recover || return
    sf_lock || return
    work=$(sf_temp) || return
    sf_tx_finish() {
        local result=$?
        trap - EXIT INT TERM HUP
        if ((switched && !committed)); then
            sf_msg '正在恢复修改前的配置……'
            if [[ -n $old ]]; then
                if sf_activate "$old" && { ((runtime_change==0)) || sf_service_restart; }; then
                    if ((runtime_change)); then
                        if [[ $mode == online ]]; then sf_health_current || sf_msg '旧配置已恢复，但当前网络复测未通过，请运行 doctor。'
                        else sf_service_active || sf_msg '旧配置已恢复，但服务尚未运行，请检查本机日志。'; fi
                    fi
                    sf_event 'ROLLBACK 已恢复修改前代次'
                    rm -f -- "$SFXH_ETC/transaction.json"
                else sf_msg '恢复服务失败，事务记录已保留，启动时将再次恢复。'; fi
            else
                systemctl stop xray.service >/dev/null 2>&1 || :
                systemctl disable xray.service >/dev/null 2>&1 || :
                rm -f -- "$SFXH_ETC/active" "$SFXH_ETC/transaction.json"
                sf_msg '首次安装未通过验证，候选服务已停止；可以重新安装。'
            fi
        fi
        sf_remove_tree "$work"
        sf_unlock
        exit "$result"
    }
    trap sf_tx_finish EXIT
    trap 'exit 130' INT TERM HUP
    if previous=$(sf_generation); then
        sf_generation_integrity "$previous" || return
        old=$(basename "$previous")
        # Optimistic generation guard prevents concurrent changes being overwritten.
        if [[ -n ${SF_EXPECT_GENERATION:-} && $SF_EXPECT_GENERATION != "$old" ]]; then sf_fail '配置已变化，请重新操作。'; return 1; fi
    fi
    sf_validate_state "$candidate" || return
    core_id=$(jq -r .core.id "$candidate")
    sf_core_verify_archive "$core_id" || return
    binary=$(sf_core_path "$core_id") || return
    client_binary=$binary
    if [[ -n $old ]]; then client_binary=$(sf_core_path "$(jq -r .core.id "$previous/state.json")") || return; fi
    sf_render "$candidate" "$work/config.json" || return
    if [[ -n $old ]]; then
        jq -S . "$candidate" > "$work/new-state.json" && jq -S . "$previous/state.json" > "$work/old-state.json" || return
        if cmp -s "$work/new-state.json" "$work/old-state.json" && { [[ $intent == metadata ]] || sf_service_active; }; then sf_msg '配置与核心未变化，无需重启。'; return 0; fi
        jq -S . "$work/config.json" > "$work/new-runtime.json" && jq -S . "$previous/config.json" > "$work/old-runtime.json" || return
        if cmp -s "$work/new-runtime.json" "$work/old-runtime.json" && [[ $(sf_hash "$binary") == "$(sf_hash "$client_binary")" ]] && { [[ $intent == metadata ]] || sf_service_active; }; then runtime_change=0; phase=metadata; fi
        cp -a -- "$previous" "$SFXH_ETC/backups/${old}-$(sf_random)" || return
    fi
    if [[ $intent == metadata && $runtime_change != 0 ]]; then sf_fail '展示信息修改不得改变运行配置或核心，未提交。'; return 1; fi
    if [[ $mode == offline ]]; then
        [[ -n $old ]] && sf_normalize_state "$previous/state.json" "$work/offline-base.json" &&
          jq -e --slurpfile old "$work/offline-base.json" 'del(.core)==($old[0]|del(.core))' "$candidate" >/dev/null || {
            sf_fail '离线恢复只允许更换历史核心，禁止同时改动身份、路由或下游。'; return 1;
        }
    fi
    if ((runtime_change)); then
        # Applies to new installs, normal updates AND explicit offline rollback.
        # Historic "verified" metadata never substitutes for the current policy.
        sf_core_security "$binary" || return
        sf_core_test "$binary" "$work/config.json" "$work/config-test.log" || return
        if [[ $mode == online ]]; then
            sf_msg '候选配置已通过语法检查，正在进行独立协议测试……'
            sf_probe_candidate "$candidate" "$binary" "$client_binary" "$work/candidate" || return
        else sf_msg '显式离线恢复：已检查核心安全底线，继续验证配置与服务启动；公网与出口状态将记为未验证。'; fi
    fi
    id="$(date -u +%Y%m%dT%H%M%S)-$(sf_random)"; generation=$SFXH_ETC/generations/$id
    mkdir -m 700 "$generation" || return
    cp -- "$candidate" "$generation/state.json" && cp -- "$work/config.json" "$generation/config.json" || return
    printf '%s\n' "$core_id" > "$generation/core-id"
    (cd -- "$generation" && sha256sum state.json config.json core-id > SHA256SUMS) || return
    chmod 600 "$generation/"*; sf_sync "$generation" || return
    sf_journal "$old" "$id" "$phase" "$work" || return
    switched=1
    sf_activate "$id" || return
    sf_event "APPLY $reason"
    if ((runtime_change)); then
        sf_service_restart || { sf_fail '正式服务启动失败。'; return 1; }
        if [[ $mode == online ]]; then sf_health_current || return
        else
            sf_service_ready "$(jq -r .node.port "$candidate")" || { sf_fail '离线恢复后服务或监听未就绪。'; return 1; }
            jq -n --arg at "$(sf_now)" --arg g "$id" '{status:"unverified-offline",checkedAt:$at,generation:$g}' > "$work/offline-health.json" &&
                sf_atomic_json "$SFXH_VAR/cache/health.json" "$work/offline-health.json" || return
        fi
    elif [[ -f $SFXH_VAR/cache/health.json ]]; then
        jq --arg old "$old" --arg g "$id" 'if .generation==$old then .generation=$g else . end' "$SFXH_VAR/cache/health.json" > "$work/health.json" &&
            sf_atomic_json "$SFXH_VAR/cache/health.json" "$work/health.json" || return
    fi
    if [[ $mode == online ]] && { ((runtime_change)) || [[ $(cat "$SFXH_ETC/last-good" 2>/dev/null) == "$old" ]]; }; then
        printf '%s\n' "$id" > "$work/last-good"
        mv -f "$work/last-good" "$SFXH_ETC/last-good" && sf_sync "$SFXH_ETC" || return
    fi
    if ((runtime_change)) && [[ $mode == online ]]; then
        jq --arg at "$(sf_now)" '.verified=true|.verifiedAt=$at' "$SFXH_VAR/cores/$core_id/metadata.json" > "$work/core-meta.json" &&
          sf_atomic_json "$SFXH_VAR/cores/$core_id/metadata.json" "$work/core-meta.json" || return
    fi
    rm -f -- "$SFXH_ETC/transaction.json"; sf_sync "$SFXH_ETC" || return
    committed=1
    sf_event "COMMIT $reason"
    sf_prune_locked || sf_msg '本次历史清理未完成，已提交的配置保持；可稍后运行 core prune。'
    if ((runtime_change==0)); then sf_msg '显示／导出设置已保存，服务未重启，已有连接保持。'
    elif [[ $mode == offline ]]; then sf_msg '历史核心已启动；公网、下游及出口未验证，请在网络恢复后运行 doctor。'
    else sf_msg '配置已应用，正式链路复测通过。'; fi
)
sf_prepare_runtime() {
    sf_root || return
    sf_recover boot || return
    local g binary id
    g=$(sf_generation) || return
    sf_generation_integrity "$g" || return
    id=$(cat "$g/core-id")
    sf_core_verify_archive "$id" || return
    binary=$(sf_core_path "$id") || return
    # The service may read credentials but cannot plant symlinks for the root helper.
    chown root:root "$SFXH_RUN" && chmod 711 "$SFXH_RUN" || return
    rm -f -- "$SFXH_RUN/config.json" "$SFXH_RUN/xray" || return
    install -m 600 -o sfxray -g sfxray "$g/config.json" "$SFXH_RUN/config.json" || return
    ln -sfn "$binary" "$SFXH_RUN/xray" || return
}
sf_runtime() {
    local line file=$SFXH_LOG/core/core.log count=0 size=0
    # Console output is filtered before persistent storage; no unredacted journal.
    "$SFXH_RUN/xray" run -config "$SFXH_RUN/config.json" 2>&1 |
      sf_redact | while IFS= read -r line; do
        if ((count % 100 == 0)); then
            size=$(wc -c < "$file" 2>/dev/null) || size=0
            if ((size>1048576)); then mv -f "$file.1" "$file.2" 2>/dev/null || :; mv -f "$file" "$file.1" || :; fi
        fi
        printf '%s %s\n' "$(sf_now)" "$line" >> "$file"; ((count+=1))
      done
}
