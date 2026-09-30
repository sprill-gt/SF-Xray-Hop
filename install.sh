#!/usr/bin/env bash
# Standalone HTTPS bootstrap and offline source entrypoint. No Git dependency.
set -uo pipefail
umask 077
SFXH_SOURCE_VERSION=0.2.6
SFXH_SOURCE_COMMIT=''
SFXH_SOURCE_SHA256=''
SFXH_BOOT_ACTION=install
SFXH_SCRIPT_VERSION=''
SFXH_SCRIPT_PRE=0
SFXH_SOURCE_KIND=github-commit
SFXH_SOURCE_PRERELEASE=false

sf_boot_fetch() {
    curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 --retry 2 "$1" -o "$2"
}
sf_boot_release() {
    local work=$1 page count version name digest url commit
    command -v curl >/dev/null || { printf '正式发行入口需要 curl。\n' >&2; return 2; }
    if ! command -v jq >/dev/null; then
        printf '准备发行清单解析依赖 jq（不升级系统）。\n' >&2
        local -a apt=(apt-get -o DPkg::Lock::Timeout=60 install -y jq)
        if ((EUID!=0)); then apt=(sudo -- "${apt[@]}"); fi
        "${apt[@]}" >&2 || { printf '无法安装 jq，请检查 APT 锁、软件源或权限后重试。\n' >&2; return 1; }
    fi
    if [[ -n $SFXH_SCRIPT_VERSION ]]; then
        [[ $SFXH_SCRIPT_VERSION =~ ^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$ ]] || return 2
        sf_boot_fetch "https://api.github.com/repos/sprill-gt/SF-Xray-Hop/releases/tags/v$SFXH_SCRIPT_VERSION" "$work/release.json" || return
    else
        [[ $SFXH_SCRIPT_PRE == 0 ]] || { printf '测试脚本需要明确 --script-version。\n' >&2; return 2; }
        : > "$work/releases.jsonl"
        for ((page=1;page<=100;page++)); do
            sf_boot_fetch "https://api.github.com/repos/sprill-gt/SF-Xray-Hop/releases?per_page=100&page=$page" "$work/page.json" || return
            jq -e 'type=="array"' "$work/page.json" >/dev/null || return
            count=$(jq length "$work/page.json"); jq -c '.[]' "$work/page.json" >> "$work/releases.jsonl" || return
            ((count==100)) || break
        done
        ((page<=100)) || return 1
        jq -s '[.[]|select(.draft==false and .prerelease==false and (.tag_name|test("^v[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}$")))]|
          sort_by(.tag_name|ltrimstr("v")|split(".")|map(tonumber))|last' "$work/releases.jsonl" > "$work/release.json" || return
    fi
    jq -e --argjson pre "$SFXH_SCRIPT_PRE" '.draft==false and (.published_at|type)=="string" and
      (.prerelease==false or ($pre==1 and .prerelease==true)) and (.tag_name|test("^v[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}$"))' "$work/release.json" >/dev/null || {
        printf '尚无符合要求的项目正式发行版；不会自动改装 main 或实验版本。\n' >&2; return 1;
    }
    version=$(jq -r '.tag_name|ltrimstr("v")' "$work/release.json")
    [[ -z $SFXH_SCRIPT_VERSION || $version == "$SFXH_SCRIPT_VERSION" ]] || return 1
    url=$(jq -er '[.assets[]|select(.name=="manifest.json")]|select(length==1)|.[0].browser_download_url' "$work/release.json") || return
    [[ $url == "https://github.com/sprill-gt/SF-Xray-Hop/releases/download/v$version/manifest.json" ]] || return 1
    sf_boot_fetch "$url" "$work/manifest.json" || return
    [[ $(wc -c < "$work/manifest.json") -le 16384 ]] || return 1
    digest=$(jq -r '.assets[]|select(.name=="manifest.json")|.digest//""' "$work/release.json")
    [[ -z $digest || $digest == "sha256:$(sha256sum "$work/manifest.json" | cut -d' ' -f1)" ]] || return 1
    jq -e --arg v "$version" '.schemaVersion==1 and .project=="SF-Xray-Hop" and .version==$v and
      (.commit|test("^[a-f0-9]{40}$")) and .archive.name==("SF-Xray-Hop-"+$v+".tar.gz") and
      (.archive.sha256|test("^[a-f0-9]{64}$")) and (.archive.size|type=="number" and floor==. and .>0 and .<=16777216)' "$work/manifest.json" >/dev/null || return
    commit=$(jq -r .commit "$work/manifest.json")
    sf_boot_fetch "https://api.github.com/repos/sprill-gt/SF-Xray-Hop/commits/v$version" "$work/commit.json" || return
    [[ $(jq -r .sha "$work/commit.json") == "$commit" ]] || return 1
    name=$(jq -r .archive.name "$work/manifest.json")
    SFXH_RELEASE_URL=$(jq -er --arg name "$name" '[.assets[]|select(.name==$name)]|select(length==1)|.[0].browser_download_url' "$work/release.json") || return
    [[ $SFXH_RELEASE_URL == "https://github.com/sprill-gt/SF-Xray-Hop/releases/download/v$version/$name" ]] || return 1
    SFXH_SOURCE_VERSION=$version; SFXH_SOURCE_COMMIT=$commit
    SFXH_SOURCE_SHA256=$(jq -r .archive.sha256 "$work/manifest.json"); SFXH_SOURCE_KIND=github-release
    SFXH_SOURCE_PRERELEASE=$(jq .prerelease "$work/release.json")
}

sf_boot_run() {
    local root=$1
    shift
    local -a command=(bash "$root/sf-xray-hop")
    if [[ $SFXH_BOOT_ACTION == upgrade ]]; then command+=(internal upgrade-manager);
    elif (($#)); then command+=(install "$@");
    elif [[ $root == /usr/local/lib/sf-xray-hop ]]; then command+=(menu);
    else command+=(internal setup); fi
    if ((EUID != 0)); then
        command -v sudo >/dev/null || { printf '请以 root 登录后重新执行安装命令，或先安装 sudo。\n' >&2; return 2; }
        command=(sudo -- "${command[@]}")
    fi
    if [[ $SFXH_BOOT_ACTION == install ]] && (($# == 0)); then
        if [[ -t 0 ]]; then "${command[@]}"
        elif ( : </dev/tty ) 2>/dev/null; then "${command[@]}" </dev/tty
        else "${command[@]}"; fi
    else
        "${command[@]}"
    fi
}

sf_boot_download() (
    local work archive root tool version url prefix digest
    for tool in tar gzip mktemp sha256sum; do
        command -v "$tool" >/dev/null || { printf '缺少下载所需工具：%s；请安装后重试。\n' "$tool" >&2; return 2; }
    done
    work=$(mktemp -d "${TMPDIR:-/tmp}/sf-xray-hop-install.XXXXXXXX") || return
    trap 'rm -rf -- "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [[ -z $SFXH_SOURCE_COMMIT ]]; then sf_boot_release "$work" || return; fi
    [[ $SFXH_SOURCE_COMMIT =~ ^[a-f0-9]{40}$ && $SFXH_SOURCE_SHA256 =~ ^[a-f0-9]{64}$ ]] || return 2
    url=https://codeload.github.com/sprill-gt/SF-Xray-Hop/tar.gz/$SFXH_SOURCE_COMMIT
    prefix="SF-Xray-Hop-$SFXH_SOURCE_COMMIT/"
    if [[ $SFXH_SOURCE_KIND == github-release ]]; then url=$SFXH_RELEASE_URL; prefix=SF-Xray-Hop/; fi
    archive=$work/source.tar.gz
    root=$work/source
    printf 'SF-Xray-Hop %s\n源码提交：%s\n正在下载固定版本并核对 SHA256……\n' "$SFXH_SOURCE_VERSION" "$SFXH_SOURCE_COMMIT" >&2
    if command -v curl >/dev/null; then
        curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 --retry 2 --output "$archive" "$url" || {
            printf 'GitHub 源码下载失败，未启动安装，请检查网络后重试。\n' >&2; return 1;
        }
    elif command -v wget >/dev/null; then
        wget --https-only --timeout=30 --tries=3 -qO "$archive" "$url" || {
            printf 'GitHub 源码下载失败，未启动安装，请检查网络后重试。\n' >&2; return 1;
        }
    else printf '需要 curl 或 wget 下载脚本。\n' >&2; return 2; fi
    printf '%s  %s\n' "$SFXH_SOURCE_SHA256" "$archive" | sha256sum --check --status || {
        printf '管理程序源码摘要不匹配，未启动安装。\n' >&2; return 1;
    }
    if [[ $SFXH_SOURCE_KIND == github-release ]]; then
        digest=$(jq -r --arg name "SF-Xray-Hop-$SFXH_SOURCE_VERSION.tar.gz" '.assets[]|select(.name==$name)|.digest//""' "$work/release.json")
        [[ -z $digest || $digest == "sha256:$SFXH_SOURCE_SHA256" ]] || return 1
        [[ $(wc -c < "$archive") == "$(jq -r .archive.size "$work/manifest.json")" ]] || return 1
    fi
    (gzip -dc "$archive" | head -c 67108865 > "$work/source.tar") 2>/dev/null || return 1
    [[ $(wc -c < "$work/source.tar") -le 67108864 ]] || return 1
    tar -tzf "$archive" > "$work/members" 2>/dev/null && tar -tvzf "$archive" > "$work/types" 2>/dev/null || {
        printf '源码下载不完整或不是有效压缩包，未启动安装。\n' >&2; return 1;
    }
    # Official archive only: one expected root, no traversal, symlinks or devices.
    if ! awk -v prefix="$prefix" 'BEGIN {ok=1} index($0,prefix)!=1 || /(^|\/)\.\.(\/|$)/ || seen[$0]++ {ok=0} END {exit !ok}' "$work/members" ||
       grep -qEv '^[-d]' "$work/types"; then
        printf '源码包目录结构异常，未启动安装。\n' >&2; return 1
    fi
    mkdir "$root" || return
    tar -xzf "$archive" -C "$root" --strip-components=1 --no-same-owner --no-same-permissions || return
    [[ -f $root/sf-xray-hop && -f $root/lib/ui.sh && -f $root/lib/install.sh ]] || {
        printf '源码包缺少必要模块，未启动安装。\n' >&2; return 1;
    }
    version=$(sed -nE 's/^SFXH_VERSION=([0-9.]+)$/\1/p' "$root/lib/common.sh")
    [[ $version == "$SFXH_SOURCE_VERSION" ]] || { printf '源码版本与安装入口不匹配，未执行管理程序。\n' >&2; return 1; }
    printf '{"kind":"%s","version":"%s","commit":"%s","archiveSha256":"%s","prerelease":%s}\n' \
      "$SFXH_SOURCE_KIND" "$version" "$SFXH_SOURCE_COMMIT" "$SFXH_SOURCE_SHA256" "$SFXH_SOURCE_PRERELEASE" > "$root/source.json"
    sf_boot_run "$root" "$@"
)

sf_boot_main() {
    local root='' source_path=${BASH_SOURCE[0]:-}
    if [[ ${1:-} == --help || ${1:-} == -h ]]; then
        printf 'SF-Xray-Hop 一键安装\n默认安装项目最新正式 Release；无正式版时明确停止。\n测试发行：--script-version 版本 --allow-pre-script\n固定源码：--source-commit 完整SHA --source-sha256 压缩包摘要\n--upgrade-manager：只升级管理脚本；安装默认0-RTT。\n'
        return 0
    fi
    local -a args=()
    while (($#)); do
        case "$1" in
            --source-commit|--source-sha256)
                [[ $# -ge 2 ]] || return 2
                if [[ $1 == --source-commit ]]; then SFXH_SOURCE_COMMIT=$2; else SFXH_SOURCE_SHA256=$2; fi
                shift 2 ;;
            --upgrade-manager) SFXH_BOOT_ACTION=upgrade; shift ;;
            --script-version) [[ $# -ge 2 ]] || return 2; SFXH_SCRIPT_VERSION=${2#v}; shift 2 ;;
            --allow-pre-script) SFXH_SCRIPT_PRE=1; shift ;;
            --) shift; args+=("$@"); break ;;
            *) args+=("$1"); shift ;;
        esac
    done
    set -- "${args[@]}"
    [[ (-z $SFXH_SOURCE_COMMIT && -z $SFXH_SOURCE_SHA256) || (-n $SFXH_SOURCE_COMMIT && -n $SFXH_SOURCE_SHA256) ]] || {
        printf '固定源码提交和 SHA256 必须同时提供。\n' >&2; return 2;
    }
    [[ -z $SFXH_SOURCE_COMMIT || (-z $SFXH_SCRIPT_VERSION && $SFXH_SCRIPT_PRE == 0) ]] || return 2
    [[ $SFXH_BOOT_ACTION != upgrade || $# == 0 ]] || { printf '管理器升级不接受核心或节点安装参数。\n' >&2; return 2; }
    # A pipe has no source path; process substitution has /dev/fd/N, not a checkout.
    if [[ -f $source_path && $source_path != /dev/fd/* && $source_path != /proc/* ]]; then
        root=$(cd -- "$(dirname -- "$source_path")" && pwd -P) || return
    fi
    if [[ -z $SFXH_SOURCE_COMMIT && -z $SFXH_SCRIPT_VERSION && $SFXH_SCRIPT_PRE == 0 && -n $root && -f $root/sf-xray-hop && -f $root/lib/install.sh ]]; then
        sf_boot_run "$root" "$@"
    elif [[ -z $SFXH_SOURCE_COMMIT && $SFXH_BOOT_ACTION == install ]] && (($# == 0)) && [[ -x /usr/local/lib/sf-xray-hop/sf-xray-hop ]]; then
        sf_boot_run /usr/local/lib/sf-xray-hop
    else
        sf_boot_download "$@"
    fi
}
sf_boot_main "$@"
