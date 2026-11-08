import { readState, writeState } from '../ProbeState';
import { LearnRequest, Proposal } from '../RuleModel';
export class Health {
  build: string = '0.3.9';
  run: string = '';
  phase: string = '待激活';
  beat: number = 0;
  successfulChecks: number = 0;
  faults: number = 0;
  maxGapMs: number = 0;
  detail: string = '';
}
export class Event {
  at: number = 0; run: string = ''; bundle: string = ''; key: string = ''; result: string = ''; code: string = '';
}
export function events(dir: string): Event[] {
  const clear = Number(readState(dir,'cleared'));
  const list: Event[] = JSON.parse(readState(dir,'events') || '[]') as Event[];
  return list.filter((e: Event) => e.at > clear);
}
const LOG_SWEEP_MS = 60 * 60 * 1000;
export function normalEvent(e: Event): boolean {
  return !e.code && (e.result === '已尝试' || e.result === '确认关闭' || e.result === '页面已消失');
}
export function sweepLogs(dir: string): void {
  const now = Date.now();
  const saved = Number(readState(dir,'logs.sweptAt'));
  const stored: Event[] = JSON.parse(readState(dir,'events') || '[]') as Event[];
  const clear = Number(readState(dir,'cleared'));
  const list = stored.filter((e: Event) => e.at > clear);
  const first = list.find((e: Event) => normalEvent(e));
  const last = saved > 0 && Number.isFinite(saved) ? saved : (first ? first.at : now);
  if (now - last >= LOG_SWEEP_MS) {
    writeState(dir,'events',JSON.stringify(list.filter((e: Event) => !normalEvent(e))));
    writeState(dir,'logs.sweptAt',now.toString());
  } else {
    if (list.length !== stored.length) { writeState(dir,'events',JSON.stringify(list)); }
    if (!(saved > 0 && Number.isFinite(saved)) || now < last) {
      writeState(dir,'logs.sweptAt',now.toString());
    }
  }
}
export function logEvent(dir: string, run: string, bundle: string, key: string, result: string, code: string): void {
  sweepLogs(dir);
  const e = new Event(); e.at = Date.now(); e.run = run; e.bundle = bundle; e.key = key; e.result = result; e.code = code;
  const list = events(dir); list.push(e);
  const recentNormal = new Set<Event>(list.filter((item: Event) => normalEvent(item)).slice(-80));
  const kept = list.filter((item: Event) => !normalEvent(item) || recentNormal.has(item));
  writeState(dir,'events',JSON.stringify(kept));
}
export function getRequest(dir: string): LearnRequest {
  return JSON.parse(readState(dir,'learn') || '{}') as LearnRequest;
}
export function beginLearn(dir: string, bundle: string): LearnRequest {
  const v = new LearnRequest(); v.at = Date.now(); v.bundle = bundle; v.run = readState(dir,'active');
  const h = getHealth(dir);
  if (h.build !== new Health().build || h.run !== v.run || !Number.isFinite(h.beat) || h.beat <= 0 ||
    Date.now() - h.beat < 0 || Date.now() - h.beat > 15000 || !['学习中','运行中'].includes(h.phase)) {
    throw new Error('请先激活广告跳过，再开始学习');
  }
  writeState(dir,'proposal',''); writeState(dir,'learn',JSON.stringify(v)); return v;
}
export function clearLearn(dir: string): void { writeState(dir,'learn',''); writeState(dir,'proposal',''); }
export function getHealth(dir: string): Health {
  return JSON.parse(readState(dir,'health') || '{}') as Health;
}
export function pending(dir: string): Proposal {
  const p: Proposal = JSON.parse(readState(dir,'proposal') || '{}') as Proposal;
  const req = getRequest(dir);
  return p.run && p.run === readState(dir,'active') && p.at === req.at && req.bundle === p.bundle ? p : new Proposal();
}
export function statusText(dir: string): string {
  const run = readState(dir,'active');
  if (run === 'stopped') { return '已停止'; }
  if (!/^[0-9]{13}$/.test(run)) { return '待激活'; }
  if (readState(dir,'mode') !== 'monitor') {
    const result = readState(dir,run);
    if (Date.now() - Number(run) > 105000 && (!result || /进行中|验证中/.test(result))) { return '需要重新激活 · 验证已到期'; }
    return result || '等待测试服务启动';
  }
  const h = getHealth(dir);
  if (h.build !== new Health().build) { return '更新后需要重新激活 · 请点启动广告跳过'; }
  if (h.run === run && h.phase === '需要重新激活') { return h.phase + (h.detail ? ' · ' + h.detail : ''); }
  if (h.run !== run || Date.now() - (h.beat || Number(run)) > 15000) {
    return Date.now() - Number(run) < 15000 ? '正在启动' : '需要重新激活 · 点击服务无响应';
  }
  return h.phase + (h.detail ? ' · ' + h.detail : '');
}
