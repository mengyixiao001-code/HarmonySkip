export class Feature {
  field: string = 'text';
  mode: string = 'exact';
  value: string = '';
  constructor(field: string = 'text', value: string = '', mode: string = 'exact') {
    this.field = field; this.value = value; this.mode = mode;
  }
}

// 0.2.1 on-disk format and learning preview.
export class AdRule {
  id: string = '';
  text: string = '';
  anchor: string = '广告';
}

export class Rule {
  action: string = 'component';
  key: string = '';
  version: number = 1;
  scene: string = '广告';
  must: Feature[] = [];
  absent: Feature[] = [];
  target: Feature[] = [];
  maxAttempts: number = 1;
  cooldownMs: number = 1500;
  result: Feature[] = [];
}

export class AppProfile {
  label: string;
  bundle: string;
  bank: boolean;
  enabled: boolean;
  versions: string[] = [];
  rules: Rule[] = [];
  constructor(label: string, bundle: string, bank: boolean = false) {
    this.label = label; this.bundle = bundle; this.bank = bank; this.enabled = !bank;
  }
}
export class RuleConfig {
  schema: number = 1;
  apps: AppProfile[] = [];
}
export class Catalog extends RuleConfig {
  revision: number = 1;
  generic: Rule = new Rule();
}
export class LearnRequest {
  run: string = '';
  bundle: string = '';
  at: number = 0;
}
export class Proposal {
  run: string = '';
  at: number = 0;
  bundle: string = '';
  message: string = '';
  candidates: AdRule[] = [];
}

export function skipLabel(text: string): boolean {
  return /^(跳过(广告)?(\s*\d{1,2}\s*[sS秒]?)?|\d{1,2}\s*[sS秒]?\s*跳过|skip)$/i.test(text.trim());
}
export function closeLabel(text: string): boolean {
  return skipLabel(text) || /^(关闭广告|关闭|[×✕xX])$/.test(text.trim());
}
export const PROTECTED = '登录|登陆|验证码|支付密码|交易密码|确认转账|确认付款|人脸识别|风险测评|签署协议|隐私政策|用户协议|密码登录';
export function blockedPage(texts: string[]): boolean {
  return texts.some((s: string) => new RegExp(PROTECTED).test(s));
}
export function explicitAd(texts: string[]): boolean {
  return texts.some((s: string) => /^(广告|推广广告|广告推广|广告\s*\d{1,2}\s*[sS秒]?)$/.test(s.trim()));
}
export function learnedRule(old: AdRule, key: string): Rule {
  const r = new Rule();
  r.key = key;
  r.must = [new Feature('text', old.anchor)];
  r.target = [new Feature('text', old.id ? old.text : '', old.id ? 'exact' : 'skip')];
  if (old.id) { r.target.push(new Feature('id', old.id)); }
  return r;
}
