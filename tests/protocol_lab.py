"""Real pinned Xray protocol lab on loopback. NOT a VPS/systemd acceptance test.

Three distinct loopback source IPs let the HTTPS receiver observe which freedom
outbound actually completed the request. All private keys stay under .cache.
"""
import argparse
import copy
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
processes = []
checks = []


def run(args, **kw):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True,
                          creationflags=FLAGS, **kw)


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def save(file, data):
    file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def stop(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def start(binary, config, listen_port, log):
    run([binary, "run", "-test", "-config", config], timeout=20)
    with log.open("wb") as output:
        proc = subprocess.Popen([str(binary), "run", "-config", str(config)],
                                stdout=output, stderr=subprocess.STDOUT,
                                creationflags=FLAGS)
    processes.append(proc)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"core exited at {config.name}; private log retained")
        try:
            with socket.create_connection(("127.0.0.1", listen_port), timeout=.2):
                return proc
        except OSError:
            time.sleep(.1)
    raise RuntimeError(f"listener timeout at {config.name}")


class Receiver(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        data = self.client_address[0].encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class LabServer(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        # REALITY intentionally abandons cover-target handshakes.
        pass


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", required=True, type=Path)
    parser.add_argument("--jq", required=True, type=Path)
    parser.add_argument("--openssl", default=shutil.which("openssl"), type=Path)
    parser.add_argument("--curl", default=shutil.which("curl.exe") or shutil.which("curl"), type=Path)
    args = parser.parse_args()
    work = ROOT / ".cache" / f"protocol-{int(time.time())}"
    work.mkdir(parents=True, mode=0o700)
    cert, key = work / "cert.pem", work / "key.pem"
    run([args.openssl, "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
         "-keyout", key, "-out", cert, "-subj", "/CN=lab.example",
         "-addext", "subjectAltName=DNS:lab.example,DNS:localhost,IP:127.0.0.1"], timeout=30)
    servers = []
    for alpn in (["h2", "http/1.1"], ["http/1.1"]):
        server = LabServer(("127.0.0.1", 0), Receiver)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.load_cert_chain(cert, key)
        context.set_alpn_protocols(alpn)
        # A TCP readiness connection must not block all subsequent TLS accepts.
        server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    tls_port, https_port = [server.server_port for server in servers]

    def model(data, expr):
        options = [args.jq]
        if os.name == "nt":
            options.append("-b")
        output = run(options + ["-L", ROOT / "templates", f'include "model"; {expr}'],
                     input=json.dumps(data).encode(), timeout=10).stdout
        return json.loads(output)

    def node(label, rtt):
        enc_output = run([args.core, "vlessenc"], timeout=15).stdout.decode()
        section = enc_output.split("Authentication: ML-KEM-768, Post-Quantum", 1)[1]
        enc = dict(re.findall(r'"(decryption|encryption)": "([^"]+)"', section))
        keys = run([args.core, "x25519"], timeout=10).stdout.decode()
        private = re.search(r"PrivateKey: (\S+)", keys)[1]
        public = re.search(r"Password(?: \(PublicKey\))?: (\S+)", keys)[1]
        ids = [run([args.core, "uuid"]).stdout.decode().strip() for _ in range(3)]
        baseline = enc["decryption"]
        if rtt == "1":
            dec = enc["decryption"].split("."); dec[2] = "0s"
            client = enc["encryption"].split("."); client[2] = "1rtt"
            enc = {"decryption": ".".join(dec), "encryption": ".".join(client)}
        return dict(schemaVersion=1, node=dict(id=ids[0], name=label, address="127.0.0.1", port=port()),
                    identities=dict(direct=dict(id=ids[1], email="sf-xray-hop-direct"),
                                    relay=dict(id=ids[2], email="sf-xray-hop-relay")),
                    encryption=dict(**enc, generatorDecryption=baseline, rtt=rtt, authentication="ML-KEM-768"),
                    reality=dict(target=f"127.0.0.1:{tls_port}", serverName="lab.example", privateKey=private,
                                 password=public, shortId=os.urandom(8).hex()),
                    xhttp=dict(path="/"+os.urandom(8).hex(), mode="auto"), fingerprint="chrome", nextHop=None,
                    core=dict(id="v26.9.9-0123456789abcdef", version="26.9.9", channel="pinned", pinnedVersion="26.9.9"))

    def node_start(state, label, source):
        config = model(state, "server_config(.)")
        config["log"]["loglevel"] = "debug"
        config["inbounds"][0]["listen"] = "127.0.0.1"
        # Test-only source addresses, so routing is observed by the receiver.
        freedom = next(o for o in config["outbounds"] if o["tag"] == "direct-freedom")
        freedom["sendThrough"] = source
        # v26.9.9 blocks private destinations by default. Permit ONLY our receiver
        # in the lab; the production template keeps all upstream default rules.
        freedom["settings"] = {"finalRules": [{"action": "allow", "ip": ["127.0.0.1/32"], "port": str(https_port)}]}
        file = work / f"{label}.json"
        save(file, config)
        return start(args.core, file, state["node"]["port"], work / f"{label}.log")

    def request(profile, label, expected=None, fail=False):
        listen_port = port()
        config = model(profile, f"client_config(.;{listen_port})")
        config["log"]["loglevel"] = "debug"
        file = work / f"client-{label}.json"; save(file, config)
        proc = start(args.core, file, listen_port, work / f"client-{label}.log")
        try:
            result = subprocess.run([str(args.curl), "--fail", "--silent", "--show-error", "--proxy",
                                     f"http://127.0.0.1:{listen_port}", "--noproxy", "", "--cacert", str(cert),
                                     "--connect-timeout", "3", "--max-time", "7", f"https://127.0.0.1:{https_port}/exit"],
                                    capture_output=True, creationflags=FLAGS, timeout=10)
            if fail:
                assert result.returncode != 0, f"{label}: unexpectedly bypassed failure"
            else:
                actual = result.stdout.decode().strip()
                if result.returncode or actual != expected:
                    detail = result.stderr.decode(errors="replace")[:600]
                    raise RuntimeError(f"{label}: expected {expected}, observed {actual!r}, curl={result.returncode}: {detail}; private logs retained")
            checks.append(label)
            print(f"PASS {label}", flush=True)
        finally:
            stop(proc)

    try:
        for rtt in ("0", "1"):
            a, b, b2 = [node(name, rtt) for name in ("入口", "出口1", "出口2")]
            assert all(model(s, "valid_state") for s in (a, b, b2))
            pb = node_start(b, f"B-{rtt}", "127.0.0.12")
            pb2 = node_start(b2, f"B2-{rtt}", "127.0.0.13")
            pa = node_start(a, f"A-{rtt}", "127.0.0.11")
            direct = model(a, 'public_profile(.;"direct")')
            relay = model(a, 'public_profile(.;"relay")')
            request(direct, f"{rtt}rtt-single-direct", "127.0.0.11")
            request(relay, f"{rtt}rtt-single-relay", "127.0.0.11")
            for fingerprint in ("firefox", "safari"):
                variant = copy.deepcopy(direct)
                variant["fingerprint"] = fingerprint
                request(variant, f"{rtt}rtt-fingerprint-{fingerprint}", "127.0.0.11")
            stop(pa)
            a["nextHop"] = model(b, 'public_profile(.;"relay")')
            pa = node_start(a, f"A-chain-{rtt}", "127.0.0.11")
            assert {k: v for k, v in model(a, 'public_profile(.;"relay")').items() if k != 'remark'} == {k: v for k, v in relay.items() if k != 'remark'}
            request(direct, f"{rtt}rtt-chain-direct", "127.0.0.11")
            request(relay, f"{rtt}rtt-chain-relay", "127.0.0.12")
            bad = model(b2, 'public_profile(.;"relay")')
            bad["id"] = "00000000-0000-4000-8000-000000000000"
            request(bad, f"{rtt}rtt-reject-invalid-candidate", fail=True)
            request(relay, f"{rtt}rtt-old-exit-still-works", "127.0.0.12")
            stop(pb)
            request(relay, f"{rtt}rtt-downstream-fails-closed", fail=True)
            request(direct, f"{rtt}rtt-emergency-direct", "127.0.0.11")
            stop(pa)
            a["nextHop"] = model(b2, 'public_profile(.;"relay")')
            pa = node_start(a, f"A-replace-{rtt}", "127.0.0.11")
            assert {k: v for k, v in model(a, 'public_profile(.;"relay")').items() if k != 'remark'} == {k: v for k, v in relay.items() if k != 'remark'}
            request(relay, f"{rtt}rtt-replace-unchanged-client", "127.0.0.13")
            stop(pa)
            a["nextHop"] = None
            pa = node_start(a, f"A-remove-{rtt}", "127.0.0.11")
            request(relay, f"{rtt}rtt-remove-unchanged-client", "127.0.0.11")
            # Existing client parameters still authenticate after server RTT policy changes.
            stop(pa)
            parts = a["encryption"]["decryption"].split(".")
            parts[2] = "0s" if rtt == "0" else a["encryption"]["generatorDecryption"].split(".")[2]
            a["encryption"]["decryption"] = ".".join(parts)
            pa = node_start(a, f"A-rtt-switch-{rtt}", "127.0.0.11")
            request(relay, f"{rtt}rtt-old-credential-after-policy-change", "127.0.0.11")
            stop(pa); stop(pb2)
        result = {"scope": "Windows/Linux loopback protocol only; no systemd/VPS/client GUI acceptance",
                  "core": run([args.core, "version"]).stdout.decode().splitlines()[0],
                  "passed": checks, "count": len(checks)}
        save(ROOT / ".cache" / "protocol-results.json", result)
        print(f"TOTAL {len(checks)} real core protocol checks", flush=True)
    finally:
        for proc in processes:
            stop(proc)
        for server in servers:
            server.shutdown(); server.server_close()


if __name__ == "__main__":
    main()
