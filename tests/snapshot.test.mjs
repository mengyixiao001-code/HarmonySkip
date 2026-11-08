import test from 'node:test';
import assert from 'node:assert/strict';
import {harness} from './runtime.mjs';
const bundle='com.tencent.hm.qqmusic';
const item=(text,id='',bounds='[965,87][1116,185]')=>({attributes:{text,id,bounds,type:'Text',visible:'true',enabled:'true',clickable:'true'},children:[]});
const tree=(nodes)=>({attributes:{bundleName:bundle,focused:'true',visible:'true'},children:nodes});
const ad=()=>tree([item('互动广告｜已 WIFI 预加载','topAdText'),item('跳过')]);

test('a successful dispatch with an unchanged skip is explicitly reported as not closed',async()=>{
 const {api,catalog,context,files}=harness();context.setTimeout=fn=>queueMicrotask(fn);
 const app=structuredClone(catalog.apps.find(a=>a.bundle===bundle));const builtin=app.rules;app.rules=[];
 context.abilityDelegatorRegistry={getAbilityDelegator:()=>({getAppContext:()=>({getApplicationContext:()=>({filesDir:'/mock'})}),
  executeShellCommand:async()=>{throw Error('a new shell input connection must not be used');}})};
 context.fileIo={unlinkSync:()=>files.delete('ui-snapshot.tmp')};
 let clicks=0;const driver={findWindow:async()=>({isFocused:async()=>true,getBundleName:async()=>bundle}),
  dumpLayout:async()=>{files.set('ui-snapshot.tmp',JSON.stringify(ad()));return true;},click:async()=>{clicks++;}};
 const logs=[];await new api.ActionExecutor().inspect(driver,app,catalog.generic,()=>true,(k,r)=>logs.push(r),builtin);
 assert.equal(clicks,1);assert.deepEqual(logs,['已尝试','未关闭：按钮仍在']);
});

test('a retained heartbeat from an earlier installation cannot claim the new build is running',()=>{
 const {api,files}=harness();const run=String(Date.now());files.set('active',run);files.set('mode','monitor');
 files.set('health',JSON.stringify({run,beat:Date.now(),phase:'运行中'}));
 assert.match(api.statusText('/mock'),/更新后需要重新激活/);
 files.set('health',JSON.stringify({run,build:'0.3.9',beat:Date.now(),phase:'运行中'}));
 assert.equal(api.statusText('/mock'),'运行中');
});

test('generic apps reject irrelevant pages before walking live components',async()=>{
 const {api,catalog,context,files}=harness();
 const bundle='com.taobao.taobao4hmos';const app=new api.AppProfile('淘宝',bundle);
 context.abilityDelegatorRegistry={getAbilityDelegator:()=>({getAppContext:()=>({getApplicationContext:()=>({filesDir:'/mock'})})})};
 context.fileIo={unlinkSync:()=>files.delete('ui-snapshot.tmp')};
 const driver={findWindow:async()=>({isFocused:async()=>true,getBundleName:async()=>bundle}),
  dumpLayout:async()=>{files.set('ui-snapshot.tmp',JSON.stringify({attributes:{bundleName:bundle,focused:'true',visible:'true'},children:[item('首页')]}));return true;},
  findComponents:async()=>{throw Error('irrelevant page must not block the next foreground app');}};
 await new api.ActionExecutor().inspect(driver,app,catalog.generic,()=>true,()=>{throw Error('unexpected click');});
 assert.equal(files.has('ui-snapshot.tmp'),false);
});
test('snapshot path scopes visible controls and preserves the measured button center',()=>{
 const {api}=harness();const page=api.parseSnapshot(JSON.stringify(ad()),bundle);
 assert.equal(page.nodes.find(n=>n.text==='跳过').point.x,1040);
 assert.equal(page.nodes.find(n=>n.text==='跳过').point.y,136);
 const foreign=ad();foreign.attributes.bundleName='other.app';
 assert.equal(api.parseSnapshot(JSON.stringify(foreign),bundle).nodes.length,0);
 const hidden=ad();hidden.children[1].attributes.visible='false';
 assert.equal(api.parseSnapshot(JSON.stringify(hidden),bundle).nodes.some(n=>n.text==='跳过'),false);
});
test('two fast snapshots cancel protected or moving targets and retain confirmation checks',async()=>{
 for(const scenario of ['success','protected','moved','duplicate']){
  const {api,context,files,catalog}=harness();
  context.setTimeout=fn=>queueMicrotask(fn);
  context.abilityDelegatorRegistry={getAbilityDelegator:()=>({getAppContext:()=>({getApplicationContext:()=>({filesDir:'/mock'})}),executeShellCommand:async cmd=>{assert.equal(cmd,'uitest uiInput click 1040 136');clicks++;return {exitCode:0,stdResult:''};}})};
  context.fileIo={unlinkSync:()=>files.delete('ui-snapshot.tmp')};
  const app=structuredClone(catalog.apps.find(a=>a.bundle===bundle));const builtin=app.rules;app.rules=[];
  let shots=0,clicks=0;
  const driver={findWindow:async()=>({isFocused:async()=>true,getBundleName:async()=>bundle}),
   dumpLayout:async()=>{
    const t=ad();
    if(shots++===1){
     if(scenario==='protected')t.children.push(item('确认付款'));
     if(scenario==='moved')t.children[1].attributes.bounds='[10,20][80,60]';
     if(scenario==='duplicate')t.children.push(item('跳过'));
    }
    files.set('ui-snapshot.tmp',JSON.stringify(clicks?tree([item('首页')]):t));return true;
   },
   click:async(x,y)=>{assert.equal(x,1040);assert.equal(y,136);clicks++;}};
  const logs=[];
  await new api.ActionExecutor().inspect(driver,app,catalog.generic,()=>true,(key,result)=>logs.push(result),builtin);
  assert.equal(clicks,scenario==='success'?1:0,scenario);
  assert.equal(files.has('ui-snapshot.tmp'),false);
  if(clicks)assert.deepEqual(logs,['已尝试','页面已消失']);
 }
});
