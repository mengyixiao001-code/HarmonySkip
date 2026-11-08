import test from 'node:test';
import assert from 'node:assert/strict';
import {harness, node as liveNode, page as livePage} from './runtime.mjs';
const bundle='com.sina.weibo.stage';
const node=(text,children=[])=>({attributes:{text,visible:'true',enabled:'true',clickable:'true',bounds:'[10,10][80,80]'},children});
const tree=children=>({attributes:{bundleName:bundle,focused:'true',visible:'true'},children});

test('hidden ancestors cannot contribute skip targets or ad anchors',()=>{
 const {api,catalog}=harness();const app=new api.AppProfile('微博',bundle);
 const hidden=node('',[node('广告'),node('跳过')]);hidden.attributes.visible='false';
 const p=api.parseSnapshot(JSON.stringify(tree([hidden,node('首页')])),bundle);
 assert.equal(api.choose(p,app,catalog.generic),undefined);
 assert.equal(p.nodes.some(n=>n.text==='跳过'),false);
});

test('oversized or malformed snapshots cancel the whole observation without killing the service',()=>{
 const {api}=harness();
 for(const raw of [JSON.stringify(tree([node('广告'),node('跳过'),...Array.from({length:2001},()=>node('内容'))])), '{', '{}','null']){
  const p=api.parseSnapshot(raw,bundle);assert.equal(p.readable,false);assert.equal(p.nodes.length,0);
 }
});

test('learning rejects a fresh heartbeat from the previous build',()=>{
 const {api,files}=harness();const run=String(Date.now());files.set('active',run);
 files.set('health',JSON.stringify({run,build:'old',phase:'运行中',beat:Date.now()}));
 assert.throws(()=>api.beginLearn('/mock',bundle));assert.equal(files.has('learn'),false);
});

test('a temporary missing foreground window must not reset the attempt budget',async()=>{
 const {api,catalog,context}=harness();context.setTimeout=fn=>queueMicrotask(fn);
 const app=new api.AppProfile('微博',bundle);let clicks=0;
 const button=liveNode('跳过');button.click=async()=>{clicks++;};
 const driver=livePage([liveNode('广告'),button],bundle);const ex=new api.ActionExecutor();
 ex.enter(bundle);await ex.inspect(driver,app,catalog.generic,()=>true,()=>{});
 ex.enter('');ex.enter(bundle);await ex.inspect(driver,app,catalog.generic,()=>true,()=>{});
 assert.equal(clicks,1);
 ex.enter('launcher');ex.enter(bundle);await ex.inspect(driver,app,catalog.generic,()=>true,()=>{});
 assert.equal(clicks,2);
});
