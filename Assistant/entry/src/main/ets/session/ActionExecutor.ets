import { BusinessError } from '@kit.BasicServicesKit';
import { Driver } from '@kit.TestKit';
import { Rule, AppProfile } from '../RuleModel';
import { sameWindow, readPage, readSnapshot } from '../platform/UiService';
import { choose, confirmed, remains } from '../rules/Recognition';

class Attempts { count: number = 0; last: number = 0; }
function actionFor(rule: Rule, builtin: Rule[]): string {
  if (rule.action && rule.action !== 'component') { return rule.action; }
  // Old learned rules keep their key, guards and attempt budget. A built-in may
  // supply its tested transport only when all recognition/result selectors match.
  const transport = builtin.find((r: Rule) => (r.action === 'nativeCenter' || r.action === 'center') &&
    JSON.stringify(r.must) === JSON.stringify(rule.must) &&
    JSON.stringify(r.absent) === JSON.stringify(rule.absent) &&
    JSON.stringify(r.target) === JSON.stringify(rule.target) &&
    JSON.stringify(r.result) === JSON.stringify(rule.result));
  return transport ? transport.action : (rule.action || 'component');
}
export class ActionExecutor {
  private bundle: string = '';
  private limits: Map<string, Attempts> = new Map();
  enter(bundle: string): void {
    // Missing focus is not evidence that the user left the app.
    if (!bundle) { return; }
    if (bundle !== this.bundle) { this.bundle = bundle; this.limits.clear(); }
  }
  async inspect(driver: Driver, app: AppProfile, generic: Rule, valid: () => boolean,
    record: (key: string, result: string, code: string) => void, builtin: Rule[] = []): Promise<void> {
    const win = await sameWindow(driver,app.bundle);
    if (!win || !valid()) { return; }
    const scanRules = builtin.concat([generic]);
    // Reject irrelevant pages with one snapshot before any live-component walk.
    let snapshot = typeof driver.dumpLayout === 'function';
    let first = choose(snapshot ? await readSnapshot(driver,app.bundle) : await readPage(driver,app,false,scanRules),app,generic,builtin);
    if (first && snapshot && actionFor(first.rule,builtin) !== 'center' && actionFor(first.rule,builtin) !== 'nativeCenter') {
      snapshot = false;
      first = choose(await readPage(driver,app,false,scanRules),app,generic,builtin);
    }
    if (!first) { return; }
    const r = first.rule;
    const action = actionFor(r,builtin);
    const budget = this.limits.get(r.key) || new Attempts();
    if (budget.count >= r.maxAttempts || Date.now() - budget.last < r.cooldownMs) { return; }
    if (!await win.isFocused() || !valid()) { return; }
    const second = choose(snapshot ? await readSnapshot(driver,app.bundle) : await readPage(driver,app,false,scanRules),app,generic,builtin);
    if (!second || second.rule.key !== r.key || second.node.id !== first.node.id ||
      second.node.text !== first.node.text || second.node.desc !== first.node.desc ||
      second.node.type !== first.node.type) { return; }
    const centerAction = action === 'center' || action === 'nativeCenter';
    const handle = second.node.handle;
    const point = centerAction ? (snapshot ? second.node.point : (handle ? await handle.getBoundsCenter() : undefined)) : undefined;
    if (centerAction && !point) { return; }
    if (snapshot && (!first.node.point || !point || first.node.point.x !== point.x || first.node.point.y !== point.y)) { return; }
    if (!await sameWindow(driver,app.bundle) || !await win.isFocused() || !valid()) { return; }
    budget.count++; budget.last = Date.now(); this.limits.set(r.key,budget);
    record(r.key,'已尝试','');
    // No asynchronous work between the final cancellation check and dispatch.
    try {
      if (!valid()) { return; }
      if (point) { await driver.click(point.x,point.y); }
      else if (handle) { await handle.click(); }
      else { throw new Error('Target unavailable'); }
      await new Promise<void>((done) => { setTimeout(done,400); });
      let outcome = '结果不明';
      if (valid() && await win.isFocused() && await sameWindow(driver,app.bundle)) {
        const after = snapshot ? await readSnapshot(driver,app.bundle) : await readPage(driver,app,true,scanRules);
        if (!!await sameWindow(driver,app.bundle) && await win.isFocused() && valid()) {
          outcome = remains(after,r) ? '未关闭：按钮仍在' : confirmed(after,r) ? '页面已消失' : '结果不明';
        }
      }
      record(r.key,outcome,'');
    } catch (e) {
      record(r.key,'结果不明',String((e as BusinessError).code || 'SERVICE')); throw e as Error;
    }
  }
}
