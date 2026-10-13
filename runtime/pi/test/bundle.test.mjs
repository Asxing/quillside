import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdtemp,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
test('distributed bundle includes OAuth callbacks and stops without credentials',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'quillside-pi-bundle-'));
 const child=spawn(process.execPath,['dist/worker.mjs'],{env:{HOME:directory,PATH:'/usr/bin:/bin',QUILLSIDE_PI_DIR:directory,PI_PACKAGE_DIR:resolve('node_modules/@earendil-works/pi-coding-agent'),PI_OFFLINE:'1'},stdio:['pipe','pipe','ignore']});
 const input=createInterface({input:child.stdout});const events=[];
 const result=new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');reject(new Error('bundled login timeout'));},5000);child.on('error',reject);child.on('exit',code=>{clearTimeout(timer);resolve(code);});input.on('line',line=>{const event=JSON.parse(line);events.push(event);if(event.type==='auth'&&event.event.type==='auth_url')child.stdin.write('{"method":"cancel"}\n');});});
 child.stdin.write('{"method":"login","provider":"openai"}\n');
 try{await result;const auth=events.find(e=>e.type==='auth'&&e.event.type==='auth_url');assert.ok(auth,'bundled worker must load the OAuth module');assert.equal(new URL(auth.event.url).origin,'https://auth.openai.com');assert.ok(events.some(e=>e.type==='error'&&e.code==='cancelled'));}
 finally{child.kill();input.close();await rm(directory,{recursive:true,force:true});}
});
