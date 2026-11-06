"""Command-line client for /admin/fault on the local instance.

Meant to be run inside a pod with `kubectl exec`, so it talks to 127.0.0.1
and reads the token from the same ADMIN_TOKEN variable the server uses.
Fault state is per process, so callers have to run it in every pod.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def call(method: str, body: dict | None = None) -> dict:
    port = os.environ.get("PORT", "8080")
    token = os.environ.get("ADMIN_TOKEN", "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/admin/fault",
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.load(resp)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="faultctl")
    sub = parser.add_subparsers(dest="command", required=True)
    set_cmd = sub.add_parser("set", help="replace the current fault configuration")
    set_cmd.add_argument("--error-rate", type=float, default=0.0)
    set_cmd.add_argument("--latency-ms", type=int, default=0)
    sub.add_parser("clear", help="remove all injected faults")
    sub.add_parser("show", help="print the current fault configuration")
    args = parser.parse_args(argv)

    try:
        if args.command == "set":
            result = call("PUT", {"error_rate": args.error_rate, "latency_ms": args.latency_ms})
        elif args.command == "clear":
            result = call("DELETE")
        else:
            result = call("GET")
    except urllib.error.HTTPError as exc:
        print(f"faultctl: HTTP {exc.code}: {exc.read().decode()}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
