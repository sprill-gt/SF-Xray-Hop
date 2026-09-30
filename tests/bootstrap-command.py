"""Execute the generated first-stage command with a fake HTTPS downloader only."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='sfxh-command-') as directory:
    root = Path(directory)
    (root / 'bin').mkdir()
    (root / 'tmp').mkdir()
    bootstrap = root / 'install.sh'
    bootstrap.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "$TEST_REPORT"\n')
    downloaded = root / 'downloaded'
    report = root / 'executed'
    curl = root / 'bin/curl'
    curl.write_text('''#!/usr/bin/env bash
while (($#)); do
    if [[ $1 == -o ]]; then dest=$2; shift 2; else shift; fi
done
cp "$TEST_DOWNLOAD" "$dest"
exit "${TEST_DOWNLOAD_STATUS:-0}"
''')
    curl.chmod(0o755)
    env = os.environ | dict(PATH=f'{root / "bin"}:{os.environ["PATH"]}', TMPDIR=str(root / 'tmp'),
                            TEST_DOWNLOAD=str(downloaded), TEST_REPORT=str(report))
    for kind in ('github-release', 'github-commit'):
        (root / 'source.json').write_text(json.dumps(dict(kind=kind, version='0.2.3', prerelease=True,
            commit='a' * 40, archiveSha256='b' * 64)))
        command = subprocess.check_output(['bash', '-c',
            'source "$1/lib/common.sh"; source "$1/lib/manager.sh"; SFXH_CODE=$2; sf_install_command',
            'bash', str(ROOT), str(root)], text=True).strip()
        assert hashlib.sha256(bootstrap.read_bytes()).hexdigest() in command
        for case in ('intact', 'modified', 'empty', 'failed-download'):
            report.unlink(missing_ok=True)
            downloaded.write_bytes(b'' if case == 'empty' else bootstrap.read_bytes() + (b'\n#changed' if case == 'modified' else b''))
            result = subprocess.run(['bash', '-c', command], env=env | dict(TEST_DOWNLOAD_STATUS='22' if case == 'failed-download' else '0'),
                                    capture_output=True, timeout=10)
            if case == 'intact':
                assert result.returncode == 0 and report.exists(), result.stderr
                expected = ['--script-version', '0.2.3', '--allow-pre-script'] if kind == 'github-release' else ['--source-commit', 'a'*40, '--source-sha256', 'b'*64]
                assert report.read_text().splitlines() == expected
            else:
                assert result.returncode != 0 and not report.exists(), (case, result.stderr)
            assert not list((root / 'tmp').iterdir()), 'bootstrap temp file leaked'
            print(f'PASS {kind}: {case}, temporary file cleaned')
print('TOTAL 8 first-stage integrity checks (HTTPS and bootstrap are fixtures)')
