#!/usr/bin/env bash
sf_core_path() {
    [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16}$ ]] || return 2
    [[ -x $SFXH_VAR/cores/$1/xray ]] || return 1
    printf '%s/cores/%s/xray\n' "$SFXH_VAR" "$1"
}
sf_core_test() {
    local binary=$1 config=$2 output=$3
    timeout 20 "$binary" run -test -config "$config" 2>&1 | sf_redact > "$output" || { sf_fail 'Xray 配置验证失败（诊断输出已脱敏）。'; return 1; }
}
sf_core_security() (
    local binary=$1 work hash policy cache expected pid='' unit='' result
    binary=$(realpath -- "$binary") || return
    [[ -x $binary && $binary != *:* && $binary != *[[:space:]]* && $SFXH_CODE != *:* && $SFXH_CODE != *[[:space:]]* ]] || return 2
    hash=$(sf_hash "$binary") || return
    policy=$(cat "$SFXH_CODE/lib/core.sh" "$SFXH_CODE/lib/core-safety-worker.sh" "$SFXH_CODE/data/core-safety.json" "$SFXH_CODE/templates/model.jq" | sha256sum | cut -d' ' -f1) || return
    expected=$(jq '.targets|length*2' "$SFXH_CODE/data/core-safety.json") || return
    cache=$SFXH_VAR/cache/core-safety/$hash.json
    [[ ! -L $SFXH_VAR/cache/core-safety && ! -L $cache ]] || return 1
    if [[ -f $cache ]] && jq -e --arg hash "$hash" --arg policy "$policy" --argjson n "$expected" '
      .binarySha256==$hash and .policySha256==$policy and .status=="pass" and .tcpChecks==$n and .udpChecks==2 and
      .identities==2 and .receiverControls==2 and .authenticatedControls==2' "$cache" >/dev/null 2>&1; then return 0; fi
    work=$(sf_temp) || return
    trap 'sf_stop_probe "$pid" "$unit"; sf_remove_tree "$work"' EXIT
    trap 'exit 130' INT TERM HUP
    # The HTTPS bootstrap extracts under umask 077 before manager deployment.
    # Bind mounting a root-only source file preserves its mode: DynamicUser
    # cannot read it. Stage only these public probe inputs with explicit modes;
    # the private parent, credentials and original source permissions stay intact.
    install -m 644 "$SFXH_CODE/lib/core-safety-worker.sh" "$work/safety-worker.sh" &&
      install -m 644 "$SFXH_CODE/data/core-safety.json" "$work/safety-targets.json" || return
    # PrivateNetwork prevents a failing/old candidate from touching host-private
    # destinations. The hosts file is bind-mounted ONLY in this temporary unit.
    jq -r '.targets[]|select(.host|endswith(".test"))|.ip+" "+.host' "$SFXH_CODE/data/core-safety.json" > "$work/hosts" || return
    chmod 644 "$work/hosts" || return
    unit="sfxh-probe-$(sf_random).service"
    mkdir -p "$SFXH_RUN/probes" && chmod 700 "$SFXH_RUN/probes" || return
    printf '%s\n' "$binary" > "$SFXH_RUN/probes/$unit" || return
    sf_msg '正在隔离验证核心的私网目标防护（无需访问公网或真实内网）……'
    (sf_probe_close_locks
     systemd-run --quiet --wait --pipe --collect --service-type=exec --unit "$unit" \
       -p 'Description=SF-Xray-Hop owned temporary probe' -p DynamicUser=yes -p NoNewPrivileges=yes \
       -p CapabilityBoundingSet= -p AmbientCapabilities= -p ProtectSystem=strict -p ProtectHome=yes \
       -p PrivateTmp=yes -p PrivateNetwork=yes -p UMask=0077 -p RuntimeMaxSec=120s -p TimeoutStopSec=3 -p KillMode=control-group \
       -p "BindReadOnlyPaths=$binary:/tmp/sfxh-safety-core" \
       -p "BindReadOnlyPaths=$work/safety-worker.sh:/tmp/sfxh-safety-worker.sh" \
       -p "BindReadOnlyPaths=$work/safety-targets.json:/tmp/sfxh-safety-targets.json" \
       -p "BindReadOnlyPaths=$work/hosts:/etc/hosts" \
       -- /usr/bin/bash /tmp/sfxh-safety-worker.sh /tmp/sfxh-safety-core /tmp/sfxh-safety-targets.json \
       > "$work/result.json" 2> "$work/unit.log") &
    pid=$!
    result=0; wait "$pid" || result=$?
    if ((result)) || ! jq -e --argjson n "$expected" '.status=="pass" and .tcpChecks==$n and .udpChecks==2 and
        .identities==2 and .receiverControls==2 and .authenticatedControls==2' "$work/result.json" >/dev/null 2>&1; then
        sf_fail '未确认核心保持私网安全底线（或隔离探测不可用），拒绝使用该候选；不会因配置能启动或 --offline 而跳过。'
        return 1
    fi
    mkdir -p "${cache%/*}" && chmod 700 "${cache%/*}" || return
    jq --arg hash "$hash" --arg policy "$policy" --arg at "$(sf_now)" \
      '.+{binarySha256:$hash,policySha256:$policy,checkedAt:$at}' "$work/result.json" > "$work/record.json" || return
    sf_atomic_json "$cache" "$work/record.json"
)
sf_core_capabilities() {
    local binary=$1 dir=$2 mode=${3:-initialize}
    if [[ $mode != initialize ]]; then
        timeout 10 "$binary" version > "$dir/version.txt" 2>&1 &&
        timeout 10 "$binary" help vlessenc > "$dir/vlessenc-help.txt" 2>&1 &&
        timeout 10 "$binary" help x25519 > "$dir/x25519-help.txt" 2>&1 &&
        grep -q vlessenc "$dir/vlessenc-help.txt" && grep -q x25519 "$dir/x25519-help.txt" || {
            sf_fail '核心命令能力未知，停止更新；未生成或覆盖密钥。'; return 1;
        }
        return 0
    fi
    timeout 10 "$binary" version > "$dir/version.txt" 2>&1 &&
    timeout 15 "$binary" vlessenc > "$dir/vlessenc.txt" 2>&1 &&
    timeout 10 "$binary" x25519 > "$dir/x25519.txt" 2>&1 || { sf_fail '核心缺少必要能力或运行失败。'; return 1; }
    sf_parse_encryption "$dir/vlessenc.txt" "$dir/encryption.json" || return
    sf_parse_reality_keys "$dir/x25519.txt" "$dir/reality-keys.json"
}
sf_parse_encryption() {
    local input=$1 output=$2
    # Select a labelled authentication block, never mix the two key pairs.
    LC_ALL=C awk '/^Authentication:/{active=($0 ~ /^Authentication: ML-KEM-768, Post-Quantum/)} active && /^"(decryption|encryption)":/{print}' "$input" |
      jq -Rs 'split("\n") | map(select(length>0) | sub("\r$";"") | "{"+.+"}" | fromjson) | select(length==2) | add |
       select((.decryption|type)=="string" and (.encryption|type)=="string") |
       (.decryption|split(".")) as $d | (.encryption|split(".")) as $e |
       select(($d|length)==4 and ($e|length)==4 and $d[0]==$e[0] and $d[1]==$e[1] and
         ($d[0]|test("^[a-zA-Z0-9-]+$")) and ($d[1]=="native" or $d[1]=="xorpub" or $d[1]=="random") and
         ($d[2]|test("^[0-9]+(-[0-9]+)?s$")) and ($e[2]=="0rtt" or $e[2]=="1rtt") and
         ($d[3]|test("^[A-Za-z0-9_-]{86}$")) and ($e[3]|test("^[A-Za-z0-9_-]{1579}$"))) |
       . + {generatorDecryption:.decryption,authentication:"ML-KEM-768",rtt:"0"}' > "$output" 2>/dev/null || return 1
    [[ -s $output ]] || { sf_fail '无法识别 vlessenc 输出；拒绝猜测新格式。'; return 1; }
}
sf_parse_reality_keys() {
    LC_ALL=C awk -F': ' '/^PrivateKey:/{print $2} /^Password( \(PublicKey\))?:/{print $2}' "$1" | tr -d '\r' |
      jq -Rs 'split("\n")|map(select(length>0))|select(length==2 and all(.[];test("^[A-Za-z0-9_-]{43}$")))|{privateKey:.[0],password:.[1]}' > "$2" 2>/dev/null || return
    [[ -s $2 ]] || { sf_fail '无法识别 x25519 输出。'; return 1; }
}
sf_github_curl() {
    local url=$1 token=${SFXH_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}
    shift
    if [[ $url == https://api.github.com/repos/* && -n $token ]]; then
        [[ $token =~ ^[A-Za-z0-9_.-]+$ ]] || { sf_fail 'GitHub Token 格式无效。'; return 2; }
        # Read the credential from stdin, never from curl's process arguments.
        curl --header @- "$@" "$url" <<< "Authorization: Bearer $token"
    else
        curl "$@" "$url"
    fi
}
sf_curl_download() {
    if [[ $1 == https://github.com/XTLS/Xray-core/releases/download/*/Xray-linux-64.zip ]]; then
        sf_core_asset "$1" "$2"
    else
        sf_github_curl "$1" --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 180 --retry 2 -o "$2" 2>/dev/null
    fi
}
sf_core_asset() (
    local url=$1 dest=$2 attempt pid='' rc bytes
    trap '[[ -z $pid ]] || { kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; }; rm -f -- "$dest.error"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    for attempt in {1..5}; do
        bytes=0; [[ ! -f $dest ]] || bytes=$(wc -c < "$dest")
        sf_msg "核心下载：第 $attempt/5 次，从 $bytes 字节继续（单次最多 180 秒）……"
        curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 180 --speed-time 30 --speed-limit 1024 --max-filesize 134217728 \
          --continue-at - "$url" -o "$dest" 2> "$dest.error" &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            sleep 5
            [[ ! -f $dest ]] || sf_msg "核心下载：已接收 $(wc -c < "$dest") 字节。"
        done
        rc=0; wait "$pid" || rc=$?; pid=''
        ((rc!=0)) || return 0
        # Only transient transfer failures are resumable. HTTP, unsupported Range,
        # TLS validation and size errors fail without executing an unverified file.
        case "$rc" in
            18|28|52|55|56) sf_msg "核心传输中断（curl $rc），保留已下载内容并尝试续传。" ;;
            *) sf_fail "核心下载失败（curl $rc），未解压或执行。"; return 1 ;;
        esac
    done
    sf_fail '核心下载重试已达上限，未解压或执行。'
)
sf_core_api() {
    local url=$1 dest=$2 code rc=0
    [[ $url == https://api.github.com/repos/XTLS/Xray-core/* ]] || return 2
    code=$(sf_github_curl "$url" --silent --show-error --location --compressed --proto '=https' --proto-redir '=https' \
      --connect-timeout 10 --max-time 30 --retry 1 --retry-max-time 40 --max-filesize 2097152 \
      --output "$dest" --write-out '%{http_code}' 2> "$dest.error") || rc=$?
    rm -f -- "$dest.error"
    ((rc==0)) || { sf_fail "GitHub 版本查询超时或传输失败（curl $rc），请稍后重试；未使用不完整结果。"; return 1; }
    [[ $code != 404 ]] || return 4
    [[ $code == 200 ]] || { sf_fail "GitHub 版本查询返回 HTTP $code（可能限流或服务异常），未推定最新版本。"; return 1; }
}
sf_core_deny_reason() {
    local file=$SFXH_CODE/data/core-denylist.json
    [[ -f $file ]] || return 0
    jq -e '.schemaVersion==1 and (.versions|type=="array" and all(.[]; (.version|type)=="string" and (.reason|type)=="string"))' "$file" >/dev/null || return 2
    jq -r --arg version "${1#v}" '[.versions[] | select(.version==$version)][0].reason // empty' "$file"
}
sf_core_allowed() {
    local reason context=${2:-explicit}
    if reason=$(sf_core_deny_reason "$1"); then
        if [[ -n $reason ]]; then
            if [[ $context == selection ]]; then
                sf_msg "跳过已撤回的 Xray ${1#v}：$reason；继续查找符合条件的版本。"
            else sf_fail "Xray ${1#v} 已撤回：$reason；请运行 sfxh core update。"; fi
            return 2
        fi
    else
        sf_fail '撤回版本策略无法读取，停止选版。'; return 1
    fi
}
sf_core_warn_version() {
    local reason
    reason=$(sf_core_deny_reason "$1") || return 0
    [[ -z $reason ]] || sf_msg "警告：Xray ${1#v} 已撤回：$reason；建议运行 sfxh core update，未自动换核。"
}
sf_core_latest() (
    local channel=$1 dest=$2 work page count tag rc
    work=$(mktemp -d "${dest}.tags.XXXXXXXX") || return
    trap 'rm -rf -- "$work"' EXIT
    : > "$work/tags.jsonl"
    # Tags contain version names and commit IDs, without every release's assets.
    # Enumerate every page before numerical sorting; API order is not version order.
    for ((page=1;page<=100;page++)); do
        sf_msg "正在查询 Xray 轻量版本索引（第 $page 页，每次最多等待 30 秒）……"
        sf_core_api "https://api.github.com/repos/XTLS/Xray-core/tags?per_page=100&page=$page" "$work/page.json" || return 1
        jq -e 'type=="array" and all(.[]; type=="object" and (.name|type)=="string")' "$work/page.json" >/dev/null || {
            sf_fail 'GitHub 版本索引格式异常。'; return 1;
        }
        count=$(jq length "$work/page.json") || return
        jq -c '.[].name' "$work/page.json" >> "$work/tags.jsonl" || return
        ((count==100)) || break
    done
    ((page<=100)) || { sf_fail '版本索引分页超过安全上限，未推定最新版本。'; return 1; }
    jq -sr 'map(select(test("^v[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}$")))|unique|
      sort_by(ltrimstr("v")|split(".")|map(tonumber))|reverse[]' "$work/tags.jsonl" > "$work/candidates" || return
    while IFS= read -r tag; do
        rc=0
        sf_core_allowed "$tag" selection || rc=$?
        if ((rc==2)); then continue; fi
        ((rc==0)) || return 1
        sf_msg "正在核对 Xray $tag 的已发布版本信息……"
        rc=0
        sf_core_api "https://api.github.com/repos/XTLS/Xray-core/releases/tags/$tag" "$work/release.json" || rc=$?
        if ((rc==4)); then continue; fi # An unpublished Git tag is not a Release.
        ((rc==0)) || return 1
        jq -e --arg tag "$tag" '.tag_name==$tag and (.draft|type)=="boolean" and
          (.prerelease|type)=="boolean" and (.published_at==null or (.published_at|type)=="string")' "$work/release.json" >/dev/null || {
            sf_fail 'GitHub 发行信息格式异常或标签不一致。'; return 1;
        }
        jq -e --arg channel "$channel" '.draft==false and (.published_at|type)=="string" and
          ($channel=="auto" or ($channel=="pre" and .prerelease==true) or ($channel=="stable" and .prerelease==false))' "$work/release.json" >/dev/null || continue
        cp -- "$work/release.json" "$dest" || return
        sf_msg "已选 Xray $tag（$(jq -r 'if .prerelease then "Pre" else "正式版" end' "$dest")）。"
        return 0
    done < "$work/candidates"
    sf_fail "没有符合 $channel 频道的已发布版本；未退回其他频道。"
)
sf_release_metadata() {
    local channel=$1 version=$2 dest=$3
    [[ -z $version ]] || { sf_core_require_version "$version" && sf_core_allowed "$version"; } || return
    sf_project_release XTLS/Xray-core "$channel" "$version" "$dest" || return
    sf_core_require_version "$(jq -r '.tag_name|ltrimstr("v")' "$dest")"
}
sf_project_release() (
    local repo=$1 channel=$2 version=$3 dest=$4 page=1 count work
    [[ $repo == XTLS/Xray-core || $repo == sprill-gt/SF-Xray-Hop ]] || return 2
    [[ $channel == auto || $channel == pre || $channel == stable || $channel == pinned ]] || return 2
    [[ $channel != auto || $repo == XTLS/Xray-core ]] || return 2
    if [[ $repo == XTLS/Xray-core && -z $version && $channel != pinned ]]; then
        sf_core_latest "$channel" "$dest"; return $?
    fi
    work=$(mktemp -d "${dest}.pages.XXXXXXXX") || return
    trap 'rm -rf -- "$work"' EXIT
    if [[ -n $version ]]; then
        [[ $repo != XTLS/Xray-core ]] || sf_core_allowed "$version" || return
        version=${version#v}
        [[ $version =~ ^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$ ]] || return 2
        if [[ $repo == XTLS/Xray-core ]]; then
            sf_msg "正在查询 Xray v$version（每次最多等待 30 秒）……"
            sf_core_api "https://api.github.com/repos/$repo/releases/tags/v$version" "$dest" || return 1
        else
            sf_curl_download "https://api.github.com/repos/$repo/releases/tags/v$version" "$dest" || return
        fi
        jq -e --arg tag "v$version" --arg channel "$channel" '.draft==false and .tag_name==$tag and
          (.prerelease|type)=="boolean" and (.published_at|type)=="string" and
          ($channel=="auto" or $channel=="pinned" or ($channel=="pre" and .prerelease==true) or ($channel=="stable" and .prerelease==false))' "$dest" >/dev/null || return
    else
        [[ $channel != pinned ]] || return 2
        : > "$work/releases.jsonl"
        while ((page<=100)); do
            sf_curl_download "https://api.github.com/repos/$repo/releases?per_page=100&page=$page" "$work/page.json" || return
            jq -e 'type=="array"' "$work/page.json" >/dev/null || return
            count=$(jq length "$work/page.json") || return
            jq -c '.[]' "$work/page.json" >> "$work/releases.jsonl" || return
            ((count==100)) || break
            ((page+=1))
        done
        ((page<=100)) || { sf_fail 'Release 分页超过安全上限，未推定最新版本。'; return 1; }
        jq -s --arg channel "$channel" '[.[]|select(.draft==false and (.published_at|type)=="string" and
          (($channel=="auto" and (.prerelease|type)=="boolean") or ($channel=="pre" and .prerelease==true) or ($channel=="stable" and .prerelease==false)) and
          (.tag_name|test("^v[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}$")))]|
          unique_by(.id)|sort_by([(.tag_name|ltrimstr("v")|split(".")|map(tonumber)), (if .prerelease then 0 else 1 end)])|last' "$work/releases.jsonl" > "$dest" || return
        jq -e 'type=="object"' "$dest" >/dev/null || { sf_fail "没有符合 $channel 频道的已发布版本；未退回其他频道。"; return 1; }
    fi
)
sf_version_direction() {
    jq -nr --arg old "${1#v}" --arg new "${2#v}" '
      ($old|split(".")|map(tonumber)) as $a | ($new|split(".")|map(tonumber)) as $b |
      if $b>$a then "upgrade" elif $b<$a then "downgrade" else "same" end'
}
sf_core_require_version() {
    local version=${1#v} i
    local -a requested minimum
    [[ $version =~ ^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$ ]] || {
        sf_usage_error "核心版本格式应为数字版本号，例如 $SFXH_MIN_CORE。"; return 2;
    }
    # Installation can validate an explicit version before jq is installed.
    IFS=. read -r -a requested <<< "$version"
    IFS=. read -r -a minimum <<< "$SFXH_MIN_CORE"
    for i in 0 1 2; do
        ((10#${requested[i]} > 10#${minimum[i]})) && return 0
        if ((10#${requested[i]} < 10#${minimum[i]})); then
            sf_usage_error "最低支持 Xray $SFXH_MIN_CORE，不能选择 $version。"; return 2
        fi
    done
    return 0
}
sf_core_download() {
    local metadata=$1 work=$2 mode=${3:-inspect} prior_archive=${4:-} consent=${5:-} url dgst_url expected actual checksum version id target
    version=$(jq -r '.tag_name|ltrimstr("v")' "$metadata")
    sf_core_require_version "$version" && sf_core_allowed "$version" || return
    url=$(jq -er '.assets[]|select(.name=="Xray-linux-64.zip")|.browser_download_url' "$metadata") || return
    dgst_url=$(jq -er '.assets[]|select(.name=="Xray-linux-64.zip.dgst")|.browser_download_url' "$metadata") || return
    [[ $url == "https://github.com/XTLS/Xray-core/releases/download/v$version/Xray-linux-64.zip" && $dgst_url == "$url.dgst" ]] || return 2
    sf_require_space "$work" && sf_require_space "$SFXH_VAR/cores" || return
    sf_msg "正在下载并校验 Xray $version……"
    sf_curl_download "$url" "$work/core.zip" && sf_curl_download "$dgst_url" "$work/core.dgst" || { sf_fail '核心下载失败。'; return 1; }
    actual=$(sf_hash "$work/core.zip")
    expected=$(jq -r '.assets[]|select(.name=="Xray-linux-64.zip")|.digest // ""' "$metadata")
    [[ -z $expected || $expected == "sha256:$actual" ]] || { sf_fail 'Release 资产摘要不一致。'; return 1; }
    checksum=$(grep -Ei 'sha2?-?256' "$work/core.dgst" | grep -Eo '[0-9a-fA-F]{64}' | tr 'A-F' 'a-f')
    [[ $checksum == "$actual" ]] || { sf_fail 'Release dgst 校验失败。'; return 1; }
    if [[ -n $prior_archive && $prior_archive != "$actual" && $consent != --yes ]]; then
        sf_confirm '相同核心标签的发行压缩包摘要发生变化。确认继续验证这份新内容？' || return
        touch "$work/archive-change-confirmed" || return
    fi
    mkdir -p "$work/unpacked" || return
    unzip -p "$work/core.zip" xray > "$work/unpacked/xray" && chmod 755 "$work/unpacked/xray" || return
    sf_core_capabilities "$work/unpacked/xray" "$work" "$mode" || return
    grep -Eq "^Xray $version([[:space:]]|$)" "$work/version.txt" || { sf_fail '下载核心版本与 Release 不一致。'; return 1; }
    sf_core_security "$work/unpacked/xray" || return
    id="v$version-$(sf_hash "$work/unpacked/xray" | cut -c1-16)"
    sf_core_publish "$id" "$work/unpacked/xray" "$metadata" "$actual" || return
    printf '%s\n' "$id"
}
sf_core_verify_directory() {
    local path=$1 id=$2 hash
    [[ $id =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16}$ && -d $path && ! -L $path &&
       -f $path/xray && -x $path/xray && ! -L $path/xray && -f $path/metadata.json && ! -L $path/metadata.json ]] || return 1
    hash=$(sf_hash "$path/xray") || return
    [[ ${id##*-} == "${hash:0:16}" ]] || return 1
    jq -e --arg id "$id" --arg hash "$hash" --arg version "${id%-*}" \
       '.id==$id and .sha256==$hash and ("v"+.version)==$version' "$path/metadata.json" >/dev/null 2>&1
}
sf_core_verify_archive() {
    sf_core_verify_directory "$SFXH_VAR/cores/$1" "$1" || { sf_fail '归档核心不完整或校验失败。'; return 1; }
}
sf_core_referenced() {
    local id=$1 file
    # Conservative: every retained generation/backup protects its referenced core.
    while IFS= read -r -d '' file; do
        [[ $(cat "$file") != "$id" ]] || return 0
    done < <(find "$SFXH_ETC/generations" "$SFXH_ETC/backups" -type f -name core-id -print0 2>/dev/null)
    [[ $(readlink "$SFXH_RUN/xray" 2>/dev/null) != "$SFXH_VAR/cores/$id/xray" ]] || return 0
    return 1
}
sf_core_checkpoint() { :; } # Overridden only by isolated fault-injection tests.
sf_core_publish() (
    local id=$1 binary=$2 metadata=$3 archive=$4 target stage='' lock_fd old
    target=$SFXH_VAR/cores/$id
    [[ $id =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16}$ ]] || return 2
    mkdir -p "$SFXH_VAR/cores/.locks" "$SFXH_VAR/cores/.quarantine" || return
    chmod 700 "$SFXH_VAR/cores/.locks" "$SFXH_VAR/cores/.quarantine" || return
    exec {lock_fd}>"$SFXH_VAR/cores/.locks/$id.lock" || return
    flock -w 30 "$lock_fd" || { sf_fail '相同核心正在归档，请稍后重试。'; return 1; }
    trap '[[ -z $stage ]] || sf_remove_tree "$stage"' EXIT
    trap 'exit 130' INT TERM HUP
    if [[ -e $target || -L $target ]]; then
        if sf_core_verify_directory "$target" "$id"; then touch "$target/last-used"; return $?; fi
        if sf_core_referenced "$id"; then sf_fail '损坏归档仍被配置或恢复代次引用，保留现场并停止更新。'; return 1; fi
        mv -T -- "$target" "$SFXH_VAR/cores/.quarantine/$id-$(sf_random)" || return
        sf_sync "$SFXH_VAR/cores" || return
    fi
    # Holding the ID lock proves these are abandoned publication attempts.
    for old in "$SFXH_VAR/cores/.stage-$id-"*; do [[ ! -e $old ]] || sf_remove_tree "$old" || return; done
    stage=$(mktemp -d "$SFXH_VAR/cores/.stage-$id-XXXXXXXX") || return
    sf_core_checkpoint mkdir
    install -m 755 "$binary" "$stage/xray" || return
    sf_core_checkpoint binary
    jq --arg id "$id" --arg hash "$(sf_hash "$stage/xray")" --arg archive "$archive" --arg time "$(sf_now)" \
      '{id:$id,version:(.tag_name|ltrimstr("v")),sha256:$hash,archiveSha256:$archive,downloadedAt:$time,verified:false,release:.html_url}' "$metadata" > "$stage/metadata.json" || return
    chmod 644 "$stage/metadata.json" && chmod 755 "$stage" || return
    sf_core_checkpoint metadata
    sf_core_verify_directory "$stage" "$id" && sf_sync "$stage/xray" && sf_sync "$stage/metadata.json" && sf_sync "$stage" || return
    mv -T -- "$stage" "$target" || return
    stage=''
    sf_sync "$SFXH_VAR/cores" || return
    sf_core_checkpoint published
    sf_core_verify_archive "$id"
)
sf_prune_locked() {
    local work active protected name path n id fd now stamp metadata
    work=$(sf_temp) || return
    active=$(sf_generation) || { sf_remove_tree "$work"; return 1; }
    sf_generation_integrity "$active" || { sf_remove_tree "$work"; return 1; }
    printf '%s\n' "${active##*/}" > "$work/protected"
    [[ ! -f $SFXH_ETC/last-good ]] || cat "$SFXH_ETC/last-good" >> "$work/protected"
    if [[ -f $SFXH_ETC/transaction.json ]]; then
        jq -er '.old,.new' "$SFXH_ETC/transaction.json" >> "$work/protected" || { sf_remove_tree "$work"; return 1; }
    fi
    for protected in generations backups; do
        n=0
        while IFS= read -r name; do
            [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || continue
            path=$SFXH_ETC/$protected/$name
            [[ -d $path && ! -L $path ]] || continue
            if [[ $protected == generations ]] && grep -Fxq "$name" "$work/protected"; then continue; fi
            ((n+=1))
            if [[ $protected == generations ]] && ((n<=10)); then continue; fi
            if [[ $protected == backups ]] && ((n<=5)); then continue; fi
            sf_remove_tree "$path" || { sf_remove_tree "$work"; return 1; }
        done < <(find "$SFXH_ETC/$protected" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
    done
    : > "$work/core-meta.jsonl"
    for metadata in "$SFXH_VAR/cores"/v*/metadata.json; do
        [[ -f $metadata ]] || continue
        jq -c 'select(.verified==true)' "$metadata" >> "$work/core-meta.jsonl" 2>/dev/null || { sf_remove_tree "$work"; return 1; }
    done
    jq -sr 'sort_by(.verifiedAt//.downloadedAt//"")|reverse|.[0:5]|.[].id' "$work/core-meta.jsonl" > "$work/keep-cores" || { sf_remove_tree "$work"; return 1; }
    now=$(date +%s)
    for path in "$SFXH_VAR/cores"/v*; do
        id=${path##*/}
        [[ $id =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16}$ && -d $path && ! -L $path ]] || continue
        grep -Fxq "$id" "$work/keep-cores" && continue
        mkdir -p "$SFXH_VAR/cores/.locks" || return
        exec {fd}>"$SFXH_VAR/cores/.locks/$id.lock" || return
        if flock -n "$fd"; then
            if ! sf_core_referenced "$id"; then
                stamp=$(stat -c %Y "$path/last-used" 2>/dev/null) || stamp=$(stat -c %Y "$path")
                # A one-day grace protects downloaded candidates not yet committed.
                if ((now-stamp>86400)); then sf_remove_tree "$path" || return; fi
            fi
        fi
        exec {fd}>&-
    done
    # Failed unpublished downloads do not consume capacity forever. A matching
    # archive lock and one-day grace exclude current writers and fresh candidates.
    for path in "$SFXH_VAR/cores"/.stage-* "$SFXH_VAR/cores/.quarantine"/v*; do
        [[ -d $path && ! -L $path ]] || continue
        name=${path##*/}
        if [[ $name =~ ^(\.stage-)?(v[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{16})- ]]; then id=${BASH_REMATCH[2]}; else continue; fi
        stamp=$(stat -c %Y "$path") || continue
        ((now-stamp>86400)) || continue
        exec {fd}>"$SFXH_VAR/cores/.locks/$id.lock" || return
        if flock -n "$fd" && ! sf_core_referenced "$id"; then sf_remove_tree "$path" || return; fi
        exec {fd}>&-
    done
    sf_remove_tree "$work"
}
sf_core_prune() (
    sf_recover && sf_lock || return
    trap sf_unlock EXIT
    sf_prune_locked && sf_msg '历史已清理：保留至少5个已验证核心、活动／恢复引用及近期候选。'
)
