"""Test an exported client JSON from an independent machine, without logging credentials."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--curl", default=shutil.which("curl"))
    parser.add_argument("--expect-exit")
    parser.add_argument("--expect-failure", action="store_true")
    parser.add_argument("--label", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if not args.expect_failure and not args.expect_exit:
        parser.error("provide --expect-exit or --expect-failure")
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    config["inbounds"] = [{"tag": "local-http", "listen": "127.0.0.1", "port": port, "protocol": "http", "settings": {}}]
    result = {"label": args.label, "checkedAt": datetime.now(timezone.utc).isoformat(), "passed": False}
    with tempfile.TemporaryDirectory(prefix="external-client-", dir=args.config.parent) as work:
        candidate = Path(work) / "client.json"
        candidate.write_text(json.dumps(config), encoding="utf-8")
        proc = subprocess.Popen([str(args.core), "run", "-config", str(candidate)], stdout=subprocess.DEVNULL,
                                stderr=subprocess.STDOUT, creationflags=flags)
        try:
            ready = False
            for _ in range(80):
                if proc.poll() is not None:
                    break
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=.1):
                        ready = True
                        break
                except OSError:
                    time.sleep(.1)
            if not ready:
                raise RuntimeError("local client did not start")
            urls = ["https://api.ipify.org"] if args.expect_failure else ["https://api.ipify.org"] * 3 + ["https://www.cloudflare.com/cdn-cgi/trace"]
            observations = []
            for url in urls:
                response = subprocess.run([args.curl, "--fail", "--silent", "--show-error", "--proxy",
                                           f"http://127.0.0.1:{port}", "--noproxy", "", "--connect-timeout", "6",
                                           "--max-time", "15", "--proto", "=https", url], capture_output=True,
                                          creationflags=flags, timeout=18)
                if args.expect_failure:
                    if response.returncode == 0:
                        raise RuntimeError("request unexpectedly succeeded during fail-closed test")
                    result["curlExitCode"] = response.returncode
                else:
                    if response.returncode:
                        raise RuntimeError(f"HTTPS request failed: curl={response.returncode}")
                    if "ipify" in url:
                        observed = response.stdout.decode().strip()
                        if observed != args.expect_exit:
                            raise RuntimeError(f"exit mismatch: expected {args.expect_exit}, observed {observed}")
                        observations.append(observed)
            result.update(passed=True, requestCount=len(urls), observedExits=observations, expectedFailure=args.expect_failure)
        except Exception as error:
            result["error"] = str(error)
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("a", encoding="utf-8") as report:
        report.write(json.dumps(result, ensure_ascii=False) + "\n")
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
