#!/usr/bin/env python3
"""Local synthetic HTTP fixtures. Never reads credentials or Apple Notes."""
import argparse
import json
import select
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    lifecycle = {}
    lifecycle_lock = threading.Lock()
    def log_message(self, *_):
        pass

    def do_GET(self):
        with self.lifecycle_lock:
            state = self.lifecycle.get(self.path, {"state": "missing"})
        data = json.dumps(state).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def hanging_stream(self, body):
        if body.get("input") != "synthetic input" or body.get("instructions") != "test system":
            self.send_error(422)
            return
        identity = self.path.removesuffix("/responses")
        mode = identity.split("/")[2]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        progress_event = b'data: {"type":"response.in_progress"}\n\n'
        self.wfile.write(progress_event if mode == "progress" else b'data: {"type":"response.output_text.delta","delta":"start"}\n\n')
        self.wfile.flush()
        opened = time.monotonic()
        with self.lifecycle_lock:
            self.lifecycle[identity] = {"state": "open"}
        deadline = time.monotonic() + 4
        try:
            while time.monotonic() < deadline:
                readable, _, _ = select.select([self.connection], [], [], 0.02)
                if readable and not self.connection.recv(1, socket.MSG_PEEK):
                    break
                if mode in ("heartbeat", "progress"):
                    # Progress without UI deltas isolates the absolute deadline
                    # from concurrent AppKit rendering in the test process.
                    payload = b': keepalive\n\n' if mode == "heartbeat" else progress_event
                    self.wfile.write(payload)
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with self.lifecycle_lock:
                self.lifecycle[identity] = {"state": "closed", "elapsed": time.monotonic() - opened}

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        if body.get("model") != "fixture-model" or body.get("stream") is not True:
            self.send_error(400)
            return
        if self.path.startswith("/lifecycle/"):
            self.hanging_stream(body)
            return
        if self.path.endswith("/responses"):
            valid = body.get("input") == "synthetic input" and body.get("instructions") == "test system" and body.get("store") is False
            events = [
                {"type": "response.output_text.delta", "delta": "合成"},
                {"type": "response.output_text.delta", "delta": "结果🙂"},
                {"type": "response.completed", "response": {"status": "completed"}},
            ]
        elif self.path.endswith("/messages"):
            valid = body.get("system") == "test system" and self.headers.get("x-api-key") == "synthetic-key"
            events = [
                {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "合成结果🙂"}},
                {"type": "message_delta", "delta": {"stop_reason": "end_turn"}},
                {"type": "message_stop"},
            ]
        elif self.path.endswith("/api/chat"):
            valid = body.get("messages", [{}])[0].get("content") == "test system"
            events = [{"message": {"content": "合成结果🙂"}, "done": False}, {"message": {"content": ""}, "done": True, "done_reason": "stop"}]
        elif self.path.endswith("/chat/completions"):
            valid = body.get("messages", [{}])[0].get("content") == "test system" and self.headers.get("Authorization") == "Bearer synthetic-key"
            events = [{"choices": [{"delta": {"content": "合成结果🙂"}, "finish_reason": None}]}, {"choices": [{"delta": {}, "finish_reason": "stop"}]}]
        else:
            self.send_error(404)
            return
        if not valid:
            self.send_error(422)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson" if self.path.endswith("/api/chat") else "text/event-stream")
        self.end_headers()
        for event in events:
            content = json.dumps(event, ensure_ascii=False)
            payload = ((content + "\n") if self.path.endswith("/api/chat") else (": keepalive\r\nevent: message\r\n" + "\r\n".join("data: " + row for row in json.dumps(event, ensure_ascii=False, indent=2).splitlines()) + "\r\n\r\n")).encode()
            # Deliberately split in the middle of UTF-8 scalars and transport lines.
            for offset in range(0, len(payload), 7):
                self.wfile.write(payload[offset:offset + 7])
                self.wfile.flush()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(args.port_file).write_text(str(server.server_port))
    server.serve_forever()
