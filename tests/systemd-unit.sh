#!/usr/bin/env bash
# Offline static analysis only. Does not install or start the formal service.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/before" "$work/after"
cp "$root/tests/fixtures/xray-0.2.9.service" "$work/before/xray.service"
cp "$root/systemd/xray.service" "$work/after/xray.service"
systemd-analyze verify "$work/after/xray.service"
if systemd-analyze --help | grep -q -- --offline; then
    LC_ALL=C systemd-analyze security --offline=yes --no-pager "$work/before/xray.service" > "$work/before.txt"
    LC_ALL=C systemd-analyze security --offline=yes --no-pager "$work/after/xray.service" > "$work/after.txt"
    before=$(sed -nE 's/.*Overall exposure level.*: ([0-9.]+).*/\1/p' "$work/before.txt")
    after=$(sed -nE 's/.*Overall exposure level.*: ([0-9.]+).*/\1/p' "$work/after.txt")
    python3 - "$before" "$after" <<'PY'
import sys
before, after = map(float, sys.argv[1:])
assert after < before, (before, after)
print(f"PASS offline systemd exposure {before} -> {after}; not runtime acceptance")
PY
    systemd-analyze security --offline=yes --no-pager --threshold=15 "$work/after/xray.service" >/dev/null
else
    printf 'SKIP offline scoring: systemd version has no --offline; verify only\n'
fi
