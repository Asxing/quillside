#!/usr/bin/env python3
"""Synthetic-only Agent role protocol acceptance. Records metadata, never keys."""
import argparse,json,re
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*_): pass
    def do_POST(self):
        try:
            length=int(self.headers.get('Content-Length','0'))
            if length>1000000: raise ValueError('size')
            payload=json.loads(self.rfile.read(length))
            messages=payload.get('messages',[])
            system=next(m['content'] for m in messages if m['role']=='system')
            user=next(m['content'] for m in messages if m['role']=='user')
            if 'APN-ROLE-1010' not in user and '复核耗时尚未统计' not in user: raise ValueError('synthetic material required')
            found=re.search(r'本轮Agent角色：([^。]+)。',system)
            role=found.group(1) if found else 'missing'
            outputs={
                '公众号':'处理一次要花多久？原来是30分钟，现在缩短到了10分钟。\n结果仍需人工复核。\n复核耗时尚未统计，整体能节省多少时间还要进一步确认。',
                '个人笔记':'处理时间：30分钟 → 10分钟。\n边界：结果仍需人工复核。\n待确认：复核耗时尚未统计。',
                '汇报':'进展：单次处理时间由30分钟缩短至10分钟。\n当前边界：仍需人工复核。\n待补充：复核耗时尚未统计，端到端效率改善尚待评估。'}
            try: request=json.loads(user)
            except ValueError: request={}
            task=request.get('task',{});stage=request.get('stage','quick')
            comments=task.get('annotations',[])
            assessments=[{'annotationID':a['id'],'status':'addressed','explanation':'合成验收：保留数字、人工复核与未统计状态。'} for a in comments]
            if stage=='plan': value={'plan':'按所选角色统一处理材料和意见','resourceRequests':[]}
            elif stage=='audit': value={'passed':True,'issues':[],'assessments':assessments}
            elif stage in ('revise','repair'): value={'document':outputs.get(role,'复核耗时尚未统计。'),'assessments':assessments,'issues':[]}
            else: value=outputs.get(role,'复核耗时尚未统计。')
            self.server.records.append({'role':role,'stage':stage,'annotation_count':len(comments),'history_count':len(task.get('history',[])),'skill_names':[x['name'] for x in task.get('skills',[])] if stage!='quick' else re.findall(r'<skill name="([^"]+)"',system),'has_role_prompt':'角色 Prompt：' in system,'synthetic_only':True})
            self.server.report.write_text(json.dumps(self.server.records,ensure_ascii=False,indent=2))
            content=value if isinstance(value,str) else json.dumps(value,ensure_ascii=False)
            self.send_response(200);self.send_header('Content-Type','application/x-ndjson');self.end_headers()
            self.wfile.write((json.dumps({'message':{'content':content},'done':False})+'\n').encode())
            self.wfile.write(b'{"message":{"content":""},"done":true,"done_reason":"stop"}\n');self.wfile.flush()
        except (ValueError,KeyError,StopIteration): self.send_error(422,'Synthetic role material required')
        except (BrokenPipeError,ConnectionResetError): pass

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--port-file',required=True);parser.add_argument('--report-file',required=True);args=parser.parse_args()
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.records=[];server.report=Path(args.report_file)
    server.report.write_text('[]');Path(args.port_file).write_text(str(server.server_port))
    try: server.serve_forever()
    except KeyboardInterrupt: server.server_close()
