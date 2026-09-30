"""Linux/root bootstrap integration with fake HTTPS download and fake manager; no VPS install."""
import io
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

if sys.platform != 'linux' or os.geteuid() != 0:
    raise SystemExit('Run on Linux as root; only temporary fixtures are modified.')
import fcntl
import pty
import termios

SOURCE = Path(__file__).resolve().parents[1] / 'install.sh'
COMMIT = 'a' * 40
PREFIX = f'SF-Xray-Hop-{COMMIT}/'
MANAGER = b'''#!/usr/bin/env bash
printf '%s\\n' "$@" > "$SF_BOOT_TEST_REPORT"
if [[ -t 0 ]]; then
    IFS= read -r choice
    printf 'tty:%s\\n' "$choice" >> "$SF_BOOT_TEST_REPORT"
fi
exit "${SF_BOOT_TEST_EXIT:-0}"
'''
count = 0


def check(condition, label):
    global count
    assert condition, label
    count += 1
    print(f'PASS {count:02d} {label}', flush=True)


with tempfile.TemporaryDirectory(prefix='sfxh-bootstrap-tests-') as directory:
    root = Path(directory)
    env = os.environ.copy()
    (root / 'bin').mkdir()
    (root / 'tmp').mkdir()
    curl = root / 'bin/curl'
    curl.write_text('''#!/usr/bin/env bash
[[ ${SF_BOOT_TEST_DOWNLOAD_FAILURE:-0} == 0 ]] || exit 22
while (($#)); do
    if [[ $1 == --output || $1 == -o ]]; then dest=$2; shift 2; else shift; fi
done
cp "$SF_BOOT_TEST_ARCHIVE" "$dest"
''')
    curl.chmod(0o755)
    report = root / 'report'
    archive = root / 'source.tar.gz'
    env.update(PATH=f'{root / "bin"}:{env["PATH"]}', TMPDIR=str(root / 'tmp'),
               SF_BOOT_TEST_ARCHIVE=str(archive), SF_BOOT_TEST_REPORT=str(report))

    def pack(extra=None, version='0.2.5'):
        with tarfile.open(archive, 'w:gz') as output:
            for name, data in [('sf-xray-hop', MANAGER), ('lib/ui.sh', b''), ('lib/install.sh', b''),
                               ('lib/common.sh', f'SFXH_VERSION={version}\n'.encode())]:
                info = tarfile.TarInfo(PREFIX + name)
                info.size = len(data)
                output.addfile(info, io.BytesIO(data))
            if extra:
                output.addfile(extra)

    def pins():
        return ['--source-commit', COMMIT, '--source-sha256', hashlib.sha256(archive.read_bytes()).hexdigest()]

    def run(args=(), extra_env=None, fixed=None):
        report.unlink(missing_ok=True)
        result = subprocess.run(['bash', '-s', '--', *(pins() if fixed is None else fixed), *args], input=SOURCE.read_bytes(), capture_output=True,
                                env=env | (extra_env or {}), start_new_session=True, timeout=15)
        assert not list((root / 'tmp').iterdir()), 'temporary source left behind'
        return result

    pack()
    result = run(['--rtt', '1', '--name', '节点 空格'])
    check(result.returncode == 0 and report.read_text().splitlines() == ['install', '--rtt', '1', '--name', '节点 空格'],
          'pipe bootstrap downloads full source, preserves arguments and cleans temporary files')
    result = run(['--rtt', '1'], {'SF_BOOT_TEST_DOWNLOAD_FAILURE': '1'})
    check(result.returncode == 1 and not report.exists(), 'failed download never starts manager')
    archive.write_bytes(b'not an archive')
    result = run(['--rtt', '1'])
    check(result.returncode == 1 and not report.exists(), 'corrupt archive rejected')
    pack(tarfile.TarInfo(PREFIX + '../escape'))
    result = run(['--rtt', '1'])
    check(result.returncode == 1 and not report.exists(), 'path traversal rejected')
    link = tarfile.TarInfo(PREFIX + 'link')
    link.type = tarfile.SYMTYPE
    link.linkname = '/etc'
    pack(link)
    result = run(['--rtt', '1'])
    check(result.returncode == 1 and not report.exists(), 'archive symlink rejected')
    pack()
    result = run()
    check(result.returncode == 0 and report.read_text().splitlines() == ['internal', 'setup'], 'noninteractive setup uses defaults without waiting for terminal')
    result = run(['--rtt', '1'], {'SF_BOOT_TEST_EXIT': '23'})
    check(result.returncode == 23, 'manager failure is returned and source is cleaned')

    # The bootstrap is streamed through a pipe; the manager must recover the SSH TTY.
    report.unlink(missing_ok=True)
    bootstrap = root / 'bootstrap.sh'
    shutil.copyfile(SOURCE, bootstrap)
    master, slave = pty.openpty()

    def terminal_session():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    child = subprocess.Popen(['bash', '-c', 'file=$1; shift; cat "$file" | bash -s -- "$@"', 'bash', str(bootstrap), *pins()],
                             stdin=slave, stdout=slave, stderr=slave, env=env, preexec_fn=terminal_session)
    os.close(slave)
    os.write(master, b'7\n')
    try:
        deadline = time.monotonic() + 15
        while child.poll() is None and time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], .1)
            if ready:
                try:
                    os.read(master, 65536)
                except OSError:
                    break
        child.wait(timeout=2)
        check(child.returncode == 0 and report.read_text().splitlines() == ['internal', 'setup', 'tty:7'],
              'piped installer keeps interactive terminal input')
        check(not list((root / 'tmp').iterdir()), 'interactive completion removes temporary source')
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        os.close(master)

    fixed = pins()
    archive.write_bytes(archive.read_bytes() + b'changed')
    result = run(['--rtt', '1'], fixed=fixed)
    check(result.returncode == 1 and not report.exists(), 'archive digest mismatch never executes manager')
    pack(version='9.9.9')
    result = run(['--rtt', '1'])
    check(result.returncode == 1 and not report.exists(), 'source version mismatch never executes manager')
    pack()
    result = run(['--rtt', '1'], fixed=[])
    check(result.returncode != 0 and not report.exists(), 'invalid official release response never executes manager')
    result = run(['--rtt', '1'], fixed=['--source-sha256', 'b' * 64])
    check(result.returncode == 2 and not report.exists(), 'partial source pin rejected before any execution')
    result = run(['--upgrade-manager'])
    check(result.returncode == 0 and report.read_text().splitlines() == ['internal', 'upgrade-manager'],
          'explicit pinned manager upgrade does not require terminal or install arguments')

    # Exercise the real official-release resolver without external HTTP or a
    # production manager. Assets are a complete tiny fake package and manifest.
    PREFIX = 'SF-Xray-Hop/'
    pack()
    manifest = dict(schemaVersion=1, project='SF-Xray-Hop', version='0.2.5', commit=COMMIT,
                    archive=dict(name='SF-Xray-Hop-0.2.5.tar.gz', sha256=hashlib.sha256(archive.read_bytes()).hexdigest(), size=archive.stat().st_size))
    (root / 'manifest.json').write_text(json.dumps(manifest))
    release = dict(tag_name='v0.2.5', draft=False, prerelease=False, published_at='2026-09-30', assets=[
        dict(name=name, browser_download_url=f'https://github.com/sprill-gt/SF-Xray-Hop/releases/download/v0.2.5/{name}')
        for name in ('manifest.json', 'SF-Xray-Hop-0.2.5.tar.gz')])
    (root / 'releases.json').write_text(json.dumps([release]))
    (root / 'release.json').write_text(json.dumps(release))
    (root / 'commit.json').write_text(json.dumps(dict(sha=COMMIT)))
    env['SF_BOOT_HTTP_ROOT'] = str(root)
    curl.write_text('''#!/usr/bin/env bash
while (($#)); do
    case "$1" in --output|-o) dest=$2; shift 2 ;; https://*) url=$1; shift ;; *) shift ;; esac
done
case "$url" in
 */releases\\?*) cp "$SF_BOOT_HTTP_ROOT/releases.json" "$dest" ;;
 */releases/tags/*) cp "$SF_BOOT_HTTP_ROOT/release.json" "$dest" ;;
 */commits/*) cp "$SF_BOOT_HTTP_ROOT/commit.json" "$dest" ;;
 */manifest.json) cp "$SF_BOOT_HTTP_ROOT/manifest.json" "$dest" ;;
 *.tar.gz) cp "$SF_BOOT_TEST_ARCHIVE" "$dest" ;;
 *) exit 22 ;;
esac
''')
    result = run(['--address', '203.0.113.10'], fixed=[])
    check(result.returncode == 0 and report.read_text().splitlines() == ['install', '--address', '203.0.113.10'],
          'default online bootstrap verifies official release manifest and executes full package')
    (root / 'releases.json').write_text('[]')
    result = run(['--address', '203.0.113.10'], fixed=[])
    check(result.returncode != 0 and not report.exists(), 'no official release stops instead of silently selecting main')
    release['prerelease'] = True
    (root / 'release.json').write_text(json.dumps(release))
    result = run(['--script-version', '0.2.5', '--address', '203.0.113.10'], fixed=[])
    check(result.returncode != 0 and not report.exists(), 'explicit version still rejects prerelease without opt-in')
    result = run(['--script-version', '0.2.5', '--allow-pre-script', '--address', '203.0.113.10'], fixed=[])
    check(result.returncode == 0 and report.exists(), 'maintainer can explicitly select and verify a project prerelease')
    (root / 'commit.json').write_text(json.dumps(dict(sha='b' * 40)))
    result = run(['--script-version', '0.2.5', '--allow-pre-script', '--address', '203.0.113.10'], fixed=[])
    check(result.returncode != 0 and not report.exists(), 'release tag commit mismatch stops bootstrap before execution')

    offline = root / 'offline'
    (offline / 'lib').mkdir(parents=True)
    shutil.copyfile(SOURCE, offline / 'install.sh')
    (offline / 'lib/install.sh').touch()
    (offline / 'sf-xray-hop').write_bytes(MANAGER)
    result = subprocess.run(['bash', str(offline / 'install.sh'), '--rtt', '0'], capture_output=True,
                            env=env | {'SF_BOOT_TEST_DOWNLOAD_FAILURE': '1'}, start_new_session=True, timeout=5)
    check(result.returncode == 0 and report.read_text().splitlines() == ['install', '--rtt', '0'],
          'complete offline checkout needs no download')
print(f'TOTAL {count} bootstrap checks (download and manager fixtures)')
