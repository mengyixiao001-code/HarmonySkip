import test from 'node:test';
import assert from 'node:assert/strict';
import {harness, node, page} from './runtime.mjs';

const bundle='com.sina.weibo.stage';
// Label, state and bounds observed on Weibo 16.10.1; no page content is stored.
const item=(text,bounds,clickable=false)=>({attributes:{text,id:'',description:'',type:clickable?'Button':'Text',
  visible:'true',enabled:'true',clickable:String(clickable),bounds},children:[]});
const tree=(children)=>({attributes:{bundleName:bundle,focused:'true',visible:'true'},children});
const ad=(bounds='[925,185][1108,286]')=>tree([
  item('广告','[827,219][891,256]'),item('跳过',bounds,true)]);

function setup(){
  const env=harness();
  env.app=structuredClone(env.catalog.apps.find(a=>a.bundle===bundle));
  env.builtin=env.app.rules;env.app.rules=[];
  env.context.setTimeout=fn=>queueMicrotask(fn);
  env.context.fileIo={unlinkSync:()=>env.files.delete('ui-snapshot.tmp')};
  return env;
}

test('Weibo specific splash wins over generic without creating a false ambiguity',()=>{
  const {api,app,builtin,catalog}=setup();
  assert.equal(builtin[0].action,'nativeCenter');
  assert.equal(api.choose(api.parseSnapshot(JSON.stringify(ad()),bundle),app,catalog.generic,builtin).rule.key,'weibo.splash');
  const duplicate=ad();duplicate.children.push(item('跳过','[100,100][200,200]',true));
  assert.equal(api.choose(api.parseSnapshot(JSON.stringify(duplicate),bundle),app,catalog.generic,builtin),undefined);
  assert.equal(api.choose(api.parseSnapshot(JSON.stringify(ad()),bundle),app,catalog.generic,[...builtin,{...builtin[0],key:'conflict'}]),undefined);
});

test('Weibo old no-ID learned rule uses fast transport without rewriting settings or losing its budget',async()=>{
  for(const learned of [false,true]){
    const {api,app,builtin,catalog,context,files}=setup();
    if(learned)app.rules=[api.learnedRule({id:'',text:'跳过',anchor:'广告'},'learn.saved')];
    const original=JSON.stringify(app);let clicks=0;
    context.abilityDelegatorRegistry={getAbilityDelegator:()=>({getAppContext:()=>({getApplicationContext:()=>({filesDir:'/mock'})}),
      executeShellCommand:async()=>{throw Error('must use the existing Driver connection');}})};
    const driver={findWindow:async()=>({isFocused:async()=>true,getBundleName:async()=>bundle}),
      click:async(x,y)=>{assert.equal(x,1016);assert.equal(y,235);clicks++;},
      findComponents:async()=>{throw Error('short splash must not walk live components');},
      dumpLayout:async()=>{files.set('ui-snapshot.tmp',JSON.stringify(clicks?tree([item('首页','[0,0][100,100]')]):ad()));return true;}};
    const ex=new api.ActionExecutor();ex.enter(bundle);const logs=[];
    await ex.inspect(driver,app,catalog.generic,()=>true,(k,r)=>logs.push([k,r]),builtin);
    assert.equal(clicks,1);assert.deepEqual(logs,[[learned?'learn.saved':'weibo.splash','已尝试'],[learned?'learn.saved':'weibo.splash','页面已消失']]);
    clicks=0;await ex.inspect(driver,app,catalog.generic,()=>true,()=>{},builtin);assert.equal(clicks,0);
    assert.equal(JSON.stringify(app),original);assert.equal(files.has('ui-snapshot.tmp'),false);
  }
});

test('Weibo snapshots cancel changed position, duplicate, protected page, missing marker or stopped session',async()=>{
  for(const scenario of ['move','duplicate','protected','marker','stopped','foreground']){
    const {api,app,builtin,catalog,context,files}=setup();let shots=0,valid=true;
    context.abilityDelegatorRegistry={getAbilityDelegator:()=>({getAppContext:()=>({getApplicationContext:()=>({filesDir:'/mock'})}),
      executeShellCommand:async()=>{throw Error('unsafe click');}})};
    const driver={findWindow:async()=>({isFocused:async()=>true,getBundleName:async()=>scenario==='foreground'&&shots>=2?'other.app':bundle}),
      dumpLayout:async()=>{const t=ad();if(shots++===1){
        if(scenario==='move')t.children[1].attributes.bounds='[900,185][1083,286]';
        if(scenario==='duplicate')t.children.push(item('跳过','[100,100][200,200]',true));
        if(scenario==='protected')t.children.push(item('确认付款','[0,0][100,100]'));
        if(scenario==='marker')t.children.shift();
        if(scenario==='stopped')valid=false;
      }files.set('ui-snapshot.tmp',JSON.stringify(t));return true;}};
    const logs=[];await new api.ActionExecutor().inspect(driver,app,catalog.generic,()=>valid,(...x)=>logs.push(x),builtin);
    assert.deepEqual(logs,[],scenario);
  }
});

test('a personal rule with different selectors keeps component transport and all its guards',async()=>{
  const {api,app,builtin,catalog,context,files}=setup();
  const personal=api.learnedRule({id:'stable',text:'跳过',anchor:'广告'},'personal.custom');
  app.rules=[personal];let clicked=false;const button=node('跳过','stable');button.click=async()=>{clicked=true;};
  const driver=page([node('广告'),button],bundle);
  driver.dumpLayout=async()=>{const t=ad();t.children[1].attributes.id='stable';files.set('ui-snapshot.tmp',JSON.stringify(t));return true;};
  context.abilityDelegatorRegistry={getAbilityDelegator:()=>({getAppContext:()=>({getApplicationContext:()=>({filesDir:'/mock'})}),
    executeShellCommand:async()=>{throw Error('custom rule must retain its transport');}})};
  await new api.ActionExecutor().inspect(driver,app,catalog.generic,()=>true,()=>{},builtin);
  assert.equal(clicked,true);
});

test('upgrading the Weibo catalogue preserves saved rules and disabled state',()=>{
  const {api,catalog}=harness();const repo=new api.RuleRepository('/mock',catalog);repo.refresh(true);
  const saved=repo.index.get(bundle);saved.enabled=false;saved.rules=[api.learnedRule({id:'',text:'跳过',anchor:'广告'},'learn.saved')];
  repo.commit(repo.pack);const before=JSON.stringify(repo.pack);
  const next=new api.RuleRepository('/mock',catalog);next.refresh();
  assert.equal(JSON.stringify(next.pack),before);assert.equal(next.builtins.get(bundle)[0].action,'nativeCenter');
});
