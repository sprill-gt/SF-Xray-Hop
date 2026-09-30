"""Create an LF-only source distribution from an explicit allowlist; never .cache."""
import gzip
import hashlib
from pathlib import Path
import re
import tarfile
import argparse
import json
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--release-commit', help='Generate manifest.json only from this clean HEAD commit')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
if args.release_commit:
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()
    if not re.fullmatch(r'[a-f0-9]{40}', args.release_commit) or head != args.release_commit or dirty:
        raise SystemExit('Release manifest requires the exact clean HEAD commit; do not label working files as a committed release.')
FILES = [ROOT / n for n in ("README.md", "sf-xray-hop", "sfxh", "install.sh", ".gitattributes")]
for directory in ("lib", "templates", "data", "systemd", "docs", "tests", "tools"):
    FILES.extend(p for p in (ROOT / directory).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
version = re.search(r"^SFXH_VERSION=([0-9.]+)$", (ROOT / "lib/common.sh").read_text(encoding="utf-8"), re.M)[1]
out = ROOT / "artifacts" / f"SF-Xray-Hop-{version}.tar.gz"
out.parent.mkdir(exist_ok=True)
for path in FILES:
    if b"\r\n" in path.read_bytes():
        raise ValueError(f"CRLF is not allowed: {path.relative_to(ROOT)}")
with out.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as gz:
    with tarfile.open(fileobj=gz, mode="w") as archive:
        for path in sorted(FILES):
            relative = path.relative_to(ROOT)
            info = archive.gettarinfo(str(path), arcname=f"SF-Xray-Hop/{relative.as_posix()}")
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = "root"
            info.mode = 0o755 if path.suffix == ".sh" or path.name in ("sf-xray-hop", "sfxh") else 0o644
            with path.open("rb") as source:
                archive.addfile(info, source)
digest = hashlib.sha256(out.read_bytes()).hexdigest()
(out.parent / (out.name + ".sha256")).write_text(f"{digest}  {out.name}\n", encoding="utf-8", newline="\n")
if args.release_commit:
    manifest = dict(schemaVersion=1, project='SF-Xray-Hop', version=version, commit=args.release_commit,
                    archive=dict(name=out.name, sha256=digest, size=out.stat().st_size))
    (out.parent / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8', newline='\n')
else:
    # A development rebuild must not leave an older commit's release manifest
    # next to new archive bytes.
    (out.parent / 'manifest.json').unlink(missing_ok=True)
print(f"Created {out.name}: {len(FILES)} files, SHA256 {digest}")
