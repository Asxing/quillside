#!/usr/bin/env python3
"""Local synthetic writing-session fixture. Never accepts real note content."""
import argparse
import json
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length > 900000: raise ValueError('size')
            payload = json.loads(self.rfile.read(length))
            user = next(x['content'] for x in payload.get('messages', []) if x['role'] == 'user')
            if 'APN-AGENT-1009' not in user: raise ValueError('synthetic marker required')
            request = json.loads(user)
            stage, task = request['stage'], request['task']
            annotations = task['annotations']
            assessments = [{'annotationID': a['id'], 'status': 'addressed', 'explanation': '已按批注统一检查，保留数据与限定条件。'} for a in annotations]
            if stage == 'plan': result = {'plan': '结合全部意见与Skill，保留事实、数字和段落结构。', 'resourceRequests': []}
            elif stage == 'audit': result = {'passed': True, 'issues': [], 'assessments': assessments}
            elif stage in ('revise', 'repair'):
                text = task['candidate'].replace('非常显著', '有所').replace('完全不需要人工', '仍需人工复核')
                if '再简洁' in task.get('instruction', ''): text = text.replace('我们目前认为，', '')
                result = {'document': text, 'assessments': assessments, 'issues': []}
            else: raise ValueError('stage')
            self.server.records.append({'stage': stage, 'annotation_count': len(annotations), 'skill_names': [s['name'] for s in task['skills']], 'history_count': len(task['history']), 'synthetic_only': True})
            self.server.report.write_text(json.dumps(self.server.records, ensure_ascii=False, indent=2))
            self.send_response(200); self.send_header('Content-Type', 'application/x-ndjson'); self.end_headers()
            content = json.dumps(result, ensure_ascii=False)
            self.wfile.write((json.dumps({'message': {'content': content}, 'done': False})+'\n').encode())
            self.wfile.write(b'{"message":{"content":""},"done":true,"done_reason":"stop"}\n'); self.wfile.flush()
        except (ValueError, KeyError, StopIteration): self.send_error(422, 'Synthetic writing task required')
        except (BrokenPipeError, ConnectionResetError): pass

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--port-file',required=True);p.add_argument('--report-file',required=True);args=p.parse_args()
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.records=[];server.report=Path(args.report_file)
    Path(args.port_file).write_text(str(server.server_port));server.report.write_text('[]')
    try: server.serve_forever()
    except KeyboardInterrupt: server.server_close()
