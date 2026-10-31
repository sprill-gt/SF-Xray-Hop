"""Execute generated short Bash commands with fake HTTPS; no server changes."""
import os
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='sfxh-command-') as directory:
    root = Path(directory)
    (root / 'bin').mkdir()
    report = root / 'executed'
    curl = root / 'bin/curl'
    curl.write_text('''#!/usr/bin/env bash
printf '%s\\n' "$@" > "$TEST_URL_REPORT"
printf 'printf "%%s\\n" "$@" > "$TEST_REPORT"\\n'
''')
    curl.chmod(0o755)
    env = os.environ | dict(PATH=f'{root / "bin"}:{os.environ["PATH"]}',
                            TEST_REPORT=str(report), TEST_URL_REPORT=str(root / 'url'))
    for kind in ('github-release', 'github-commit'):
        (root / 'source.json').write_text(json.dumps(dict(kind=kind, version='0.2.3', prerelease=True,
            commit='a' * 40, archiveSha256='b' * 64)))
        command = subprocess.check_output(['bash', '-c',
            'source "$1/lib/common.sh"; source "$1/lib/manager.sh"; SFXH_CODE=$2; sf_install_command',
            'bash', str(ROOT), str(root)], text=True).strip()
        assert command.startswith('bash <(curl -fsSL https://')
        assert '/'+ 'a'*40 + '/install.sh' in command
        subprocess.run(['bash', '-c', command], env=env, capture_output=True, check=True, timeout=10)
        expected = ['--script-version', '0.2.3', '--allow-pre-script'] if kind == 'github-release' else ['--source-commit', 'a'*40, '--source-sha256', 'b'*64]
        assert report.read_text().splitlines() == expected
        assert (root / 'url').read_text().splitlines() == ['-fsSL', 'https://raw.githubusercontent.com/sprill-gt/SF-Xray-Hop/' + 'a'*40 + '/install.sh']
        print(f'PASS {kind}: short Bash command pins commit and preserves arguments')
print('TOTAL 2 short Bash command checks (HTTPS and bootstrap are fixtures)')
