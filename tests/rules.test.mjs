import assert from 'node:assert/strict';
import test from 'node:test';
import { harness, node, page } from './runtime.mjs';
const { api, catalog, context } = harness();
const matches = async (driver, app) => api.choose(await api.readPage(driver, app), app, catalog.generic)?.node.handle;
test('the requested native apps including QQ Music are present, banks await reviewed rules', () => {
  const config = api.migrate("",catalog);
  assert.equal(config.apps.length, 9);
  assert.equal(config.apps.filter((x) => x.bank).length, 2);
  assert.ok(config.apps.filter((x) => x.bank).every((x) => !x.enabled && x.rules.length === 0));
});
test('an explicit ad and a unique skip button match', async () => {
  const app = new api.AppProfile('淘宝', 'taobao');
  const skip = node('跳过 3秒', 'ad-skip');
  assert.equal(await matches(page([node('广告'), skip], app.bundle), app), skip);
});
for (const [title, nodes] of [
  ['ordinary onboarding skip', [node('跳过', 'onboarding')]],
  ['generic close', [node('广告'), node('关闭', 'dialog')]],
  ['ambiguous skip', [node('广告'), node('跳过', 'a'), node('跳过', 'b')]],
  ['disabled countdown', [node('广告'), node('跳过', 'a', false)]],
  ['payment page', [node('广告'), node('跳过'), node('确认付款')]],
  ['consent page', [node('广告'), node('跳过'), node('隐私政策')]]
]) {
  test('ignores ' + title, async () => {
    const app = new api.AppProfile('京东', 'jd');
    assert.equal(await matches(page(nodes, app.bundle), app), undefined);
  });
}
test('bank requires an enabled reviewed rule with matching ID, text and ad anchor', async () => {
  const app = new api.AppProfile('中国银行', 'boc', true);
  const close = node('关闭', 'ad-close');
  const driver = page([node('广告'), close], app.bundle);
  assert.equal(await matches(driver, app), undefined);
  app.enabled = true;
  assert.equal(await matches(driver, app), undefined);
  const rule = new api.AdRule();
  rule.id = 'ad-close'; rule.text = '关闭';
  app.rules.push(api.learnedRule(rule,'bank.1'));
  assert.equal(await matches(driver, app), close);
  assert.equal(await matches(page([close], app.bundle), app), undefined);
  close.getId = async () => 'different-dialog';
  assert.equal(await matches(driver, app), undefined);
});
test('disabled app never clicks, including saved rules', async () => {
  const app = new api.AppProfile('微博', 'weibo');
  app.enabled = false;
  assert.equal(await matches(page([node('广告'), node('跳过')], app.bundle), app), undefined);
});
test('Weibo ad without a component ID remains learnable and matches only explicit skip text', async () => {
  const app = new api.AppProfile('微博', 'com.sina.weibo.stage');
  const skip = node('跳过', '');
  const driver = page([node('广告'), skip], app.bundle);
  const saved = api.capture(await api.readPage(driver,app),app);
  assert.equal(saved.candidates.length, 1);
  assert.equal(saved.candidates[0].id, '');
  app.bank = true; app.rules = saved.candidates.map((r) => api.learnedRule(r,'weibo.1'));
  assert.equal(await matches(driver, app), skip);
  assert.equal(await matches(page([node('跳过')], app.bundle), app), undefined);
  assert.equal(await matches(page([node('广告'), node('关闭')], app.bundle), app), undefined);
});
test('learning retries when the ad has not appeared yet', async () => {
  const app = new api.AppProfile('微博', 'weibo');
  const result = api.capture(await api.readPage(page([node('首页')],app.bundle),app),app);
  assert.equal(result.candidates.length,0);
});
test('component text reads stay sequential for the actual UiTest service', async () => {
  const app = new api.AppProfile('微博', 'weibo');
  let inFlight = false;
  const guarded = (text) => {
    const element = node(text);
    element.getText = async () => {
      assert.equal(inFlight, false, 'UiTest rejects concurrent calls');
      inFlight = true;
      await new Promise((resolve) => setTimeout(resolve, 1));
      inFlight = false;
      return text;
    };
    return element;
  };
  assert.ok(await matches(page([guarded('广告'), guarded('跳过')], app.bundle), app));
});
