#!/usr/bin/env bash
sf_self_channel() {
    local root=$SFXH_CODE source
    if [[ -L $SFXH_INSTALL/sf-xray-hop ]]; then root=$(dirname "$(readlink -f "$SFXH_INSTALL/sf-xray-hop")") || return; fi
    source=$(sf_source_info "$root") || return
    if [[ $(jq -r '.prerelease==true' <<< "$source") == true ]]; then printf 'pre\n'; else printf 'stable\n'; fi
}
sf_self_channel_label() { if [[ $1 == pre ]]; then printf '测试版\n'; else printf '稳定版\n'; fi; }
sf_self_info() {
    local state
    sf_msg "脚本版本：$SFXH_VERSION；当前通道：$(sf_self_channel_label "$(sf_self_channel)")"
    if state=$(sf_state); then sf_msg "核心配置版本：$(jq -r '.core.version+" / "+.core.channel' "$state")；脚本更新不更换核心。"; fi
    sf_msg "实际运行核心：$(sf_running_core_version || printf '—')"
}
sf_self_resolve() {
    local dest=$1 version=${2:-} allow=${3:-} channel=${4:-}
    [[ -z $channel || $channel == stable || $channel == pre ]] || return 2
    [[ -n $channel ]] || channel=$(sf_self_channel) || return
    if [[ -n $allow ]]; then
        [[ -n $version ]] || { sf_usage_error '--allow-pre 必须同时指定 --version；跟随测试版请使用 --channel pre。'; return 2; }
        channel=pinned
    fi
    sf_project_release sprill-gt/SF-Xray-Hop "$channel" "$version" "$dest" || {
        sf_fail '没有找到所选项目发行版，或 GitHub 请求失败；未改用 main／核心 Pre 代替脚本发行版。'; return 1;
    }
}
sf_self_check() (
    local work version='' allow='' channel=''
    while (($#)); do
        case "$1" in --channel) [[ $# -ge 2 ]] || return 2; channel=$2; shift 2 ;; --version) [[ $# -ge 2 ]] || return 2; version=${2#v}; shift 2 ;; --allow-pre) allow=1; shift ;; *) return 2 ;; esac
    done
    work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"' EXIT
    sf_self_resolve "$work/release.json" "$version" "$allow" "$channel" || return
    version=$(jq -r '.tag_name|ltrimstr("v")' "$work/release.json")
    sf_curl_download "https://api.github.com/repos/sprill-gt/SF-Xray-Hop/commits/v$version" "$work/commit.json" || return
    jq -e '.sha|test("^[a-f0-9]{40}$")' "$work/commit.json" >/dev/null || return
    sf_msg "当前脚本：$SFXH_VERSION；目标：$(jq -r '.tag_name' "$work/release.json")"
    sf_msg "目标提交：$(jq -r .sha "$work/commit.json")"
    sf_msg '目标来源：项目 GitHub Release；更新时将验证发行清单、提交与完整包摘要。'
)
sf_release_asset() {
    local metadata=$1 name=$2 dest=$3 repo=$4 url digest count tag
    count=$(jq --arg name "$name" '[.assets[]|select(.name==$name)]|length' "$metadata") || return
    [[ $count == 1 ]] || { sf_fail '发行资产缺失或重复。'; return 1; }
    tag=$(jq -er .tag_name "$metadata") || return
    url=$(jq -er --arg name "$name" '.assets[]|select(.name==$name)|.browser_download_url' "$metadata") || return
    [[ $url == "https://github.com/$repo/releases/download/$tag/$name" ]] || return 2
    sf_curl_download "$url" "$dest" || return
    digest=$(jq -r --arg name "$name" '.assets[]|select(.name==$name)|.digest//""' "$metadata") || return
    [[ -z $digest || $digest == "sha256:$(sf_hash "$dest")" ]] || { sf_fail '发行资产与 API 摘要不一致。'; return 1; }
}
sf_unpack_manager() {
    local archive=$1 dest=$2 work=$3 size
    # Expand to a bounded plain tar before any extraction; reject every link,
    # special member, duplicate name and path outside the one package root.
    (gzip -dc -- "$archive" | head -c 67108865 > "$work/package.tar") 2>/dev/null || return 1
    size=$(wc -c < "$work/package.tar")
    ((size<=67108864)) || { sf_fail '脚本包解压体积超过64 MiB。'; return 1; }
    tar -tf "$work/package.tar" > "$work/members" && tar -tvf "$work/package.tar" > "$work/types" || return
    awk 'BEGIN{ok=1} !/^SF-Xray-Hop\/[A-Za-z0-9_.\/-]*$/ || /(^|\/)\.\.?($|\/)/ || /\/\// || seen[$0]++ {ok=0} END{exit !ok}' "$work/members" &&
      ! grep -qEv '^[-d]' "$work/types" || { sf_fail '脚本包包含不安全路径、重复成员或链接。'; return 1; }
    mkdir -p "$dest" && tar -xf "$work/package.tar" -C "$dest" --strip-components=1 --no-same-owner --no-same-permissions
}
sf_self_download() {
    local metadata=$1 work=$2 version name commit hash size
    version=$(jq -r '.tag_name|ltrimstr("v")' "$metadata") || return
    sf_release_asset "$metadata" manifest.json "$work/manifest.json" sprill-gt/SF-Xray-Hop || return
    [[ $(wc -c < "$work/manifest.json") -le 16384 ]] || return 1
    jq -e --arg version "$version" '.schemaVersion==1 and .project=="SF-Xray-Hop" and .version==$version and
      (.commit|test("^[a-f0-9]{40}$")) and .archive.name==("SF-Xray-Hop-"+$version+".tar.gz") and
      (.archive.sha256|test("^[a-f0-9]{64}$")) and (.archive.size|type=="number" and floor==. and .>0 and .<=16777216)' "$work/manifest.json" >/dev/null || {
        sf_fail '发行清单未知或不一致。'; return 1;
    }
    name=$(jq -r .archive.name "$work/manifest.json"); commit=$(jq -r .commit "$work/manifest.json")
    sf_curl_download "https://api.github.com/repos/sprill-gt/SF-Xray-Hop/commits/v$version" "$work/commit.json" || return
    [[ $(jq -r .sha "$work/commit.json") == "$commit" ]] || { sf_fail '发行标签提交与清单不一致。'; return 1; }
    sf_release_asset "$metadata" "$name" "$work/package.tar.gz" sprill-gt/SF-Xray-Hop || return
    hash=$(sf_hash "$work/package.tar.gz"); size=$(wc -c < "$work/package.tar.gz")
    jq -e --arg hash "$hash" --argjson size "$size" '.archive.sha256==$hash and .archive.size==$size' "$work/manifest.json" >/dev/null || {
        sf_fail '完整脚本包与发行清单不一致。'; return 1;
    }
    sf_unpack_manager "$work/package.tar.gz" "$work/package" "$work" || return
    [[ $(sed -nE 's/^SFXH_VERSION=([0-9.]+)$/\1/p' "$work/package/lib/common.sh") == "$version" ]] || return 1
    jq -n --arg version "$version" --arg commit "$commit" --arg hash "$hash" --argjson pre "$(jq .prerelease "$metadata")" \
      '{kind:"github-release",version:$version,commit:$commit,archiveSha256:$hash,prerelease:$pre}' > "$work/package/source.json"
    sf_msg "已验证脚本包：$version；提交：$commit"
}
sf_manager_unit_compatible() {
    local candidate=$1 hash
    [[ -f $SFXH_UNIT && ! -L $SFXH_UNIT ]] || return 1
    cmp -s "$candidate/systemd/xray.service" "$SFXH_UNIT" && return 0
    hash=$(sf_hash "$SFXH_UNIT") || return
    [[ -f $candidate/data/legacy-units.sha256 ]] && grep -qxF "$hash" "$candidate/data/legacy-units.sha256" || {
        sf_fail '现有 unit 不是已知迁移基线，拒绝覆盖本地修改。'; return 1;
    }
    systemd-analyze verify "$candidate/systemd/xray.service" || return
}
sf_manager_install_unit() {
    local source=$1 temp
    [[ -f $source && ! -L $source && ! -L $SFXH_UNIT ]] || return 1
    temp=$(mktemp "${SFXH_UNIT%/*}/.xray-unit.XXXXXXXX") || return
    if install -m 644 "$source" "$temp" && sf_sync "$temp" && mv -f -- "$temp" "$SFXH_UNIT" && sf_sync "${SFXH_UNIT%/*}"; then
        systemctl daemon-reload
    else rm -f -- "$temp"; return 1; fi
}
sf_manager_restore_unit() {
    local journal=$SFXH_ETC/manager-transaction.json expected
    [[ -f $journal ]] || return 0
    if jq -e '.unitMigration==true' "$journal" >/dev/null; then
        expected=$(jq -er '.unitBackupSha256|select(test("^[a-f0-9]{64}$"))' "$journal") || return
        [[ -f $SFXH_ETC/manager-unit-backup && ! -L $SFXH_ETC/manager-unit-backup && $(sf_hash "$SFXH_ETC/manager-unit-backup") == "$expected" ]] || return 1
        sf_manager_install_unit "$SFXH_ETC/manager-unit-backup" || return
    fi
}
sf_manager_compatible() (
    local candidate=$1 work=$2 current module binary
    SFXH_CODE=$candidate
    # shellcheck disable=SC1090
    for module in common model core; do source "$candidate/lib/$module.sh" || return; done
    sf_paths
    current=$(sf_generation) || return
    sf_manager_unit_compatible "$candidate" || return
    sf_validate_state "$current/state.json" && sf_render "$current/state.json" "$work/rendered.json" || return
    jq -S . "$work/rendered.json" > "$work/new.sorted" && jq -S . "$current/config.json" > "$work/current.sorted" || return
    cmp -s "$work/new.sorted" "$work/current.sorted" || { sf_fail '目标脚本不能保持当前运行配置，拒绝切换。'; return 1; }
    binary=$(sf_current_core) || return
    sf_core_test "$binary" "$work/rendered.json" "$work/compatibility.log"
)
sf_self_recover() {
    local file=$SFXH_ETC/manager-transaction.json old previous
    [[ -f $file ]] || return 0
    old=$(jq -er .old "$file") || return
    previous=$(jq -r '.previous//""' "$file") || return
    [[ $old =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16}$ ]] || return 1
    sf_manager_restore_unit || return
    sf_manager_activate "$SFXH_INSTALL/releases/$old" || return
    sf_manager_restore_previous "$previous" || return
    rm -f -- "$file" "$SFXH_ETC/manager-unit-backup"
    sf_msg '已恢复中断脚本更新前的完整版本；节点状态和运行服务未回退。'
    sf_msg '请重新运行命令，让入口载入恢复后的完整脚本。'
    return 75
}
sf_manager_restore_previous() {
    local id=$1 temp=$SFXH_INSTALL/.previous-manager.new
    [[ ! -e $SFXH_INSTALL/previous-manager || -L $SFXH_INSTALL/previous-manager ]] || return 1
    if [[ -z $id ]]; then rm -f -- "$SFXH_INSTALL/previous-manager"
    else
        [[ $id =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16}$ ]] && sf_manager_verify "$SFXH_INSTALL/releases/$id" || return 1
        ln -sfn -- "$SFXH_INSTALL/releases/$id" "$temp" && mv -Tf -- "$temp" "$SFXH_INSTALL/previous-manager" || return
    fi
    sf_sync "$SFXH_INSTALL"
}
sf_manager_prune() {
    local path current previous n=0
    current=$(dirname "$(readlink -f "$SFXH_INSTALL/sf-xray-hop")") || return
    previous=$(readlink -f "$SFXH_INSTALL/previous-manager") || previous=''
    [[ ! -f $SFXH_ETC/manager-transaction.json ]] || return 0
    while IFS= read -r path; do
        [[ $path =~ /v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16}$ && $path == "$SFXH_INSTALL/releases/"* && ! -L $path && $(realpath -m "$path") == "$path" ]] || continue
        [[ $path != "$current" && $path != "$previous" ]] || continue
        ((n+=1)); ((n<=1)) || rm -rf -- "$path" || return
    done < <(find "$SFXH_INSTALL/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
}
sf_manager_switch() (
    local source=$1 work current next previous='' switched=0 complete=0 unit_change=false unit_hash=''
    sf_root && sf_installed && sf_recover && sf_lock || return
    [[ $(cat "$SFXH_ETC/owner") == SF-Xray-Hop ]] && grep -q 'SF-Xray-Hop managed' "$SFXH_UNIT" || return 1
    work=$(sf_temp) || return
    sf_switch_finish() {
        local rc=$?
        if ((switched && !complete)); then
            sf_manager_restore_unit && sf_manager_activate "$current" && sf_manager_restore_previous "${previous##*/}" && rm -f "$SFXH_ETC/manager-transaction.json" || sf_msg '脚本恢复尚未完成；保留恢复记录。'
        fi
        sf_manager_prune || sf_msg '脚本历史清理未完成，将在下次操作重试。'
        sf_remove_tree "$work"; sf_unlock; return "$rc"
    }
    trap sf_switch_finish EXIT
    trap 'exit 130' INT TERM HUP
    sf_self_recover || return
    sf_require_space "$SFXH_INSTALL" || return
    sf_generation_integrity "$(sf_generation)" && sf_core_verify_archive "$(jq -r .core.id "$(sf_state)")" || return
    next=$(sf_manager_stage "$source") || return
    if [[ -L $SFXH_INSTALL/sf-xray-hop ]]; then current=$(dirname "$(readlink -f "$SFXH_INSTALL/sf-xray-hop")")
    else current=$(sf_manager_stage "$SFXH_INSTALL") || return; fi
    [[ $current == "$SFXH_INSTALL/releases/"* ]] && sf_manager_verify "$current" || return
    if [[ -e $SFXH_INSTALL/previous-manager || -L $SFXH_INSTALL/previous-manager ]]; then
        [[ -L $SFXH_INSTALL/previous-manager ]] || return 1
        previous=$(readlink -f "$SFXH_INSTALL/previous-manager") || return
        [[ $previous == "$SFXH_INSTALL/releases/"* ]] && sf_manager_verify "$previous" || return
    fi
    sf_manager_compatible "$next" "$work" || return
    [[ $current != "$next" ]] || { sf_msg '脚本内容没有变化。'; return 0; }
    if ! cmp -s "$next/systemd/xray.service" "$SFXH_UNIT"; then
        unit_change=true
        [[ ! -L $SFXH_ETC/manager-unit-backup ]] || return 1
        install -m 600 "$SFXH_UNIT" "$SFXH_ETC/manager-unit-backup" && sf_sync "$SFXH_ETC/manager-unit-backup" || return
        unit_hash=$(sf_hash "$SFXH_ETC/manager-unit-backup") || return
    fi
    jq -n --arg old "${current##*/}" --arg new "${next##*/}" --arg previous "${previous##*/}" --argjson migration "$unit_change" --arg hash "$unit_hash" \
      '{old:$old,new:$new,previous:$previous,unitMigration:$migration,unitBackupSha256:$hash}' > "$work/journal.json" &&
      sf_atomic_json "$SFXH_ETC/manager-transaction.json" "$work/journal.json" || return
    switched=1
    sf_manager_activate "$next" "$current" || return
    if [[ $unit_change == true ]]; then
        sf_manager_install_unit "$next/systemd/xray.service" || return
        sf_msg '服务单元已迁移并 daemon-reload；加固在下次明确重启时生效，本次不重启运行核心。'
    fi
    sf_manager_checkpoint after-switch
    sf_manager_verify "$next" && sf_manager_compatible "$next" "$work" &&
      bash "$SFXH_INSTALL/sf-xray-hop" --version > "$work/version.txt" || return
    [[ $(cat "$work/version.txt") == "$(sed -nE 's/^SFXH_VERSION=([0-9.]+)$/\1/p' "$next/lib/common.sh")" ]] || return 1
    complete=1
    rm -f -- "$SFXH_ETC/manager-transaction.json" "$SFXH_ETC/manager-unit-backup" || return
    sf_event "MANAGER 已切换至 ${next##*/}"
    sf_msg "管理脚本已切换：${next##*/}；运行核心、身份和下游保持不变。"
)
sf_self_update() (
    local work version='' allow='' consent='' channel=''
    while (($#)); do
        case "$1" in --channel) [[ $# -ge 2 ]] || return 2; channel=$2; shift 2 ;; --version) [[ $# -ge 2 ]] || return 2; version=${2#v}; shift 2 ;; --allow-pre) allow=1; shift ;; --yes) consent=1; shift ;; *) return 2 ;; esac
    done
    sf_installed && sf_recover && sf_lock || return
    work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"; sf_unlock' EXIT
    sf_self_resolve "$work/release.json" "$version" "$allow" "$channel" && sf_self_download "$work/release.json" "$work" || return
    sf_manager_compatible "$work/package" "$work" || return
    sf_msg "脚本：$SFXH_VERSION → $(jq -r .version "$work/manifest.json")；目标通道：$(if [[ $(jq -r .prerelease "$work/release.json") == true ]]; then sf_self_channel_label pre; else sf_self_channel_label stable; fi)"
    if [[ $(sf_version_direction "$SFXH_VERSION" "$(jq -r .version "$work/manifest.json")") == downgrade ]]; then
        sf_msg '目标脚本版本号较低；这是本次选择的脚本回退，节点和核心设置保持。'
    fi
    [[ -n $consent ]] || sf_confirm '发行包已验证；确认只更新管理脚本？运行核心与节点参数保持。' || return
    sf_manager_switch "$work/package"
)
sf_self_rollback() (
    local previous work
    [[ $# == 0 || ($# == 1 && $1 == --yes) ]] || return 2
    sf_installed && sf_recover && sf_lock || return
    previous=$(readlink -f "$SFXH_INSTALL/previous-manager") || return
    [[ $previous == "$SFXH_INSTALL/releases/"* ]] && sf_manager_verify "$previous" || { sf_fail '没有可验证的上一个管理脚本。'; return 1; }
    work=$(sf_temp) || return
    trap 'sf_remove_tree "$work"; sf_unlock' EXIT
    sf_manager_compatible "$previous" "$work" || { sf_fail '历史脚本不能读取当前状态／核心，拒绝恢复过时私密配置。'; return 1; }
    [[ ${1:-} == --yes ]] || sf_confirm "确认回退脚本到 ${previous##*/}？当前身份、下游与核心保持。" || return
    sf_manager_switch "$previous"
)
