"""Check shipped bytes, imports and paths; not an installation/systemd test."""
import hashlib
from pathlib import Path, PurePosixPath
import re
import tarfile

root = Path(__file__).resolve().parents[1]
version = re.search(r'^SFXH_VERSION=([0-9.]+)$', (root/'lib/common.sh').read_text(), re.M)[1]
archive = root/'artifacts'/f'SF-Xray-Hop-{version}.tar.gz'
assert hashlib.sha256(archive.read_bytes()).hexdigest() == (archive.with_name(archive.name+'.sha256')).read_text().split()[0]
with tarfile.open(archive) as tar:
    files = {}
    for member in tar:
        path = PurePosixPath(member.name)
        assert not path.is_absolute() and '..' not in path.parts and path.parts[0] == 'SF-Xray-Hop'
        assert member.isfile() and not member.issym() and not member.islnk()
        name = path.relative_to('SF-Xray-Hop').as_posix()
        assert name not in files and not any(part in ('.cache', '.git', 'artifacts', '__pycache__') for part in path.parts)
        files[name] = tar.extractfile(member).read()
        assert files[name] == (root/name).read_bytes() and b'\r\n' not in files[name]
        assert member.mode == (0o755 if name.endswith('.sh') or name in ('sf-xray-hop','sfxh') else 0o644)
    for name in ('lib/core-safety-worker.sh', 'data/core-safety.json', 'templates/model.jq', 'systemd/xray.service', 'install.sh'):
        assert name in files, f'missing runtime dependency: {name}'
    for source in (files['sf-xray-hop'].decode(),):
        modules = re.search(r'for module in (.*?); do', source)[1].split()
        assert all(f'lib/{module}.sh' in files for module in modules)
print(f'PASS distribution digest, {len(files)} unique regular files, source bytes, modes, LF and runtime dependencies')
