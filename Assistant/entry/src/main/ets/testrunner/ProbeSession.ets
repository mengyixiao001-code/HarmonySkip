import { uiService, sameWindow } from '../platform/UiService';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, Component, ON } from '@kit.TestKit';
import { readState, writeState } from '../ProbeState';

const FIXTURE = 'local.harmonyskip.fixture';
const BUDGET = 90000;
function pause(ms: number): Promise<void> { return new Promise<void>((done) => { setTimeout(done, ms); }); }

class Candidate {
  button: Component;
  key: string;
  id: string;
  constructor(button: Component, key: string, id: string) {
    this.button = button; this.key = key; this.id = id;
  }
}

async function one(driver: Driver, id: string): Promise<Component | undefined> {
  const hits = await driver.findComponents(ON.inWindow(FIXTURE).id(id));
  return hits && hits.length === 1 ? hits[0] : undefined;
}

async function candidate(driver: Driver): Promise<Candidate | undefined> {
  const win = await driver.findWindow({ bundleName: FIXTURE, focused: true });
  if (!win || !(await win.isFocused()) || (await win.getBundleName()) !== FIXTURE) { return undefined; }
  const marker = await one(driver, 'hs_ad_marker');
  if (!marker || (await marker.getText()) !== '测试广告') { return undefined; }
  const session = await one(driver, 'hs_challenge');
  if (!session) { return undefined; }
  const key = await session.getText();
  if (!/^[0-9]{13}$/.test(key)) { return undefined; }
  const skips = await driver.findComponents(ON.inWindow(FIXTURE).id('hs_splash_skip'));
  const closes = await driver.findComponents(ON.inWindow(FIXTURE).id('hs_popup_close'));
  const skipCount = skips ? skips.length : 0;
  const closeCount = closes ? closes.length : 0;
  if (skipCount + closeCount !== 1) { return undefined; }
  const splash = skipCount === 1;
  const btn = splash && skips ? skips[0] : (closes ? closes[0] : undefined);
  if (!btn || !(await btn.isEnabled()) || !(await btn.isClickable())) { return undefined; }
  const label = await btn.getText();
  if (label !== (splash ? '跳过广告' : '关闭广告')) {
    if (label !== '' || (await btn.getDescription()) !== (splash ? 'hs_splash_action' : 'hs_popup_action')) {
      return undefined;
    }
  }
  return new Candidate(btn, key, splash ? '开屏' : '弹窗');
}

export default class ProbeSession {
  onPrepare(): void {}
  onRun(): void { uiService.run(() => this.runProbe()); }

  private async runProbe(): Promise<void> {
    const delegate = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments().parameters;
    const run = args['-s hsRun'] || args['hsRun'];
    const usb = (args['-s hsOrigin'] || args['hsOrigin']) === 'usb';
    const prefix = usb ? 'USB 对照 · ' : '';
    const dir = delegate.getAppContext().getApplicationContext().filesDir;
    let endMessage = '超时，未在测试页确认点击';
    let success = false;
    try {
      if (typeof run !== 'string' || !/^[0-9]{13}$/.test(run)) {
        await delegate.finishTest('会话编号无效', 1);
        return;
      }
      // USB control runs must be armed by their caller, just like on-device runs.
      if (readState(dir, 'active') !== run) {
        await delegate.finishTest('无有效会话', 1);
        return;
      }
      writeState(dir, run, usb ? 'USB 对照进行中' : '验证中，请在断开调试后打开轻跳测试页。');
      const driver = Driver.create();
      const until = Date.now() + BUDGET;
      while (Date.now() < until && readState(dir, 'active') === run) {
        let hit: Candidate | undefined = undefined;
        try {
          const first = await candidate(driver);
          if (first) {
            const again = await candidate(driver);
            if (again && again.key === first.key && again.id === first.id) { hit = again; }
          }
        } catch (_) { /* 窗口切换、控件消失时，重新观察。 */ }
        if (!hit) { await pause(350); continue; }
        if (Date.now() >= until || readState(dir, 'active') !== run) { break; }
        if (!await sameWindow(driver,FIXTURE) || readState(dir,'active') !== run) { break; }
        await hit.button.click();
        // 一次会话最多发出一次点击。只有另一应用显示匹配回执才算成功。
        endMessage = '已尝试点击，但未读到匹配回执';
        for (let i = 0; i < 8; i++) {
          await pause(250);
          const receipt = await one(driver, 'hs_receipt');
          if (receipt && (await receipt.getText()) === hit.key) {
            success = true;
            endMessage = hit.id + '验证成功，回执 ' + hit.key;
            break;
          }
        }
        break;
      }
      if (readState(dir, 'active') !== run) { endMessage = '验证已停止'; success = false; }
    } catch (_) { endMessage = '验证失败，测试服务暂不可用'; }
    writeState(dir, run, prefix + endMessage);
    await delegate.finishTest(prefix + endMessage, success ? 0 : 1);
  }
}
