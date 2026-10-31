#!/usr/bin/env bash
# Host capabilities and sysctl are fixtures; never change the host network stack.
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d "$SFXH_CODE/.cache/bbr.XXXXXXXX"); export SFXH_TEST_ROOT
# shellcheck disable=SC1090
for module in common tune operations; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
trap 'rm -rf -- "$SFXH_TEST_ROOT"' EXIT
# The fixture tests tuning ownership, not flock itself.
case $(uname -s) in MINGW*|MSYS*) sf_lock() { :; } ;; esac
sf_installed() { return 0; }
uname() { printf '6.1.0-fixture\n'; }
systemctl() { :; }
printf 'SF-Xray-Hop\n' > "$SFXH_ETC/owner"
printf '{"project":"SF-Xray-Hop","unrelated":"keep"}\n' > "$SFXH_ETC/ownership.json"
mkdir -p "$SFXH_TEST_ROOT/sysctl" "$SFXH_INSTALL" "$SFXH_BIN" "${SFXH_UNIT%/*}"
printf 'cubic\n' > "$SFXH_TEST_ROOT/sysctl/cc"
printf 'fq_codel\n' > "$SFXH_TEST_ROOT/sysctl/qdisc"
printf 'reno cubic bbr\n' > "$SFXH_TEST_ROOT/sysctl/available"
sysctl() {
    local arg=${*: -1} key value file
    key=${arg%%=*}; value=${arg#*=}
    case "$key" in net.ipv4.tcp_congestion_control) file=cc ;; net.core.default_qdisc) file=qdisc ;; net.ipv4.tcp_available_congestion_control) file=available ;; *) return 1 ;; esac
    if [[ $1 == -n ]]; then cat "$SFXH_TEST_ROOT/sysctl/$file"
    else
        [[ ! -f $SFXH_TEST_ROOT/fail-bbr || $value != bbr ]] || return 1
        printf '%s\n' "$value" > "$SFXH_TEST_ROOT/sysctl/$file"
    fi
}
reject() { if "$@" > "$SFXH_TEST_ROOT/rejected" 2>&1; then printf 'FAIL expected rejection\n'; exit 1; fi; }
sf_bbr_paths
sf_bbr_status
[[ ! -e $SF_BBR_SYSCTL && ! -e $SF_BBR_MODULE ]]
printf 'PASS BBR status does not enable or create configuration\n'
sf_tune_bbr on
[[ $(cat "$SFXH_TEST_ROOT/sysctl/cc") == bbr && $(cat "$SFXH_TEST_ROOT/sysctl/qdisc") == fq ]]
[[ -f $SF_BBR_SYSCTL && -f $SF_BBR_MODULE ]]
jq -e '.tuning.bbr.originalCC=="cubic" and .unrelated=="keep"' "$SF_BBR_OWNER" >/dev/null
reject sf_tune_bbr on
printf 'external change\n' >> "$SF_BBR_SYSCTL"
reject sf_tune_bbr off
[[ $(cat "$SFXH_TEST_ROOT/sysctl/cc") == bbr ]]
sed -i '$d' "$SF_BBR_SYSCTL"
sf_tune_bbr off
[[ $(cat "$SFXH_TEST_ROOT/sysctl/cc") == cubic && $(cat "$SFXH_TEST_ROOT/sysctl/qdisc") == fq_codel ]]
[[ ! -e $SF_BBR_SYSCTL && ! -e $SF_BBR_MODULE ]]
sf_tune_bbr off
printf 'PASS enable, ownership, duplicate refusal, external edits, restoration and repeated off\n'
touch "$SFXH_TEST_ROOT/fail-bbr"
reject sf_tune_bbr on
[[ $(cat "$SFXH_TEST_ROOT/sysctl/cc") == cubic && $(cat "$SFXH_TEST_ROOT/sysctl/qdisc") == fq_codel ]]
[[ ! -e $SF_BBR_SYSCTL && ! -e $SF_BBR_MODULE ]]
jq -e '.tuning.bbr==null' "$SF_BBR_OWNER" >/dev/null
rm "$SFXH_TEST_ROOT/fail-bbr"
printf 'PASS partial runtime failure rolls back and removes owned persistence\n'
printf 'user-owned\n' > "$SF_BBR_SYSCTL"
reject sf_tune_bbr on
grep -qx user-owned "$SF_BBR_SYSCTL"
rm "$SF_BBR_SYSCTL"
sf_tune_bbr on
cp "$SFXH_CODE/systemd/xray.service" "$SFXH_UNIT"
sf_uninstall --yes --keep-data
[[ $(cat "$SFXH_TEST_ROOT/sysctl/cc") == cubic && ! -e $SF_BBR_SYSCTL && ! -e $SF_BBR_MODULE ]]
jq -e '.tuning.bbr==null and .unrelated=="keep"' "$SF_BBR_OWNER" >/dev/null
printf 'PASS foreign files preserved and uninstall restores managed BBR before removing service\n'
