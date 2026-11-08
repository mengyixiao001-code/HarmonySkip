import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';

// Exercise the actual test runner with a changing UI and a simulated clock.
// This checks the match/click decisions independently of device permissions.
const source = readFileSync(new URL('../Assistant/entry/src/main/ets/testrunner/ProbeSession.ets', import.meta.url), 'utf8')
  .replace(/^import .*;$/gm, '').replace('export default class ProbeSession', 'class ProbeSession');
const platform = readFileSync(new URL('../Assistant/entry/src/main/ets/platform/UiService.ets', import.meta.url), 'utf8')
  .replace(/^import .*;$/gm, '').replace(/export /g, '');
const program = stripTypeScriptTypes(platform + '\n' + source) + '\nnew ProbeSession().onRun();';
const token = '1700000000000';

async function scenario(kind, options = {}) {
  let now = Number(token), clicks = 0, clickedAt = 0, inspected = 0, stopped = false, acknowledged = false;
  const bundle = 'local.harmonyskip.fixture';
  const state = new Map([['active', token]]);
  const selector = { inWindow(name) { assert.equal(name, bundle); return { id(id) { return id; } }; } };
  const element = (text, enabled = true) => ({
    getText: async () => text, getDescription: async () => options.description || '',
    isClickable: async () => true, isEnabled: async () => enabled,
    click: async () => { clicks++; clickedAt = now; acknowledged = !options.noReceipt; }
  });
  const driver = {
    findWindow: async (f) => {
      assert.equal(f.bundleName, bundle); assert.equal(f.focused, true);
      inspected++;
      if (options.disappear && inspected > 1) return null;
      return options.foreign ? null : { isFocused: async () => true, getBundleName: async () => bundle };
    },
    findComponents: async (sel) => {
      if (kind === 'onboarding') return [];
      if (sel === 'hs_receipt') return acknowledged ? [element(token)] : [];
      if (sel === 'hs_ad_marker') return [element('测试广告')];
      if (sel === 'hs_challenge') return [element(options.unstable ? String(Number(token) + inspected) : token)];
      if (sel === 'hs_splash_skip' && options.duplicates) return [element('跳过广告'), element('跳过广告')];
      if (sel === 'hs_splash_skip' && (kind === 'splash' || kind === 'ambiguous'))
        return [element('跳过广告', now - Number(token) >= 1200)];
      if (sel === 'hs_popup_close' && (kind === 'popup' || kind === 'ambiguous'))
        return [element(options.emptyLabel ? '' : '关闭广告')];
      return [];
    }
  };
  let done;
  const completion = new Promise((resolve) => { done = resolve; });
  const delegate = { getAppContext: () => ({ getApplicationContext: () => ({ filesDir: '/mock' }) }), finishTest: async (msg, code) => done({ msg, code }) };
  vm.runInNewContext(program, {
    TestRunner: class {}, Driver: { create: () => driver }, ON: selector,
    abilityDelegatorRegistry: { getArguments: () => ({ parameters: {
      '-s hsRun': token, '-s hsOrigin': options.usb ? 'usb' : ''
    } }), getAbilityDelegator: () => delegate },
    readState: (dir, key) => state.get(key) || '', writeState: (dir, key, val) => state.set(key, val),
    Date: { now: () => now }, setTimeout: (fn, ms) => { now += ms;
      if (options.cancel && !stopped) { state.set('active', 'stopped'); stopped = true; }
      queueMicrotask(fn);
    }
  });
  const result = await completion;
  return { ...result, clicks, clickedAt };
}

test('splash waits until enabled, clicks once and checks target receipt', async () => {
  const out = await scenario('splash');
  assert.equal(out.code, 0); assert.equal(out.clicks, 1);
  assert.ok(out.clickedAt >= Number(token) + 1200); assert.match(out.msg, /回执 1700000000000/);
});
test('popup closes once', async () => {
  const out = await scenario('popup');
  assert.equal(out.code, 0); assert.equal(out.clicks, 1);
});
for (const [label, kind, opts] of [
  ['onboarding skip', 'onboarding', {}], ['different app', 'popup', { foreign: true }],
  ['two eligible buttons', 'ambiguous', {}], ['window switch before click', 'popup', { disappear: true }],
  ['duplicate candidate IDs', 'popup', { duplicates: true }], ['unlabelled button', 'popup', { emptyLabel: true }],
  ['changing ad', 'popup', { unstable: true }], ['stopped during countdown', 'splash', { cancel: true }]
]) {
  test('skips ' + label, async () => {
    const out = await scenario(kind, opts);
    assert.equal(out.clicks, 0); assert.equal(out.code, 1);
  });
}
test('a dispatched click without a target receipt is a failed check', async () => {
  const out = await scenario('popup', { noReceipt: true });
  assert.equal(out.clicks, 1); assert.equal(out.code, 1);
});
test('button represented by its explicit accessibility label', async () => {
  const out = await scenario('popup', { emptyLabel: true, description: 'hs_popup_action' });
  assert.equal(out.clicks, 1); assert.equal(out.code, 0);
});
test('a USB control run is explicitly labelled in its receipt', async () => {
  const out = await scenario('popup', { usb: true });
  assert.equal(out.code, 0); assert.match(out.msg, /^USB 对照/);
});
