import assert from 'node:assert/strict';
import test from 'node:test';
import { harness } from './runtime.mjs';

const hour = 60 * 60 * 1000;
function logClock() {
  const env = harness();
  let now = 1793780000000;
  env.context.Date = { now: () => now };
  return { ...env, advance: (ms) => { now += ms; }, now: () => now };
}

test('normal records clear at sixty minutes without requiring another click; exceptions survive', () => {
  const {api,files,advance} = logClock();
  api.logEvent('/mock','run','app','r1','已尝试','');
  api.logEvent('/mock','run','app','r1','确认关闭','');
  api.logEvent('/mock','run','app','r2','结果不明','');
  api.logEvent('/mock','run','app','','连接异常','17000004');
  advance(hour - 1);
  api.sweepLogs('/mock');
  assert.equal(api.events('/mock').length,4);
  advance(1);
  api.sweepLogs('/mock');
  assert.deepEqual(Array.from(api.events('/mock'), e => e.result),['结果不明','连接异常']);
  const after = files.get('events');
  advance(2 * hour);
  api.sweepLogs('/mock');
  assert.equal(files.get('events'),after);
});

test('normal limit never evicts older exceptions, including more than eighty exceptions', () => {
  const {api} = logClock();
  for (let i = 0; i < 100; i++) api.logEvent('/mock','run','app','error'+i,'连接异常','17000004');
  for (let i = 0; i < 100; i++) api.logEvent('/mock','run','app','normal'+i,'确认关闭','');
  const rows = Array.from(api.events('/mock'));
  assert.equal(rows.filter(api.normalEvent).length,80);
  const errors = rows.filter(e => !api.normalEvent(e));
  assert.equal(errors.length,100);
  assert.equal(errors[0].key,'error0');
});

test('upgrade cleans expired legacy normal records and preserves unknown or coded outcomes', () => {
  const {api,files,now} = logClock();
  const old = now() - 2 * hour;
  files.set('events',JSON.stringify([
    {at:old,result:'确认关闭',code:''},
    {at:old+1,result:'其他故障',code:''},
    {at:old+2,result:'确认关闭',code:'UNEXPECTED'}
  ]));
  api.sweepLogs('/mock');
  assert.deepEqual(Array.from(api.events('/mock'),e => e.result),['其他故障','确认关闭']);
  assert.equal(Number(files.get('logs.sweptAt')),now());
});

test('the sweep schedule persists across sessions and resets safely on a backward clock change', () => {
  const {api,files,advance,now} = logClock();
  api.sweepLogs('/mock');
  const first = files.get('logs.sweptAt');
  advance(30 * 60 * 1000);
  api.logEvent('/mock','new-run','app','r1','确认关闭','');
  api.sweepLogs('/mock');
  assert.equal(files.get('logs.sweptAt'),first);
  advance(30 * 60 * 1000);
  api.sweepLogs('/mock');
  assert.equal(api.events('/mock').length,0);
  advance(-hour);
  api.sweepLogs('/mock');
  assert.equal(Number(files.get('logs.sweptAt')),now());
});

test('manual clearing reclaims the stored records on maintenance, including exception records', () => {
  const {api,files,now,advance} = logClock();
  api.logEvent('/mock','run','app','','连接异常','17000004');
  files.set('cleared',String(now()));
  advance(1);
  api.sweepLogs('/mock');
  assert.equal(files.get('events'),'[]');
  api.logEvent('/mock','run','app','','连接异常','17000002');
  assert.equal(api.events('/mock').length,1);
});
