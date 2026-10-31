#!/usr/bin/env bash
# Bootstrap dependency flow only; never runs a real package manager or download.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# Load functions without the entrypoint; all external boundaries below are fake.
# shellcheck disable=SC1090
source <(sed '$d' "$root/install.sh")
mkdir "$work/bin"
export TEST_APT_LOG=$work/apt.log TEST_UPDATE_STATUS=0 TEST_INSTALL_STATUS=0
cat > "$work/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_APT_LOG"
[[ $* != *update* ]] || exit "$TEST_UPDATE_STATUS"
exit "$TEST_INSTALL_STATUS"
EOF
cat > "$work/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $1 != -- ]] || shift
exec "$@"
EOF
chmod +x "$work/bin/apt-get" "$work/bin/sudo"
export PATH="$work/bin:$PATH"
command() {
    if [[ $1 == -v && $2 == jq ]]; then [[ $TEST_HAS_JQ == 1 ]]; else builtin command "$@"; fi
}
sf_boot_fetch() { return 23; }
SFXH_SCRIPT_VERSION=0.2.8
run_case() {
    local expected=$1 rc=0
    : > "$TEST_APT_LOG"
    sf_boot_release "$work" > "$work/stdout" 2> "$work/stderr" || rc=$?
    [[ $rc == "$expected" ]]
}
TEST_HAS_JQ=0
run_case 23
[[ $(wc -l < "$TEST_APT_LOG") == 2 ]]
sed -n '1p' "$TEST_APT_LOG" | grep -q 'APT::Update::Error-Mode=any update$'
sed -n '2p' "$TEST_APT_LOG" | grep -q 'install -y --no-install-recommends jq$'
printf 'PASS missing jq refreshes indexes before installation\n'
TEST_UPDATE_STATUS=100
run_case 1
[[ $(wc -l < "$TEST_APT_LOG") == 1 ]]
grep -q 'APT 索引刷新失败' "$work/stderr"
printf 'PASS failed index refresh stops before package install and release lookup\n'
TEST_UPDATE_STATUS=0 TEST_INSTALL_STATUS=100
run_case 1
[[ $(wc -l < "$TEST_APT_LOG") == 2 ]]
grep -q '无法安装 jq' "$work/stderr"
printf 'PASS failed jq installation stops before release lookup\n'
TEST_HAS_JQ=1
run_case 23
[[ ! -s $TEST_APT_LOG ]]
printf 'PASS existing jq avoids all APT operations\n'
(
    sf_boot_download() { [[ $SFXH_SCRIPT_VERSION == "$SFXH_SOURCE_VERSION" && $SFXH_SCRIPT_PRE == 1 ]]; }
    sf_boot_main --rc
)
printf 'PASS short RC option selects the bootstrap version and allows prerelease\n'
printf 'TOTAL 5 bootstrap dependency/RC checks (APT and HTTP mocked)\n'
