import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import { harness, node, page } from './runtime.mjs';

const fixture = JSON.parse(readFileSync(new URL('./fixture-pack.json',import.meta.url))).apps[0];
function setup(){
  const env=harness(); env.repo=new env.api.RuleRepository('/mock',env.catalog);
  env.repo.refresh(true); return env;
}
test('old settings, confirmed ID and no-ID rules migrate, bank choice survives, new defaults merge',()=>{
  const {api,catalog}=harness();
  const old={apps:[{label:'工行',bundle:catalog.apps[4].bundle,bank:true,enabled:false,
    rules:[{id:'close',text:'关闭',anchor:'广告'},{id:'',text:'跳过',anchor:'广告'}]}]};
  const p=api.migrate(JSON.stringify(old),catalog);
  assert.equal(p.apps.length,catalog.apps.length);assert.equal(p.apps[4].rules.length,2);assert.equal(p.apps[4].enabled,false);
  assert.equal(p.apps[4].rules[1].target[0].mode,'skip');
});
test('catalogue addition and revised built-in rule load without replacing personal overrides',()=>{
  const {api,catalog,repo,files}=setup();
  const personal=structuredClone(fixture);repo.commit({schema:1,apps:[personal]});
  const updated=structuredClone(catalog);
  const newApp=structuredClone(fixture);newApp.rules[0].version=2;updated.apps.push(newApp);
  updated.apps.push({...newApp,bundle:'app.new',rules:[]});
  const next=new api.RuleRepository('/mock',updated);next.refresh();
  assert.equal(next.index.get(fixture.bundle).rules[0].version,1);
  assert.equal(next.builtins.get(fixture.bundle)[0].version,2);
  assert.ok(next.index.has('app.new'));assert.ok(files.has('store.previous'));
});
test('invalid imports and partial writes keep the previous published configuration',()=>{
  const {repo,files,context}=setup();const stamp=repo.stamp;
  for(const raw of ['{','{}',JSON.stringify({schema:9,apps:[]}),JSON.stringify({schema:1,apps:[fixture,fixture]})]){
    assert.throws(()=>repo.commit(repo.preview(raw)));assert.equal(files.get('store.head'),stamp);
  }
  const saved=context.writeState;context.writeState=(d,k,v)=>{if(k.startsWith('personal.')) throw Error('full');saved(d,k,v);};
  assert.throws(()=>repo.commit(repo.preview(JSON.stringify({schema:1,apps:[fixture]}))));
  repo.refresh();assert.equal(files.get('store.head'),stamp);assert.ok(!repo.index.has(fixture.bundle));
});
test('corrupt active pair recovers last good backup, double corruption fails closed',()=>{
  const {repo,api,catalog,files}=setup();repo.commit(repo.preview(JSON.stringify({schema:1,apps:[fixture]})));
  files.set('personal.'+JSON.parse(repo.stamp).slot,'bad');
  const recovered=new api.RuleRepository('/mock',catalog);recovered.refresh();
  assert.ok(recovered.warning);assert.ok(!recovered.index.has(fixture.bundle));
  files.set('personal.'+JSON.parse(repo.stamp).backup,'bad');
  files.set('store.previous','bad');assert.throws(()=>new api.RuleRepository('/mock',catalog).refresh());
});
test('damaged old configuration is retained and never replaced by fresh defaults',()=>{
  const {api,files,catalog}=harness();files.set('rules','{');
  assert.throws(()=>new api.RuleRepository('/mock',catalog).refresh(true));
  assert.equal(files.get('rules'),'{');assert.ok(!files.has('store.head'));
});
test('restricted regex, descriptions, types, forbidden markers, no-ID guards',async()=>{
  const {api,catalog,repo}=setup();const a=structuredClone(fixture);const r=a.rules[0];a.rules=[r];
  r.target=[{field:'id',mode:'exact',value:'ad1'},{field:'desc',mode:'regex',value:'^关闭\\d{1,2}|跳过$'},
    {field:'type',mode:'exact',value:'Button'}];r.absent=[{field:'text',mode:'exact',value:'教程'}];
  repo.preview(JSON.stringify({schema:1,apps:[a]}));
  const raw=[node('活动广告'),node('','ad1',true,true,'关闭12')];
  const check=async(nodes)=>api.choose(await api.readPage(page(nodes,a.bundle),a),a,catalog.generic);
  assert.equal((await check(raw)).rule.key,r.key);assert.equal(await check([...raw,node('教程')]),undefined);
  assert.equal(await check([...raw,node('立即登录')]),undefined);
  r.target[1].value='^(a+)+$';assert.throws(()=>api.validateRule(r));
  r.target=[{field:'text',mode:'exact',value:'关闭'}];assert.throws(()=>api.validateRule(r));
});
test('personal priority and same-tier conflicts, including duplicate candidate handles',async()=>{
  const {api,catalog}=setup();const a=structuredClone(fixture);
  const r=api.learnedRule({id:'skip',text:'跳过',anchor:'广告'},'personal');a.rules=[r];
  const scan=async arr=>api.choose(await api.readPage(page(arr,a.bundle),a),a,catalog.generic);
  const nodes=[node('广告'),node('跳过','skip')];
  assert.equal((await scan(nodes)).rule.key,'personal');
  a.rules.push({...r,key:'conflict'});assert.equal(await scan(nodes),undefined);
  const p=await api.readPage(page([...nodes,nodes[1]],a.bundle),a);
  assert.equal(api.capture(p,a).candidates.length,0);assert.match(api.capture(p,a).message,/不唯一/);
});
test('two different layers process in one visit, per-rule limit and focus re-entry',async()=>{
  const {api,catalog,context}=setup();context.setTimeout=fn=>queueMicrotask(fn);
  const a=structuredClone(fixture);const runner=new api.ActionExecutor();runner.enter(a.bundle);
  let layer=0;const ids=['hs_layer_one','hs_layer_two'];let clicks=0;
  const driver=page([],a.bundle);
  driver.findComponents=async(sel)=>{
    if(sel.filter==='desc')return [];
    if(layer===2)return [node('广告已关闭')];
    const button=node('关闭',ids[layer]);button.click=async()=>{clicks++;layer++;};
    return [node(layer?'优惠广告':'活动广告'),button];
  };
  const results=[];
  async function tick(){await runner.inspect(driver,a,catalog.generic,()=>true,(k,r)=>results.push([k,r]));}
  await tick();await tick();assert.equal(clicks,2);assert.deepEqual(results.map(x=>x[1]),['已尝试','页面已消失','已尝试','页面已消失']);
  layer=0;await tick();assert.equal(clicks,2);runner.enter('home');runner.enter(a.bundle);await tick();assert.equal(clicks,3);
});
test('stopped or replaced sessions invalidate waiting jobs before dispatch',async()=>{
  const {api,catalog}=setup();const a=structuredClone(fixture);const q=new api.SerialQueue();const ex=new api.ActionExecutor();
  let release;const gate=q.run(()=>new Promise(r=>release=r));await Promise.resolve();
  let valid=true,clicks=0;const b=node('关闭','hs_layer_one');b.click=async()=>{clicks++;};
  const queued=q.run(()=>ex.inspect(page([node('活动广告'),b],a.bundle),a,catalog.generic,()=>valid,()=>{}));
  valid=false;release();await gate;await queued;assert.equal(clicks,0);
});
test('foreground or page changes at the last check cancel the click',async()=>{
  const {api,catalog}=setup();const a=structuredClone(fixture);
  for(const mode of ['focus','page','stop']){
    let calls=0,reads=0,valid=true,clicks=0;
    const b=node('关闭','hs_layer_one');b.click=async()=>{clicks++;};
    const driver=page([],a.bundle);
    driver.findWindow=async()=>{calls++;if(calls===2){if(mode==='focus')return null;if(mode==='stop')valid=false;}
      return {isFocused:async()=>true,getBundleName:async()=>a.bundle};};
    driver.findComponents=async(sel)=>sel.filter==='desc'?[]:[node((++reads===2&&mode==='page')?'普通引导':'活动广告'),b];
    await new api.ActionExecutor().inspect(driver,a,catalog.generic,()=>valid,()=>{});
    assert.equal(clicks,0,mode);
  }
});
test('an unreadable or protected post-click page never confirms closure',async()=>{
  const {api,catalog,context}=setup();context.setTimeout=fn=>queueMicrotask(fn);
  for(const after of [[],[node('用户协议')],[node('其他页面')]]){
    const a=structuredClone(fixture);let clicked=false;const b=node('关闭','hs_layer_one');b.click=async()=>{clicked=true;};
    const driver=page([],a.bundle);driver.findComponents=async(sel)=>sel.filter==='desc'?[]:clicked?after:[node('活动广告'),b];
    const logs=[];await new api.ActionExecutor().inspect(driver,a,catalog.generic,()=>true,(k,r)=>logs.push(r));
    assert.deepEqual(logs,['已尝试','结果不明']);
  }
});
test('200 × 20 configuration validates once and hot loops inspect only the foreground bucket',async(t)=>{
  const {repo,api,context,catalog}=setup();
  const apps=Array.from({length:200},(_,i)=>({...fixture,bundle:'perf.app'+i,rules:Array.from({length:20},(_,j)=>({
    ...fixture.rules[0],key:'r'+j,must:[{field:'text',mode:'exact',value:'活动广告'+j}]}))}));
  const raw=JSON.stringify({schema:1,apps});const start=performance.now();repo.commit(repo.preview(raw));
  const ms=performance.now()-start;let largeReads=0;
  const orig=context.readConfigFile;context.readConfigFile=(d,k)=>{if(k!=='store.head')largeReads++;return orig(d,k);};
  const selected=repo.index.get('perf.app137');assert.equal(selected.rules.length,20);
  for(const a of repo.index.values()){if(a!==selected)Object.defineProperty(a,'rules',{get(){throw Error('foreign rules inspected');}});}
  const p=await api.readPage(page([node('活动广告13'),node('关闭','hs_layer_one')],selected.bundle),selected);
  for(let i=0;i<100;i++){repo.refresh();assert.equal(api.choose(p,repo.index.get(selected.bundle),catalog.generic)?.rule.key,'r13');}
  assert.equal(largeReads,0);t.diagnostic('4000 rules, '+Buffer.byteLength(raw)+' bytes, import+verify+index '+ms.toFixed(1)+' ms; 100 hot passes, 0 section reads');
});





test('first migration has a recovery pair and a failed head switch preserves the prior backup',()=>{
  const {api,catalog,repo,context,files}=setup();
  const initial=JSON.parse(repo.stamp);
  assert.notEqual(initial.backup,-1);
  const save=context.writeState;
  context.writeState=(d,k,v)=>{if(k==='store.head')throw Error('power loss');save(d,k,v);};
  assert.throws(()=>repo.commit(repo.preview(JSON.stringify({schema:1,apps:[fixture]}))));
  files.set('personal.'+initial.slot,'!');
  const recovered=new api.RuleRepository('/mock',catalog);recovered.refresh();
  assert.ok(recovered.warning);assert.equal(recovered.pack.apps.length,catalog.apps.length);
});
test('session-scoped version evidence rejects stale, incomplete and invalidated snapshots',async()=>{
  const {api,context,files}=setup();let packageChange;
  context.commonEventManager={createSubscriber:async()=>({}),subscribe:(_,cb)=>{packageChange=cb;},unsubscribe(){}};
  const gate=new api.VersionGate();
  await gate.start('/mock','new');files.set('version.complete','old');
  files.set('version.snapshot',JSON.stringify({run:'old',apps:[{bundle:fixture.bundle,name:'0.2.0'}]}));
  assert.equal(gate.allows(fixture),false);
  files.set('version.complete','new');assert.equal(gate.allows(fixture),false);
  files.set('version.snapshot',JSON.stringify({run:'new',apps:[{bundle:fixture.bundle,name:'0.2.0'}]}));
  assert.equal(gate.allows(fixture),true);assert.equal(gate.allows({...fixture,versions:['0.3.0']}),false);
  packageChange();assert.equal(gate.allows(fixture),false);assert.equal(gate.allows({...fixture,versions:[]}),true);
});
test('captured learning pauses even past 45s until cancellation; no entry, ambiguous and refused candidates report reasons',async()=>{
  const {api,repo,context,files}=setup();const bundle=repo.pack.apps[0].bundle;
  const run='1793770000000';let now=Number(run);
  context.Date={now:()=>now};files.set('active',run);
  const driver=page([],bundle);let focus=bundle, content=[];
  driver.findWindow=async()=>({isFocused:async()=>true,getBundleName:async()=>focus});
  driver.findComponents=async s=>s.filter==='desc'?[]:content;
  for(const [nodes,expected,foreign] of [
    [[node('首页')],'未出现',false],[[node('广告'),node('关闭')],'定位依据',false],
    [[node('广告'),node('跳过'),node('跳过')],'不唯一',false],[[],'未进入目标',true]
  ]){
    const session=new api.MonitorSession();focus=foreign?'other':bundle;content=nodes;
    files.set('learn',JSON.stringify({at:now,run,bundle}));
    assert.equal(await session.step(driver,repo,'/mock',run),true);
    now+=45001;assert.equal(await session.step(driver,repo,'/mock',run),false);
    assert.match(api.pending('/mock').message,new RegExp(expected));now+=10;
  }
  const session=new api.MonitorSession();focus=bundle;let clicks=0;
  const skip=node('跳过');skip.click=async()=>{clicks++;content=[node('首页')];};content=[node('广告'),skip];
  files.set('learn',JSON.stringify({at:now,run,bundle}));
  assert.equal(await session.step(driver,repo,'/mock',run),true);assert.equal(api.pending('/mock').candidates.length,1);
  now+=50000;assert.equal(await session.step(driver,repo,'/mock',run),true);assert.equal(clicks,0);
  api.clearLearn('/mock');context.setTimeout=fn=>queueMicrotask(fn);assert.equal(await session.step(driver,repo,'/mock',run),false);assert.equal(clicks,1);
});
test('runner retries only five failed service calls, records code, never advances health on failure',async()=>{
  const {api,context,files,catalog}=setup();const run='1793770000000';
  files.set('active',run);files.set('learn',JSON.stringify({at:Number(run),run,bundle:fixture.bundle}));
  let tries=0,finished;context.setTimeout=fn=>queueMicrotask(fn);context.readCatalog=()=>catalog;
  context.Driver={create:()=>({findWindow:async()=>{tries++;throw Object.assign(Error('service'),{code:17000002});}})};
  context.abilityDelegatorRegistry={getArguments:()=>({parameters:{hsRun:run}}),getAbilityDelegator:()=>({
    getAppContext:()=>({getApplicationContext:()=>({filesDir:'/mock'})}),finishTest:async(msg,code)=>{finished=code;}})};
  await new api.MonitorSession().onRun();
  assert.equal(tries,5);assert.equal(finished,1);
  const h=JSON.parse(files.get('health'));assert.equal(h.phase,'需要重新激活');assert.equal(h.beat,0);
  assert.equal(api.events('/mock').length,5);assert.equal(api.events('/mock')[0].code,'17000002');
  assert.match(api.pending('/mock').message,/服务中断/);
});
test('full scan of unlabelled structural containers is not a readable result page',async()=>{
  const {api}=setup();const a=structuredClone(fixture);
  a.rules[0].absent=[{field:'desc',mode:'exact',value:'blocked'}];
  const p=await api.readPage(page([node('', '',true,false)],a.bundle),a,true);
  assert.equal(p.readable,false);assert.equal(api.confirmed(p,a.rules[0]),false);
});
