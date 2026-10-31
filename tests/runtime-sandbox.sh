#!/usr/bin/env bash
# Disposable GitHub runner ONLY; never install or restart xray.service.
set -euo pipefail
[[ $EUID == 0 && ${GITHUB_ACTIONS:-} == true ]] || { printf 'Requires a disposable GitHub runner.\n' >&2; exit 2; }
[[ $(systemctl show xray.service -p LoadState --value 2>/dev/null || :) == not-found ]] || exit 2
! getent passwd sfxray >/dev/null || exit 2
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1
SFXH_TEST_ROOT=$(mktemp -d /var/lib/sfxh-ci-sandbox.XXXXXXXX); export SFXH_TEST_ROOT
unit=sfxh-ci-runtime.service
created=0
cleanup() {
    systemctl stop "$unit" >/dev/null 2>&1 || :
    rm -f -- "/run/systemd/system/$unit"
    systemctl daemon-reload || :
    if ((created)); then userdel sfxray || :; fi
    [[ $SFXH_TEST_ROOT == /var/lib/sfxh-ci-sandbox.* && ! -L $SFXH_TEST_ROOT ]] && rm -rf -- "$SFXH_TEST_ROOT"
}
trap cleanup EXIT
umask 022
chmod 755 "$SFXH_TEST_ROOT"
# shellcheck disable=SC1090
for module in common model core health transaction manager; do source "$SFXH_CODE/lib/$module.sh"; done
sf_paths; sf_dirs
useradd --system --user-group --home-dir /nonexistent --shell /usr/sbin/nologin sfxray
created=1
sf_manager_copy "$SFXH_CODE" "$SFXH_INSTALL"
# Production ExecStart is outside ProtectHome, as on a real install.
mkdir -p /usr/local/lib/sf-xray-hop
cp -R "$SFXH_INSTALL"/. /usr/local/lib/sf-xray-hop/
core=${SFXH_TEST_CORE:?}
version=$("$core" version); version=${version#Xray }; version=${version%% *}
hash=$(sf_hash "$core"); id="v$version-${hash:0:16}"
mkdir -p "$SFXH_VAR/cores/$id" "$SFXH_ETC/generations/fixture"
install -m 755 "$core" "$SFXH_VAR/cores/$id/xray"
jq -n --arg id "$id" --arg version "$version" --arg hash "$hash" '{id:$id,version:$version,sha256:$hash}' > "$SFXH_VAR/cores/$id/metadata.json"
printf '{}\n' > "$SFXH_ETC/generations/fixture/state.json"
printf '%s\n' "$id" > "$SFXH_ETC/generations/fixture/core-id"
port=$(sf_local_port)
jq -n --argjson port "$port" '{log:{loglevel:"info"},inbounds:[{listen:"127.0.0.1",port:$port,protocol:"http"}],outbounds:[{protocol:"blackhole",settings:{response:{type:"http"}}}]}' > "$SFXH_ETC/generations/fixture/config.json"
(cd "$SFXH_ETC/generations/fixture" && sha256sum state.json config.json core-id > SHA256SUMS)
sf_activate fixture
chown sfxray:sfxray "$SFXH_LOG/core"
# Change only path prefixes, test environment and unit name.
python3 - "$SFXH_CODE/systemd/xray.service" "/run/systemd/system/$unit" "$SFXH_TEST_ROOT" <<'PY'
from pathlib import Path
import sys
src, dest, root = sys.argv[1:]
s = Path(src).read_text().replace("RuntimeDirectory=sf-xray-hop", "RuntimeDirectory=sfxh-ci-runtime")
s = s.replace("ReadWritePaths=/var/log/sf-xray-hop/core", f"ReadWritePaths={root}/var/log/sf-xray-hop/core")
s = s.replace("ReadOnlyPaths=/run/sf-xray-hop", f"ReadOnlyPaths={root}/run/sf-xray-hop")
s = s.replace("Type=simple", f"Type=simple\nEnvironment=SFXH_TEST_MODE=1 SFXH_TEST_ROOT={root}")
Path(dest).write_text(s)
PY
systemctl daemon-reload
systemctl start "$unit"
for attempt in {1..30}; do
    if curl --silent --proxy "http://127.0.0.1:$port" --noproxy '' --max-time 2 -o /dev/null -w '%{http_code}' http://control.sfxh.test/ | grep -qx 403; then break; fi
    sleep 0.2
done
systemctl is-active --quiet "$unit"
status=$(curl --silent --proxy "http://127.0.0.1:$port" --noproxy '' --max-time 2 -o /dev/null -w '%{http_code}' http://control.sfxh.test/)
[[ $status == 403 ]]
main=$(systemctl show "$unit" -p MainPID --value)
actual=''
for child in $(pgrep -P "$main"); do
    if [[ $(readlink "/proc/$child/exe") == "$SFXH_VAR/cores/$id/xray" ]]; then actual=$child; break; fi
done
[[ -n $actual ]]
[[ $(awk '/^Uid:/{print $2}' "/proc/$actual/status") == "$(id -u sfxray)" ]]
[[ $(awk '/^CapEff:/{print $2}' "/proc/$actual/status") == 0000000000000400 ]]
[[ $(awk '/^NoNewPrivs:/{print $2}' "/proc/$actual/status") == 1 ]]
[[ -s $SFXH_LOG/core/core.log ]]
if nsenter -t "$actual" -m -- touch "$SFXH_ETC/forbidden" 2>/dev/null; then exit 1; fi
if nsenter -t "$actual" -m -- touch "$SFXH_RUN/forbidden" 2>/dev/null; then exit 1; fi
systemctl restart "$unit"
status=$(curl --silent --proxy "http://127.0.0.1:$port" --noproxy '' --retry 5 --retry-connrefused --retry-delay 1 --max-time 8 -o /dev/null -w '%{http_code}' http://control.sfxh.test/)
[[ $status == 403 ]]
printf 'PASS real hardened runtime: root preparation, nonroot core, bind capability only, readonly config/runtime, logs, restart\n'
