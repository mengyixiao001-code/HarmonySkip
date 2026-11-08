import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { harness } from './runtime.mjs';

test('recoverable active configuration can be saved even when previous pointer is corrupt',()=>{
  const {api,files,catalog}=harness();
  const repo=new api.RuleRepository('/mock',catalog);repo.refresh(true);
  const h=JSON.parse(files.get('store.head'));
  files.set('personal.'+h.slot,'broken');
  files.set('store.previous','broken');
  const recovered=new api.RuleRepository('/mock',catalog);recovered.refresh();
  assert.ok(recovered.warning);
  const pack=structuredClone(recovered.pack);pack.apps[0].enabled=false;
  recovered.commit(pack);
  const next=new api.RuleRepository('/mock',catalog);next.refresh();
  assert.equal(next.pack.apps[0].enabled,false);
  files.set('store.head','broken');
  const fallback=new api.RuleRepository('/mock',catalog);fallback.refresh();
  assert.equal(fallback.pack.apps.length,catalog.apps.length);
});

test('failed repair commit preserves a valid recovery pointer',()=>{
  const {api,files,catalog,context}=harness();
  const repo=new api.RuleRepository('/mock',catalog);repo.refresh(true);
  const h=JSON.parse(files.get('store.head'));
  files.set('personal.'+h.slot,'broken');files.set('store.previous','broken');
  const recovered=new api.RuleRepository('/mock',catalog);recovered.refresh();
  const write=context.writeState;
  context.writeState=(d,k,v)=>{if(k==='store.head')throw Error('disk full');write(d,k,v);};
  assert.throws(()=>recovered.commit(recovered.pack));
  files.set('store.head','broken');
  const fallback=new api.RuleRepository('/mock',catalog);fallback.refresh();
  assert.equal(fallback.pack.apps.length,catalog.apps.length);
});

test('runner attaches its rejection handler to an asynchronous monitor startup',async()=>{
  const raw=readFileSync(new URL('../Assistant/entry/src/main/ets/testrunner/ProbeRunner.ets',import.meta.url),'utf8');
  const source=raw.replace(/^import .*;$/gm,'').replace('export default class','class')
    .replace("import('./MonitorSession')",'loadMonitor()');
  let finished;

  const chained={then(resolve,reject){reject(Error('startup failed'));}};
  // Promise resolution assimilates the returned thenable only when onRun is returned.
  const context={loadMonitor:()=>Promise.resolve({default:class{onRun(){return chained;}}}),
    abilityDelegatorRegistry:{getArguments:()=>({parameters:{hsMode:'monitor'}}),getAbilityDelegator:()=>({finishTest(message,code){finished={message,code};return Promise.resolve();}})}};
  vm.runInNewContext(stripTypeScriptTypes(source)+';new ProbeRunner().onRun();',context);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(finished?.code,1);
});
