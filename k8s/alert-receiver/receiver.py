"""Minimal Alertmanager webhook receiver.

Stands in for a pager and a ticketing system: every notification is written
to stdout as one JSON line, tagged with the path it arrived on (/page,
/ticket, /watchdog, /default), so `kubectl logs` shows what would have been
sent to whom.
"""

import json
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return
        record = {
            "received_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "channel": self.path.strip("/") or "default",
            "status": payload.get("status"),
            "group_labels": payload.get("groupLabels"),
            "alerts": [
                {
                    "status": a.get("status"),
                    "labels": a.get("labels"),
                    "starts_at": a.get("startsAt"),
                    "ends_at": a.get("endsAt"),
                }
                for a in payload.get("alerts", [])
            ],
        }
        print(json.dumps(record), flush=True)
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        # Used by the readiness probe.
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
