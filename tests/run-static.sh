#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
python3 tests/check.py
python3 tests/privacy.py
shellcheck -S warning -e SC1090,SC2034 sf-xray-hop sfxh install.sh lib/*.sh tests/*.sh
python3 tests/bootstrap-command.py
bash tests/bootstrap-dependencies.sh
bash tests/releases-auto.sh
bash tests/asset-resume.sh
bash tests/argon-review.sh
