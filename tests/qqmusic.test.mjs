import assert from 'node:assert/strict';
import test from 'node:test';
import { harness, node, page } from './runtime.mjs';
const bundle='com.tencent.hm.qqmusic';
test('QQ Music joins an existing list without altering its switches or learned rules',()=>{
  const {api,catalog}=harness();
  const old=structuredClone(catalog);
  old.apps=old.apps.filter(a=>a.bundle!==bundle);
  old.apps[0].enabled=false;
  old.apps.find(a=>a.bundle==='com.sina.weibo.stage').rules=[api.learnedRule({id:'',text:'跳过',anchor:'广告'},'saved.weibo')];
  const expected=JSON.stringify(old.apps);
  const merged=api.mergeCatalog(old,catalog);
  assert.equal(JSON.stringify(merged.apps.filter(a=>a.bundle!==bundle)),expected);
  assert.equal(merged.apps.find(a=>a.bundle===bundle).enabled,true);
});
test('QQ Music uses a unique explicit-ad skip and respects protection and ambiguity',async()=>{
  const {api,catalog}=harness();
  const app=catalog.apps.find(a=>a.bundle===bundle);
  const skip=node('跳过','');
  const match=async rows=>api.choose(await api.readPage(page(rows,bundle),app),app,catalog.generic);
  assert.equal((await match([node('广告'),skip])).node.handle,skip);
  for(const rows of [[skip],[node('广告'),skip,node('跳过')],[node('广告'),skip,node('用户协议')],[node('广告'),node('关闭')]]) {
    assert.equal(await match(rows),undefined);
  }
  app.enabled=false;
  assert.equal(await match([node('广告'),skip]),undefined);
});

test('observed interactive splash requires both page anchors and a unique skip',async()=>{
 const {api,catalog}=harness();
 const base=catalog.apps.find(a=>a.bundle===bundle);
 const app=structuredClone(base);app.rules=[];
 const button=node('跳过','');
 const marker=node('互动广告｜已 WIFI 预加载','topAdText',true,false);
 const scan=async rows=>api.choose(await api.readPage(page(rows,bundle),app,false,base.rules),app,catalog.generic,base.rules);
 assert.equal((await scan([marker,button])).rule.key,'qqmusic.splash.interactive');
 assert.equal(await scan([node('互动广告｜已 WIFI 预加载','wrong'),button]),undefined);
 assert.equal(await scan([node('其他页面','topAdText'),button]),undefined);
 assert.equal(await scan([marker,button,node('跳过')]),undefined);
 assert.equal(await scan([marker,button,node('确认付款')]),undefined);
 assert.equal(api.choose(await api.readPage(page([marker,button],bundle),app),app,catalog.generic),undefined);
});

test('short splash reads IDs only for anchors and action state only for targets',async()=>{
 const {api,catalog}=harness();const app=structuredClone(catalog.apps.find(a=>a.bundle===bundle));
 const builtins=app.rules;app.rules=[];
 const marker=node('互动广告｜已 WIFI 预加载','topAdText');
 marker.isEnabled=async()=>{throw Error('unneeded marker state read');};
 const unrelated=node('互动广告说明','interactiveDesc');
 unrelated.getId=async()=>{throw Error('unneeded unrelated ID read');};
 unrelated.isEnabled=async()=>{throw Error('unneeded unrelated state read');};
 const skip=node('跳过');
 const p=await api.readPage(page([marker,unrelated,skip],bundle),app,false,builtins);
 assert.equal(api.choose(p,app,catalog.generic,builtins).node.handle,skip);
});

test('QQ center action uses the live target point, keeps the component path for other rules',async()=>{
 const {api,catalog,context}=harness();context.setTimeout=fn=>queueMicrotask(fn);
 const base=structuredClone(catalog.apps.find(a=>a.bundle===bundle));base.rules[0].action='center';const app=structuredClone(base);app.rules=[];
 let clicked=false;const target=node('跳过');target.click=async()=>{throw Error('component click must not be used');};
 target.getBoundsCenter=async()=>({x:1040,y:136});
 const marker=node('互动广告｜已 WIFI 预加载','topAdText');
 const driver=page([],bundle);driver.findComponents=async sel=>sel.filter==='desc'?[]:clicked?[node('首页')]:[marker,target];
 driver.click=async(x,y)=>{assert.equal(x,1040);assert.equal(y,136);clicked=true;};
 await new api.ActionExecutor().inspect(driver,app,catalog.generic,()=>true,()=>{},base.rules);
 assert.equal(clicked,true);
});
