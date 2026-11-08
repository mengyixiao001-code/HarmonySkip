import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
test('both runner modes catch asynchronous startup failure and finish the test',async()=>{
 const raw=readFileSync(new URL('../Assistant/entry/src/main/ets/testrunner/ProbeRunner.ets',import.meta.url),'utf8')
  .replace(/^import .*;$/gm,'').replace('export default ','')
  .replace(/import\('\.\/(?:MonitorSession|ProbeSession)'\)/g,'loadSession()');
 const program=new vm.Script(stripTypeScriptTypes(raw)+'\nthis.Runner=ProbeRunner;');
 for(const mode of ['monitor','probe']){
  const finished=[];const ctx={loadSession:async()=>({default:class{async onRun(){throw Error('startup failed');}}}),
   abilityDelegatorRegistry:{getArguments:()=>({parameters:{hsMode:mode}}),getAbilityDelegator:()=>({finishTest:(msg,code)=>finished.push(code)})}};
  program.runInNewContext(ctx);new ctx.Runner().onRun();await new Promise(setImmediate);
  assert.deepEqual(finished,[1],mode);
 }
});
