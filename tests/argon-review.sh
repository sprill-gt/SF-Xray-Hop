#!/usr/bin/env bash
# Local fixture boundaries for the reviewed changes; no external network.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
SFXH_CODE=$root
# shellcheck disable=SC1090
for module in common install model core; do source "$root/lib/$module.sh"; done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# A PATH-level date failure proves timestamps no longer execute external date.
date() { return 99; }
[[ $(TZ=Pacific/Honolulu sf_now) =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
printf 'PASS builtin UTC timestamp\n'
curl() {
    local url=${*: -1}
    case "$url" in
        *ipify*) [[ $SCENARIO != outage ]] || return 28; printf '%s\n' "$IP_A" ;;
        *icanhazip*) printf '%s\r\n' "$IP_B" ;;
        *cloudflare*) printf 'fl=fixture\nip=%s\n' "$IP_C" ;;
        *) return 1 ;;
    esac
}
SCENARIO=outage IP_A=8.8.8.8 IP_B=1.1.1.1 IP_C=1.1.1.1
[[ $(sf_detect_address) == 1.1.1.1 ]]
SCENARIO=normal IP_A=8.8.8.8 IP_B=1.1.1.1 IP_C=9.9.9.9
if sf_detect_address; then exit 1; fi
for ip in 127.0.0.1 10.0.0.1 100.100.100.200 169.254.169.254 192.0.2.1 198.51.100.1 203.0.113.1 224.1.1.1 0.0.0.0 256.1.1.1; do
    IP_A=$ip IP_B=$ip IP_C=$ip
    if sf_detect_address; then exit 1; fi
done
printf 'PASS address quorum tolerates one outage and rejects disagreement/special addresses\n'
curl() { printf '%s\n' "$@" > "$work/args"; if [[ $1 == --header ]]; then cat > "$work/header"; else : > "$work/header"; fi; }
SFXH_GITHUB_TOKEN=fixture_token
sf_github_curl https://api.github.com/repos/XTLS/Xray-core/tags --silent
! grep -q fixture_token "$work/args"
grep -qx 'Authorization: Bearer fixture_token' "$work/header"
sf_github_curl https://github.com/XTLS/Xray-core/releases/download/v1/a --silent
[[ ! -s $work/header ]]
SFXH_GITHUB_TOKEN=$'bad\nheader'
if sf_github_curl https://api.github.com/repos/XTLS/Xray-core/tags; then exit 1; fi
unset SFXH_GITHUB_TOKEN
printf 'PASS token stays out of process arguments, assets, and malformed headers\n'
# Use the existing generated unit fixture, which remains under the private cache.
if [[ -n ${SFXH_TEST_PROFILE:-} ]]; then
    sf_export_client_config "$SFXH_TEST_PROFILE" "$work/export.json"
    sf_client_config "$SFXH_TEST_PROFILE" "$work/probe.json" 19999
    jq -e '.inbounds|length==1 and .[0].port==19999' "$work/probe.json" >/dev/null
    jq -e '.inbounds|length==2 and any(.[];.protocol=="socks" and .settings.udp==true and .listen=="127.0.0.1" and .port==10808)' "$work/export.json" >/dev/null
    sf_core_test "$SFXH_TEST_CORE" "$work/export.json" "$work/config-test.log"
    printf 'PASS exported SOCKS UDP plus HTTP config validates; internal port remains isolated\n'
fi
