"""Constant-rate HTTP load generator.

Requests are scheduled on a fixed clock and handed to a thread pool, so slow
responses do not lower the offered rate. That matters during the latency
drill: a closed-loop client would back off and hide the problem.
"""

import os
import signal
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

TARGET = os.environ.get("TARGET_URL", "http://demo-app.slo-lab.svc:8080/work")
RPS = float(os.environ.get("RPS", "10"))
TIMEOUT = float(os.environ.get("TIMEOUT_SECONDS", "5"))
REPORT_EVERY = 30

counts = {"ok": 0, "http_error": 0, "conn_error": 0}
running = True


def stop(*_):
    global running
    running = False


def hit():
    try:
        with urllib.request.urlopen(TARGET, timeout=TIMEOUT) as resp:
            resp.read()
        counts["ok"] += 1
    except urllib.error.HTTPError:
        counts["http_error"] += 1
    except Exception:
        # Connection failures never reach the server's metrics, so the
        # server-side SLI cannot see them. Logged here for comparison.
        counts["conn_error"] += 1


def main():
    signal.signal(signal.SIGTERM, stop)
    interval = 1.0 / RPS
    print(f"loadgen: {RPS} rps against {TARGET}", flush=True)
    next_at = time.monotonic()
    last_report = next_at
    with ThreadPoolExecutor(max_workers=64) as pool:
        while running:
            pool.submit(hit)
            next_at += interval
            now = time.monotonic()
            if now - last_report >= REPORT_EVERY:
                print(f"loadgen: {counts}", flush=True)
                last_report = now
            time.sleep(max(0.0, next_at - now))
    return 0


if __name__ == "__main__":
    sys.exit(main())
