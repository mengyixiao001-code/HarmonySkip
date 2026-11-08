import { fileIo } from '@kit.CoreFileKit';
import { readState, writeState } from '../ProbeState';
import { Component, Driver, ON, MatchPattern, UiWindow, abilityDelegatorRegistry, Point } from '@kit.TestKit';
import { AppProfile, PROTECTED, Feature, Rule } from '../RuleModel';

export class SerialQueue {
  private tail: Promise<void> = Promise.resolve();
  run<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.tail.then(operation);
    this.tail = next.then((): void => {}).catch((): void => {});
    return next;
  }
}
// One queue per test runner. Each queued transaction owns the driver until it resolves.
export const uiService = new SerialQueue();
export class SeenNode {
  handle?: Component;
  point?: Point;
  text: string = ''; id: string = ''; desc: string = ''; type: string = '';
  enabled: boolean = false;
  constructor(handle?: Component) { this.handle = handle; }
}
export class Page {
  nodes: SeenNode[] = [];
  readable: boolean = false;
  protectedPage: boolean = false;
}
export async function front(driver: Driver): Promise<string> {
  const w = await driver.findWindow({ focused: true });
  return w && await w.isFocused() ? await w.getBundleName() : '';
}
export async function sameWindow(driver: Driver, bundle: string): Promise<UiWindow | undefined> {
  const w = await driver.findWindow({ focused: true, bundleName: bundle });
  return w && await w.isFocused() && await w.getBundleName() === bundle ? w : undefined;
}
export async function readPage(driver: Driver, app: AppProfile, verifyReadable: boolean = false, builtin: Rule[] = []): Promise<Page> {
  const p = new Page();
  const scope = ON.inWindow(app.bundle);
  // Custom fields may select controls with no visible text. The built-in and learned
  // skip paths keep the fast text filter that was verified on short splash screens.
  let full = false;
  const rules = app.rules.concat(builtin);
  const anchorIds = rules.some((r: Rule) => r.must.some((f: Feature) => f.field === 'id'));
  for (const r of rules) {
    for (const f of r.must.concat(r.absent,r.target,r.result)) {
      if (f.field === 'id' && r.must.includes(f) && r.must.some((t: Feature) =>
        t.field === 'text' && t.mode === 'exact' && /广告|跳过|关闭/.test(t.value))) { continue; }
      if (f.field === 'id' && r.target.includes(f) && r.target.some((t: Feature) =>
        t.field === 'text' && t.mode === 'exact' && /广告|跳过|关闭|^[×✕xX]$|^skip$/i.test(t.value))) { continue; }
      if (f.field !== 'text' || (f.mode === 'exact' && !/广告|跳过|关闭|^[×✕xX]$|^skip$/i.test(f.value)) ||
        f.mode === 'regex') { full = true; }
    }
  }
  const found = await driver.findComponents(full ? scope : scope.text(
    '.*(广告|跳过|关闭|' + PROTECTED + ').*|[×✕xX]|[sS][kK][iI][pP]',MatchPattern.REG_EXP));
  const items = found || [];
  if (items.length > (full ? 180 : 100)) { return p; }
  const described = await driver.findComponents(ON.inWindow(app.bundle).description('.*(' + PROTECTED + ').*',MatchPattern.REG_EXP));
  if (described && described.length) { p.protectedPage = true; return p; }
  p.readable = false;
  if (!items.length && verifyReadable && !full) {
    const any = await driver.findComponents(ON.inWindow(app.bundle));
    if (any && any.length <= 500) {
      // A scoped, readable, labelled control is positive evidence that the replacement page loaded.
      for (const n of any.slice(0,24)) {
        if ((await n.getText()).trim() || (await n.getDescription()).trim()) { p.readable = true; break; }
      }
    }
  }
  for (const item of items) {
    const n = new SeenNode(item);
    n.text = await item.getText();
    if (new RegExp(PROTECTED).test(n.text)) { p.protectedPage = true; return p; }
    const actionLabel = /跳过|关闭|^[×✕xX]$|^skip$/i.test(n.text);
    const anchorLabel = anchorIds && rules.some((r: Rule) => r.must.some((f: Feature) =>
      f.field === 'text' && f.mode === 'exact' && f.value === n.text));
    if (full || actionLabel || anchorLabel) { n.id = await item.getId(); }
    if (full) { n.desc = await item.getDescription(); n.type = await item.getType(); }
    if (full || actionLabel) { n.enabled = await item.isEnabled() && await item.isClickable(); }
    if (n.text.trim() || n.id || n.desc.trim()) { p.readable = true; }
    p.nodes.push(n);
  }
  return p;
}

class SnapshotAttributes {
  bundleName: string = ''; focused: string = ''; visible: string = '';
  text: string = ''; description: string = ''; id: string = ''; type: string = '';
  enabled: string = ''; clickable: string = ''; bounds: string = '';
}
class SnapshotTree {
  attributes: SnapshotAttributes = new SnapshotAttributes();
  children: SnapshotTree[] = [];
}
export function parseSnapshot(raw: string, bundle: string): Page {
  // An incomplete/oversized observation is not a lost UiTest connection.
  // Discard every node, including any candidate found before the failure.
  try { return parseSnapshotTree(raw,bundle); } catch (_) { return new Page(); }
}
function parseSnapshotTree(raw: string, bundle: string): Page {
  const page = new Page();
  const tree = JSON.parse(raw) as SnapshotTree;
  let count = 0;
  const visit = (node: SnapshotTree, owner: string, focused: boolean, enabled: boolean, depth: number): void => {
    if (++count > 2000 || depth > 128) { throw new Error('页面过大'); }
    const a = node.attributes;
    if (a.visible === 'false') { return; }
    const usable = enabled && a.enabled !== 'false';
    const current = a.bundleName || owner;
    const active = a.bundleName ? a.focused === 'true' : focused;
    if (current === bundle && active && a.visible === 'true') {
      const n = new SeenNode();
      n.text = a.text || ''; n.desc = a.description || ''; n.id = a.id || ''; n.type = a.type || '';
      n.enabled = usable && a.enabled === 'true' && a.clickable === 'true';
      if (new RegExp(PROTECTED).test(n.text + ' ' + n.desc)) { page.protectedPage = true; }
      const rect = /^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/.exec(a.bounds || '');
      if (rect && Number(rect[3]) > Number(rect[1]) && Number(rect[4]) > Number(rect[2])) {
        n.point = {x:Math.floor((Number(rect[1])+Number(rect[3]))/2),y:Math.floor((Number(rect[2])+Number(rect[4]))/2)};
      }
      if (n.text || n.desc || n.id) { page.readable = true; }
      page.nodes.push(n);
    }
    for (const child of node.children || []) { visit(child,current,active,usable,depth + 1); }
  };
  visit(tree,'',false,true,0);
  return page;
}
export async function readSnapshot(driver: Driver, bundle: string): Promise<Page> {
  const dir = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext().filesDir;
  const key = 'ui-snapshot.tmp';
  writeState(dir,key,'');
  try {
    if (!await driver.dumpLayout(dir + '/' + key)) { return new Page(); }
    return parseSnapshot(readState(dir,key),bundle);
  } finally { fileIo.unlinkSync(dir + '/' + key); }
}
