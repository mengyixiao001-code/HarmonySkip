import { Rule, Feature, AdRule, AppProfile, Proposal, skipLabel, closeLabel, explicitAd } from '../RuleModel';
import { Page, SeenNode } from '../platform/UiService';

export function feature(n: SeenNode, f: Feature): boolean {
  const v = f.field === 'id' ? n.id : f.field === 'desc' ? n.desc : f.field === 'type' ? n.type : n.text;
  if (f.mode === 'skip') { return skipLabel(v); }
  if (f.mode === 'ad') { return explicitAd([v]); }
  if (f.mode === 'regex') { return new RegExp('^(?:' + f.value.slice(1,-1) + ')$').test(v); }
  return v === f.value;
}
function present(p: Page, f: Feature): boolean { return p.nodes.some((n: SeenNode) => feature(n,f)); }
function target(n: SeenNode, r: Rule): boolean { return r.target.every((f: Feature) => feature(n,f)); }
export class Decision {
  rule: Rule;
  node: SeenNode;
  constructor(rule: Rule,node: SeenNode) { this.rule = rule; this.node = node; }
}
export function choose(p: Page, app: AppProfile, generic: Rule, builtin: Rule[] = []): Decision | undefined {
  if (!app.enabled || !p.readable || p.protectedPage) { return undefined; }
  const overrides = new Set<string>(app.rules.map((r: Rule) => r.key));
  const defaults = app.bank ? [] : builtin.filter((r: Rule) => !overrides.has(r.key));
  const fallback = app.bank || overrides.has(generic.key) || defaults.some((r: Rule) => r.key === generic.key) ? [] : [generic];
  const tiers: Rule[][] = [app.rules,defaults,fallback];
  for (const rules of tiers) {
    let found: Decision | undefined = undefined;
    for (const r of rules) {
      if (!r.must.every((f: Feature) => present(p,f)) || r.absent.some((f: Feature) => present(p,f))) { continue; }
      const hits = p.nodes.filter((n: SeenNode) => n.enabled && target(n,r));
      if (hits.length > 1 || (hits.length > 0 && found)) { return undefined; }
      if (hits.length === 1) { found = new Decision(r,hits[0]); }
    }
    if (found) { return found; }
  }
  return undefined;
}
export function remains(p: Page, r: Rule): boolean {
  return p.readable && !p.protectedPage && p.nodes.some((n: SeenNode) => target(n,r));
}
export function confirmed(p: Page, r: Rule): boolean {
  if (!p.readable || p.protectedPage || p.nodes.some((n: SeenNode) => target(n,r))) { return false; }
  if (r.result.length > 0) { return r.result.every((f: Feature) => present(p,f)); }
  return r.must.some((f: Feature) => !present(p,f));
}
export function capture(p: Page, app: AppProfile): Proposal {
  const v = new Proposal(); v.bundle = app.bundle;
  if (p.protectedPage) { v.message = '登录、支付或协议保护已生效'; return v; }
  const marker = p.nodes.find((n: SeenNode) => explicitAd([n.text]));
  if (!marker) { v.message = '未出现明确广告标记'; return v; }
  const buttons = p.nodes.filter((n: SeenNode) => n.enabled && closeLabel(n.text));
  if (buttons.length !== 1) { v.message = buttons.length ? '广告按钮不唯一' : '未找到可用的关闭按钮'; return v; }
  const n = buttons[0];
  if (!n.id && !skipLabel(n.text)) { v.message = '普通关闭按钮缺少稳定定位依据'; return v; }
  const r = new AdRule(); r.id = n.id; r.text = n.text; r.anchor = marker.text;
  v.candidates = [r]; v.message = '请确认这是要关闭的广告按钮'; return v;
}
