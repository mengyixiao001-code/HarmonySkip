import { Rule, Feature, AppProfile, RuleConfig, Catalog, AdRule, skipLabel, learnedRule, explicitAd } from '../RuleModel';
import { readConfigFile, writeState } from '../ProbeState';

const LIMIT = 6 * 1024 * 1024;
function check(ok: boolean, reason: string): void {
  if (!ok) { throw new Error(reason); }
}
function short(s: string, limit: number): boolean {
  return typeof s === 'string' && s.length > 0 && s.length <= limit;
}
function integer(n: number, min: number, max: number): boolean {
  return Number.isInteger(n) && n >= min && n <= max;
}
function parsePack(raw: string): RuleConfig {
  check(short(raw, LIMIT), '配置为空或过大');
  return JSON.parse(raw) as RuleConfig;
}
function validateFeatures(list: Feature[], required: boolean): void {
  check(Array.isArray(list) && list.length <= 12 && (!required || list.length > 0), '选择器数量无效');
  for (const f of list) {
    check(['id','text','desc','type'].includes(f.field), '未知控件属性');
    if (f.mode === 'exact') { check(short(f.value, 160), '精确值无效'); }
    else if (f.mode === 'regex') {
      // Anchored alternatives of literals and bounded digit slots only.
      check(short(f.value, 96) && /^\^([^\\^$.*+?()\[\]{}|]|\\d\{1,[1-3]\})+(\|([^\\^$.*+?()\[\]{}|]|\\d\{1,[1-3]\})+)*\$$/.test(f.value), '受限正则无效');
    } else {
      check((f.mode === 'skip' || f.mode === 'ad') && f.field === 'text' && f.value === '', '未知匹配方式');
    }
  }
}
export function validateRule(rule: Rule): void {
  check(rule.action === undefined || rule.action === 'component' || rule.action === 'center' || rule.action === 'nativeCenter', '未知点击方式');
  check(short(rule.key, 80) && /^[a-zA-Z0-9._-]+$/.test(rule.key) && integer(rule.version, 1, 1000000) &&
    short(rule.scene, 60), '规则编号、版本或场景无效');
  validateFeatures(rule.must, true); validateFeatures(rule.absent, false);
  validateFeatures(rule.target, true); validateFeatures(rule.result, false);
  check(integer(rule.maxAttempts,1,5) && integer(rule.cooldownMs,250,3600000), '次数或冷却无效');
  const stableId = rule.target.some((f: Feature) => f.field === 'id' && f.mode === 'exact');
  const skip = rule.target.some((f: Feature) => (f.field === 'text' || f.field === 'desc') &&
    (f.mode === 'skip' || (f.mode === 'exact' && skipLabel(f.value))));
  const marker = rule.must.some((f: Feature) => (f.field === 'text' || f.field === 'desc') &&
    (f.mode === 'ad' || (f.mode === 'exact' && (explicitAd([f.value]) || f.value === '互动广告｜已 WIFI 预加载'))));
  check(stableId || (marker && skip), '无 ID 的规则需要广告标记和明确的跳过按钮');
}
export function validatePack(pack: RuleConfig): void {
  check(pack.schema === 1 && Array.isArray(pack.apps) && pack.apps.length <= 400, '规则包版本或应用数量无效');
  const bundles = new Set<string>();
  for (const a of pack.apps) {
    check(short(a.bundle, 160) && /^[A-Za-z][A-Za-z0-9_.]*$/.test(a.bundle) &&
      !bundles.has(a.bundle) && short(a.label, 60), '应用包名重复或名称无效');
    bundles.add(a.bundle);
    check(typeof a.bank === 'boolean' && typeof a.enabled === 'boolean' && Array.isArray(a.versions) &&
      a.versions.length <= 40 && a.versions.every((v: string) => short(v, 64)), '应用设置无效');
    check(Array.isArray(a.rules) && a.rules.length <= 100, '规则数量无效');
    const keys = new Set<string>();
    for (const r of a.rules) {
      validateRule(r); check(!keys.has(r.key), '同一应用内规则编号重复'); keys.add(r.key);
    }
  }
}
export function mergeCatalog(pack: RuleConfig, catalog: Catalog): RuleConfig {
  validatePack(pack);
  const out = new RuleConfig();
  const map = new Map<string,AppProfile>();
  for (const a of pack.apps) { map.set(a.bundle, a); }
  for (const base of catalog.apps) {
    const a = map.get(base.bundle);
    if (!a) {
      const next = JSON.parse(JSON.stringify(base)) as AppProfile;
      next.rules = []; if (next.bank) { next.enabled = false; }
      out.apps.push(next); continue;
    }
    a.bank = a.bank || base.bank;
    if (a.bank && !a.rules.length) { a.enabled = false; }
    out.apps.push(a); map.delete(a.bundle);
  }
  map.forEach((a: AppProfile) => { if (a.bank && !a.rules.length) { a.enabled = false; } out.apps.push(a); });
  return out;
}
class LegacyApp {
  label: string = ''; bundle: string = ''; bank: boolean = false; enabled: boolean = false; rules: AdRule[] = [];
}
class Legacy { apps: LegacyApp[] = []; }
export function migrate(raw: string, catalog: Catalog): RuleConfig {
  const pack = new RuleConfig();
  if (raw) {
    check(raw.length <= LIMIT, '旧配置过大');
    const old = JSON.parse(raw) as Legacy;
    check(Array.isArray(old.apps), '旧名单损坏');
    for (const item of old.apps) {
      const a = new AppProfile(item.label,item.bundle,item.bank);
      a.enabled = item.enabled;
      check(Array.isArray(item.rules), '旧规则损坏');
      for (const oldRule of item.rules) {
        check(typeof oldRule.id === 'string' && short(oldRule.text,160) && short(oldRule.anchor,160) &&
          (oldRule.id.length > 0 || skipLabel(oldRule.text)), '旧规则缺少依据');
        a.rules.push(learnedRule(oldRule,'legacy.' + (a.rules.length + 1)));
      }
      pack.apps.push(a);
    }
  }
  return mergeCatalog(pack,catalog);
}
class PersonalGroup { bundle: string = ''; rules: Rule[] = []; }
class PersonalFile { schema: number = 1; groups: PersonalGroup[] = []; }
class Head {
  schema: number = 1; revision: number = 0; slot: number = 0; backup: number = -1;
}
function head(raw: string): Head {
  const h = JSON.parse(raw) as Head;
  check(h.schema === 1 && integer(h.slot,0,2) && integer(h.backup,-1,2) && h.slot !== h.backup &&
    integer(h.revision,1,Number.MAX_SAFE_INTEGER),'配置指针损坏');
  return h;
}
export class RuleRepository {
  dir: string; catalog: Catalog; pack: RuleConfig = new RuleConfig();
  index: Map<string, AppProfile> = new Map();
  builtins: Map<string, Rule[]> = new Map();
  stamp: string = ''; warning: string = '';
  private slot: number = -1;
  constructor(dir: string, catalog: Catalog) {
    validatePack(catalog); validateRule(catalog.generic);
    this.dir = dir; this.catalog = catalog;
    for (const app of catalog.apps) { this.builtins.set(app.bundle,app.bank ? [] : app.rules); }
  }
  private read(key: string): string { return readConfigFile(this.dir,key); }
  private pair(slot: number): RuleConfig {
    const settings = parsePack(this.read('settings.' + slot));
    validatePack(settings);
    const raw = this.read('personal.' + slot);
    check(short(raw,LIMIT), '个人规则文件损坏');
    const personal = JSON.parse(raw) as PersonalFile;
    check(personal.schema === 1 && Array.isArray(personal.groups) &&
      personal.groups.length === settings.apps.length, '规则分卷不一致');
    for (let i = 0; i < settings.apps.length; i++) {
      const g = personal.groups[i];
      check(settings.apps[i].bundle === g.bundle && settings.apps[i].rules.length === 0, '应用与规则分卷不一致');
      settings.apps[i].rules = g.rules;
    }
    validatePack(settings);
    return settings;
  }
  private publish(pack: RuleConfig, stamp: string, slot: number): void {
    this.pack = mergeCatalog(pack,this.catalog);
    this.index.clear();
    for (const a of this.pack.apps) { this.index.set(a.bundle,a); }
    this.stamp = stamp; this.slot = slot;
  }
  refresh(initialize: boolean = false): void {
    const raw = this.read('store.head');
    if (!raw) {
      if (this.read('store.previous')) {
        const h = head(this.read('store.previous'));
        this.publish(this.pair(h.slot),'',h.slot); this.warning = '配置指针丢失，使用上一份备份'; return;
      }
      if (!initialize || this.stamp) {
        throw new Error('规则仓库未初始化或指针丢失');
      }
      const legacy = this.read('rules');
      if (legacy) { writeState(this.dir,'rules.pre030',legacy); }
      this.commit(migrate(legacy,this.catalog)); return;
    }
    if (raw === this.stamp) { return; }
    this.warning = '';
    try {
      const h = head(raw);
      try { this.publish(this.pair(h.slot),raw,h.slot); }
      catch (e) {
        if (h.backup < 0) { throw e as Error; }
        this.publish(this.pair(h.backup),raw,h.backup);
        this.warning = '当前配置损坏，正在使用上一份已校验备份。';
      }
    } catch (_) {
      const prev = head(this.read('store.previous'));
      this.publish(this.pair(prev.slot),raw,prev.slot);
      this.warning = '当前配置损坏，正在使用上一份已校验备份。';
    }
  }
  preview(raw: string): RuleConfig { return mergeCatalog(parsePack(raw), this.catalog); }
  commit(pack: RuleConfig): void {
    const raw = this.read('store.head');
    check(raw === this.stamp,'配置已变化，请刷新后重试');
    validatePack(pack);
    const copy = parsePack(JSON.stringify(pack));
    const groups = new PersonalFile();
    for (const a of copy.apps) {
      const g = new PersonalGroup(); g.bundle = a.bundle; g.rules = a.rules; groups.groups.push(g); a.rules = [];
    }
    let backup = -1;
    if (!this.warning && raw) { backup = head(raw).backup; }
    // During recovery, this.slot is the verified pair; damaged pointers are not trusted.
    const next = [0,1,2].find((i: number) => i !== this.slot && i !== backup);
    check(next !== undefined,'没有可用配置分卷');
    const slot = next as number;
    writeState(this.dir,'settings.' + slot,JSON.stringify(copy));
    writeState(this.dir,'personal.' + slot,JSON.stringify(groups));
    const verified = this.pair(slot);
    check(JSON.stringify(verified) === JSON.stringify(pack),'写入后校验失败');
    const h = new Head(); h.slot = slot; h.backup = this.slot; h.revision = Date.now();
    if (this.slot >= 0) {
      const previous = new Head();
      previous.slot = this.slot; previous.revision = h.revision;
      writeState(this.dir,'store.previous',this.warning ? JSON.stringify(previous) : raw);
    }
    if (this.slot < 0) {
      // Establish a recoverable pair on the very first migration, too.
      const seed = new Head(); seed.slot = 1; seed.revision = h.revision;
      writeState(this.dir,'settings.1',JSON.stringify(copy));
      writeState(this.dir,'personal.1',JSON.stringify(groups));
      this.pair(1); writeState(this.dir,'store.previous',JSON.stringify(seed)); h.backup = 1;
    }
    const stamp = JSON.stringify(h);
    writeState(this.dir,'store.head',stamp);
    this.publish(verified,stamp,slot); this.warning = '';
  }
}
