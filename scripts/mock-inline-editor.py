#!/usr/bin/env python3
"""Local UI acceptance fixture. Rejects requests lacking the synthetic note marker.

Run with --port-file and --report-file. Only metadata is retained, never note text.
Use Ollama Native / fixture-inline in the app and remove the temporary connection afterward.
"""
import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MARKER = "ON-UI-20261008"
RESULT = "ON-UI-20261008：项目计划周五交付，请确认负责人和验收标准。"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length > 220_000:
            self.send_error(413)
            return
        try:
            body = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError):
            self.send_error(400)
            return
        messages = body.get("messages", [])
        user = next((m.get("content", "") for m in messages if m.get("role") == "user"), "")
        valid = self.path == "/api/chat" and body.get("model") == "fixture-inline" and MARKER in user
        if not valid:
            self.send_error(422, "Synthetic note marker required")
            return
        with self.server.report_lock:
            self.server.requests += 1
            self.server.report.write_text(json.dumps({"requests": self.server.requests, "synthetic_marker_verified": True}))
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        try:
            for start in range(0, len(RESULT), 4):
                self.wfile.write((json.dumps({"message": {"content": RESULT[start:start + 4]}, "done": False}, ensure_ascii=False) + "\n").encode())
                self.wfile.flush()
                time.sleep(0.15)
            self.wfile.write(b'{"message":{"content":""},"done":true,"done_reason":"stop"}\n')
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--report-file", required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.report = Path(args.report_file)
    server.requests = 0
    server.report_lock = threading.Lock()
    server.report.write_text(json.dumps({"requests": 0}))
    Path(args.port_file).write_text(str(server.server_port))
    server.serve_forever()
