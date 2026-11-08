import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
const raw=readFileSync(new URL('../Assistant/entry/src/main/ets/platform/LocalHdc.ets',import.meta.url),'utf8').replace(/^import .*;$/gm,'').replace(/export /g,'');
const program=new vm.Script(stripTypeScriptTypes(raw)+'\nthis.activate = activate;');
function setup(phase,extra=false,onlyOther=false){
 const files=new Map();let calls=0;const commands=[];
 const c={Date,Health:class {},setTimeout:(fn,ms)=>{if(ms!==12000)queueMicrotask(fn);return 1;},clearTimeout:()=>{},
 hdc:{start:()=>{},run:async (cmd,temp,target)=>{calls++;commands.push({cmd,target});if(cmd.startsWith('tconn'))return 'connect ok';if(cmd==='list targets -v')return (onlyOther?'':'127.0.0.1:12345 TCP Connected')+(extra||onlyOther?'\n192.168.1.3:12345 TCP Connected':'');if(cmd.endsWith('shell echo HS_SESSION_OK'))return 'HS_SESSION_OK';return '';}},
 connection:{getDefaultNet:async()=>{throw Error('offline');}},readState:(_,k)=>files.get(k)||'',writeState:(_,k,v)=>files.set(k,v),clearLearn:()=>{},
 getHealth:()=>({run:files.get('active'),phase,beat:Date.now(),successfulChecks:phase==='运行中'?1:0})};
 program.runInNewContext(c);return {c,files,commands,calls:()=>calls};
}
test('activation requires a successful running heartbeat, not merely a matching run ID',async()=>{
 const ctx={tempDir:'/tmp',getApplicationContext:()=>({filesDir:'/files'})};
 for(const phase of ['连接异常','待激活','需要重新激活']){
  const {c}=setup(phase);await assert.rejects(c.activate(ctx,'12345',true,[],()=>{}),/启动|服务/);
 }
 const {c}=setup('运行中');await c.activate(ctx,'12345',true,[],()=>{});
});

test('reactivation with an old connection uses only the newly verified target',async()=>{
 const {c,commands}=setup('运行中',true);
 await c.activate({tempDir:'/tmp',getApplicationContext:()=>({filesDir:'/files'})},'12345',true,[],()=>{});
 const shells=commands.filter(item=>item.cmd.includes('shell '));
 assert.ok(shells.length>=2);
 assert.ok(shells.every(item=>item.target==='127.0.0.1:12345'));
});

test('a different connected target never substitutes for the requested phone address',async()=>{
 const {c,commands,files}=setup('运行中',false,true);
 await assert.rejects(c.activate({tempDir:'/tmp',getApplicationContext:()=>({filesDir:'/files'})},'12345',true,[],()=>{}),/授权/);
 assert.equal(commands.some(item=>item.cmd.includes('shell ')),false);
 assert.equal(files.has('active'),false);
});

test('version lookups and runner launch share the verified target',async()=>{
 const {c,commands}=setup('运行中',true);
 c.osAccount={getAccountManager:()=>({getOsAccountLocalId:async()=>100})};
 await c.activate({tempDir:'/tmp',getApplicationContext:()=>({filesDir:'/files'})},'12345',true,[{bundle:'app.example',versions:['1']}],()=>{});
 const shells=commands.filter(item=>item.cmd.includes('shell '));
 assert.equal(shells.length,3);assert.ok(shells.every(item=>item.target==='127.0.0.1:12345'));
});
