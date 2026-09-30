"""Portable source/docs checks; this does not claim Linux deployment acceptance."""
import os
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("BASH_BIN") or shutil.which("bash") or r"C:\Program Files\Git\bin\bash.exe"
failures = []
readme = (ROOT / 'README.md').read_text(encoding='utf-8')
bootstrap_hash = hashlib.sha256((ROOT / 'install.sh').read_bytes()).hexdigest()
if bootstrap_hash not in readme or 'sha256sum -c -' not in readme:
    failures.append('README bootstrap digest is missing or stale')
version = re.search(r'^SFXH_VERSION=([0-9.]+)$', (ROOT/'lib/common.sh').read_text(), re.M)[1]
if f'SFXH_SOURCE_VERSION={version}\n' not in (ROOT/'install.sh').read_text() or f'--script-version {version} ' not in readme:
    failures.append('manager, bootstrap and README release versions disagree')
shells = list(ROOT.glob("lib/*.sh")) + list(ROOT.glob("tests/*.sh")) + [ROOT / p for p in ("sf-xray-hop", "sfxh", "install.sh")]
for file in shells:
    result = subprocess.run([BASH, "-n", str(file)], capture_output=True, text=True)
    if result.returncode:
        failures.append(f"syntax {file.relative_to(ROOT)}: {result.stderr}")
source_files = shells + list(ROOT.glob("docs/*.md")) + [ROOT / "README.md"]
source_files += list(ROOT.glob("templates/*")) + list(ROOT.glob("data/*")) + list(ROOT.glob("systemd/*"))
source_files += list(ROOT.glob("tests/*.py")) + list(ROOT.glob("tools/*.py"))
for file in source_files:
    if b"\r\n" in file.read_bytes():
        failures.append(f"CRLF: {file.relative_to(ROOT)}")
for file in list(ROOT.glob("docs/*.md")) + [ROOT / "README.md"]:
    if re.search(r"raw\.githubusercontent\.com/sprill-gt/SF-Xray-Hop/main/install\.sh", file.read_text(encoding="utf-8")):
        failures.append(f"floating install command: {file.name}")
    for link in re.findall(r"\]\(([^)]+)\)", file.read_text(encoding="utf-8")):
        if not re.match(r"https?://|#", link):
            target = file.parent / link.split("#")[0]
            if not target.exists():
                failures.append(f"broken link: {file.name}: {link}")
for file in list(ROOT.glob("lib/*.sh")):
    text = file.read_text(encoding="utf-8")
    if re.search(r"^\s*eval\s", text, re.M):
        failures.append(f"eval in {file.name}")
cli = (ROOT / "docs/cli.md").read_text(encoding="utf-8")
for command in ("install", "guide", "view", "status", "doctor", "test", "chain", "rtt", "target", "fingerprint", "core", "self", "node", "logs", "uninstall"):
    if f"sfxh {command}" not in cli:
        failures.append(f"undocumented command: {command}")
for file in source_files:
    value = file.read_text(encoding="utf-8")
    # Real generated ML-KEM material and populated share links must stay in .cache.
    if re.search(r"[A-Za-z0-9_-]{1000,}", value) or re.search(r"vless://[0-9a-fA-F-]{36}@", value):
        failures.append(f"possible credential: {file.relative_to(ROOT)}")
if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"PASS syntax ({len(shells)} scripts), LF, documentation links/commands, secret scan, no eval")
