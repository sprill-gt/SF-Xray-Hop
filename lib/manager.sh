#!/usr/bin/env bash
sf_source_info() {
    local root=${1:-$SFXH_CODE}
    if [[ -f $root/source.json ]] && jq -e '
        (.kind=="github-commit" or .kind=="github-release") and (.commit|test("^[a-f0-9]{40}$")) and
        (.archiveSha256|test("^[a-f0-9]{64}$")) and (.version|test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
        ' "$root/source.json" >/dev/null 2>&1; then cat "$root/source.json"
    else printf '{"kind":"package"}\n'; fi
}
sf_install_command() {
    local source commit hash pre=''
    source=$(sf_source_info) || return
    if [[ $(jq -r .kind <<< "$source") == github-release ]]; then
        [[ $(jq -r '.prerelease // false' <<< "$source") != true ]] || pre=' --allow-pre-script'
        printf '(set -o pipefail; curl -fsSL https://raw.githubusercontent.com/sprill-gt/SF-Xray-Hop/%s/install.sh | bash -s -- --script-version %s%s)\n' "$(jq -r .commit <<< "$source")" "$(jq -r .version <<< "$source")" "$pre"
        return 0
    fi
    commit=$(jq -r '.commit//empty' <<< "$source"); hash=$(jq -r '.archiveSha256//empty' <<< "$source")
    [[ -n $commit && -n $hash ]] || return 1
    printf '(set -o pipefail; curl -fsSL https://raw.githubusercontent.com/sprill-gt/SF-Xray-Hop/%s/install.sh | bash -s -- --source-commit %s --source-sha256 %s)\n' "$commit" "$commit" "$hash"
}
sf_manager_copy() {
    local source=$1 dest=$2 part
    mkdir -p "$dest" || return
    for part in lib templates data systemd docs; do cp -R -- "$source/$part" "$dest/" || return; done
    for part in sf-xray-hop sfxh install.sh; do install -m 755 "$source/$part" "$dest/$part" || return; done
    install -m 644 "$source/README.md" "$dest/README.md" || return
    [[ ! -f $source/source.json ]] || install -m 644 "$source/source.json" "$dest/source.json" || return
    [[ -z $(find "$dest" -type l -print -quit) ]] || { sf_fail '管理程序包不得含符号链接。'; return 1; }
    chown -R root:root "$dest" && chmod -R go-w "$dest" || return
    find "$dest" -type d -exec chmod 755 {} + || return
    find "$dest/lib" "$dest/templates" "$dest/data" "$dest/systemd" "$dest/docs" -type f -exec chmod 644 {} +
}
sf_manager_verify() {
    local root=$1 file
    [[ -f $root/MANAGER-SHA256SUMS ]] || return 1
    (cd "$root" && sha256sum --check --status MANAGER-SHA256SUMS) || return
    for file in "$root/sf-xray-hop" "$root/sfxh" "$root/install.sh" "$root/lib/"*.sh; do bash -n "$file" || return; done
}
sf_manager_stage() (
    local source=$1 stage='' id version abandoned
    sf_lock || return
    [[ ! -L $SFXH_INSTALL && ! -L $SFXH_INSTALL/releases ]] || { sf_fail '管理器安装目录不是受支持的普通目录。'; return 1; }
    mkdir -p "$SFXH_INSTALL/releases" || return
    chown root:root "$SFXH_INSTALL" "$SFXH_INSTALL/releases" && chmod 755 "$SFXH_INSTALL" "$SFXH_INSTALL/releases" || return
    # All writers hold the same lock, including nested installs/updates. A killed
    # writer cannot leave an unbounded collection of private staging copies.
    trap '[[ -z $stage ]] || rm -rf -- "$stage"; sf_unlock' EXIT
    trap 'exit 130' INT TERM HUP
    for abandoned in "$SFXH_INSTALL/releases/".stage-*; do
        [[ -d $abandoned && ! -L $abandoned && $(realpath -m "$abandoned") == "$abandoned" ]] || continue
        rm -rf -- "$abandoned" || return
    done
    stage=$(mktemp -d "$SFXH_INSTALL/releases/.stage-XXXXXXXX") || return
    sf_manager_copy "$source" "$stage" || return
    version=$(sed -nE 's/^SFXH_VERSION=([0-9.]+)$/\1/p' "$stage/lib/common.sh")
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    (cd "$stage" && find . -type f ! -name MANAGER-SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > MANAGER-SHA256SUMS) || return
    id="v$version-$(sf_hash "$stage/MANAGER-SHA256SUMS" | cut -c1-16)"
    sf_manager_verify "$stage" && sf_sync "$stage" || return
    if [[ -e $SFXH_INSTALL/releases/$id ]]; then
        [[ ! -L $SFXH_INSTALL/releases/$id ]] && sf_manager_verify "$SFXH_INSTALL/releases/$id" &&
          cmp -s "$stage/MANAGER-SHA256SUMS" "$SFXH_INSTALL/releases/$id/MANAGER-SHA256SUMS" || return
    else
        mv -T "$stage" "$SFXH_INSTALL/releases/$id" || return
        stage=''; sf_sync "$SFXH_INSTALL/releases" || return
    fi
    printf '%s\n' "$SFXH_INSTALL/releases/$id"
)
sf_manager_checkpoint() { :; }
sf_manager_activate() {
    local target=$1 previous=${2:-} temp
    [[ $target == "$SFXH_INSTALL/releases/"* && $(realpath -m "$target") == "$target" ]] || return 2
    sf_manager_verify "$target" || return
    if [[ -n $previous && $previous != "$target" ]]; then
        temp=$SFXH_INSTALL/.previous-manager.new
        ln -sfn -- "$previous" "$temp" && mv -Tf -- "$temp" "$SFXH_INSTALL/previous-manager" || return
    fi
    temp=$SFXH_INSTALL/.entry.new
    ln -sfn -- "$target/sf-xray-hop" "$temp" || return
    sf_manager_checkpoint before-switch
    # Replace a regular legacy entry or a release symlink in one rename. Runtime
    # modules are always loaded from the entry's resolved immutable directory.
    mv -Tf -- "$temp" "$SFXH_INSTALL/sf-xray-hop" && sf_sync "$SFXH_INSTALL"
}
sf_upgrade_manager() ( sf_manager_switch "${1:-$SFXH_CODE}"; )
