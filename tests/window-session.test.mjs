import assert from 'node:assert/strict';
import test from 'node:test';
import { harness, node, page } from './runtime.mjs';

async function session(outcomes, learning = false) {
  const env = harness();
  const {api,context,files,catalog} = env;
  const repo = new api.RuleRepository('/mock',catalog);
  repo.refresh(true);
  const run = '1793840000000';
  files.set('active',run);
  if (learning) files.set('learn',JSON.stringify({run,at:Date.now(),bundle:catalog.apps[0].bundle}));
  let calls = 0;
  let finished;
  const healthWrites = [];
  const write = context.writeState;
  context.writeState = (dir,key,value) => {
    if (key === 'health') healthWrites.push(JSON.parse(value));
    write(dir,key,value);
  };
  context.Driver = {create:() => ({
    findWindow:async () => {
      const code = outcomes[calls++];
      if (code) throw Object.assign(Error('test service response'),{code});
      return {isFocused:async () => true,getBundleName:async () => 'unmanaged.app'};
    }
  })};
  context.setTimeout = callback => {
    if (calls >= outcomes.length) files.set('active','stopped');
    queueMicrotask(callback);
  };
  context.abilityDelegatorRegistry = {
    getArguments:() => ({parameters:{hsRun:run}}),
    getAbilityDelegator:() => ({
      getAppContext:() => ({getApplicationContext:() => ({filesDir:'/mock'})}),
      finishTest:async (message,code) => { finished = {message,code}; }
    })
  };
  await new api.MonitorSession().onRun();
  return {...env,calls,finished,healthWrites};
}

test('more than five stale windows recover without connection faults, logs or false successful checks',async () => {
  const out = await session([...Array(8).fill(17000004),0]);
  assert.equal(out.calls,9);
  assert.equal(out.finished.code,0);
  assert.equal(out.api.events('/mock').length,0);
  assert.equal(out.healthWrites.length,1);
  assert.equal(out.healthWrites[0].successfulChecks,1);
  assert.equal(out.healthWrites[0].faults,0);
  assert.equal(out.healthWrites[0].phase,'运行中');
});

test('window invalidation during learning preserves the request and recovers learning status',async () => {
  const out = await session([...Array(6).fill(17000004),0],true);
  assert.equal(out.finished.code,0);
  assert.equal(out.healthWrites.at(-1).phase,'学习中');
  assert.ok(JSON.parse(out.files.get('learn')).at);
  assert.equal(out.files.get('proposal'),undefined);
});

test('stopping during stale-window recovery finishes without faking a service heartbeat',async () => {
  const out = await session([17000004]);
  assert.equal(out.calls,1);
  assert.equal(out.finished.code,0);
  assert.equal(out.healthWrites.length,0);
  assert.equal(out.api.events('/mock').length,0);
});

test('stale-window responses reset consecutive connection failures, while real failures remain recorded',async () => {
  const out = await session([17000002,17000002,17000004,...Array(4).fill(17000002),0]);
  assert.equal(out.calls,8);
  assert.equal(out.finished.code,0);
  assert.equal(out.api.events('/mock').length,6);
  assert.equal(out.healthWrites.at(-1).faults,6);
  assert.equal(out.healthWrites.at(-1).phase,'运行中');
});

test('five consecutive real service failures still stop and request reactivation',async () => {
  const out = await session(Array(5).fill(17000002));
  assert.equal(out.calls,5);
  assert.equal(out.finished.code,1);
  assert.equal(out.healthWrites.at(-1).phase,'需要重新激活');
  assert.equal(out.api.events('/mock').length,5);
});

test('window destroyed at the final focus recheck dispatches no stale click',async () => {
  const {api,catalog} = harness();
  const app = new api.AppProfile('样本','sample.app');
  let focusReads = 0;
  let clicks = 0;
  const button = node('跳过','skip');
  button.click = async () => { clicks++; };
  const driver = page([node('广告'),button],app.bundle);
  driver.findWindow = async () => ({
    getBundleName:async () => app.bundle,
    isFocused:async () => {
      if (++focusReads === 2) throw Object.assign(Error('destroyed'),{code:17000004});
      return true;
    }
  });
  const logs = [];
  await assert.rejects(new api.ActionExecutor().inspect(driver,app,catalog.generic,() => true,
    (...args) => logs.push(args)),error => error.code === 17000004);
  assert.equal(clicks,0);
  assert.equal(logs.length,0);
});

test('window loss after dispatch retains an unknown result and prevents another attempt in the same visit',async () => {
  const {api,catalog,context,files} = harness();
  context.setTimeout = callback => queueMicrotask(callback);
  const app = new api.AppProfile('样本','sample.app');
  const action = new api.ActionExecutor();
  action.enter(app.bundle);
  let clicks = 0;
  let disappeared = false;
  const button = node('跳过','skip');
  button.click = async () => { clicks++; disappeared = true; };
  const driver = page([node('广告'),button],app.bundle);
  driver.findWindow = async () => ({
    getBundleName:async () => app.bundle,
    isFocused:async () => {
      if (disappeared) throw Object.assign(Error('destroyed'),{code:17000004});
      return true;
    }
  });
  const record = (key,result,code) => api.logEvent('/mock','run',app.bundle,key,result,code);
  await assert.rejects(action.inspect(driver,app,catalog.generic,() => true,record),
    error => error.code === 17000004);
  assert.deepEqual(Array.from(api.events('/mock'),e => e.result),['已尝试','结果不明']);
  assert.equal(api.events('/mock')[1].code,'17000004');
  const old = JSON.parse(files.get('events'));
  old[0].at -= 2 * 3600000;
  files.set('events',JSON.stringify(old));
  files.set('logs.sweptAt',String(Date.now() - 2 * 3600000));
  api.sweepLogs('/mock');
  assert.equal(api.events('/mock').length,1);
  assert.equal(api.events('/mock')[0].result,'结果不明');
  disappeared = false;
  await action.inspect(driver,app,catalog.generic,() => true,record);
  assert.equal(clicks,1);
});
