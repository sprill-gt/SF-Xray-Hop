"""Reject accidental publication of node literals, personal contacts and host paths."""
import ipaddress
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GIT = ['git', '-c', f'safe.directory={ROOT}']
paths = subprocess.check_output([*GIT, 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
allowed_dns = {'1.1.1.1', '8.8.8.8', '9.9.9.9'}
allowed_uuid = {'00000000-0000-4000-8000-000000000000', '01234567-89ab-cdef-0123-456789abcdef'}
failures = []
for name in filter(None, paths):
    path = ROOT / name
    if not path.is_file():
        continue
    try:
        value = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    for number, line in enumerate(value.splitlines(), 1):
        for literal in re.findall(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])', line):
            try:
                address = ipaddress.ip_address(literal)
            except ValueError:
                continue
            if address.is_global and not address.is_multicast and literal not in allowed_dns:
                failures.append(f'{name}:{number}: public IPv4 literal')
        for literal in re.findall(r'[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', line):
            if not (literal.endswith('@users.noreply.github.com') or literal == 'noreply@github.com' or literal.endswith('@example.com')):
                failures.append(f'{name}:{number}: nonexample email literal')
        for literal in re.findall(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b', line):
            if literal not in allowed_uuid:
                failures.append(f'{name}:{number}: unexplained UUID literal')
        if re.search(r'[A-Za-z]:[\\/]Users[\\/][A-Za-z0-9_. -]+[\\/]', line):
            failures.append(f'{name}:{number}: personal Windows profile path')
# Check the history available in this checkout; CI/release use fetch-depth: 0.
emails = subprocess.check_output([*GIT, 'log', 'HEAD', '--format=%ae%n%ce'], cwd=ROOT).decode().splitlines()
for email in emails:
    if not (email.endswith('@users.noreply.github.com') or email == 'noreply@github.com'):
        failures.append('HEAD history contains a non-noreply author/committer; value withheld')
if failures:
    raise SystemExit('\n'.join(failures))
print('PASS tracked-file privacy literals and checked-out HEAD commit identities')
