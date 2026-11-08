import { abilityDelegatorRegistry, Driver } from '@kit.TestKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppProfile, LearnRequest, Proposal } from '../RuleModel';
import { readState, readConfigFile, writeState } from '../ProbeState';
import { RuleRepository } from '../rules/RuleRepository';
import { readCatalog } from '../rules/Catalog';
import { capture } from '../rules/Recognition';
import { front, readPage, sameWindow, uiService } from '../platform/UiService';
import { ActionExecutor } from '../session/ActionExecutor';
import { VersionGate } from '../platform/VersionGate';
import { Health, getRequest, logEvent, sweepLogs } from '../session/SessionState';

function pause(ms: number): Promise<void> { return new Promise<void>((done) => { setTimeout(done,ms); }); }
export default class MonitorSession {
  private health: Health = new Health();
  private action: ActionExecutor = new ActionExecutor();
  private bundle: string = '';
  private versions: VersionGate = new VersionGate();
  private learnAt: number = 0;
  private caught: boolean = false;
  private expired: boolean = false;
  private reason: string = '';
  private reasonRank: number = 0;
  private lastWrite: number = 0;
  private logCheckAt: number = 0;

  async onRun(): Promise<void> {
    const d = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments().parameters;
    const run = args['-s hsRun'] || args['hsRun'];
    const ctx = d.getAppContext().getApplicationContext();
    const dir = ctx.filesDir;
    if (!/^[0-9]{13}$/.test(run) || readState(dir,'active') !== run) { await d.finishTest('会话已失效',1); return; }
    this.health.run = run;
    let errors = 0;
    try {
      const repo = new RuleRepository(dir,readCatalog(ctx));
      await this.versions.start(dir,run);
      const driver = Driver.create();
      while (readState(dir,'active') === run) {
        try {
          if (Date.now() >= this.logCheckAt) {
            sweepLogs(dir); this.logCheckAt = Date.now() + 60000;
          }
          repo.refresh();
          const learning = await uiService.run(() => this.step(driver,repo,dir,run));
          if (readState(dir,'active') !== run) { break; }
          errors = 0;
          const now = Date.now();
          if (this.health.beat) { this.health.maxGapMs = Math.max(this.health.maxGapMs,now - this.health.beat); }
          this.health.beat = now; this.health.successfulChecks++;
          this.report(dir,learning ? '学习中' : '运行中',repo.warning,false);
          await pause(230);
        } catch (e) {
          if (readState(dir,'active') !== run) { break; }
          if ((e as BusinessError).code === 17000004) {
            // The service answered, but the observed UI no longer exists.
            // Discard this observation and obtain fresh handles next time.
            errors = 0;
            await pause(230);
            continue;
          }
          errors++; this.health.faults++;
          const code = String((e as BusinessError).code || 'SERVICE');
          logEvent(dir,run,this.bundle,'','连接异常',code);
          this.report(dir,'连接异常',code + ' · ' + String((e as Error).message).slice(0,160) + ' · 重试 ' + errors + '/5',true);
          if (errors >= 5) { throw e as Error; }
          await pause(1000);
        }
      }
      this.versions.close(); await d.finishTest('已停止',0);
    } catch (e) {
      if (readState(dir,'active') === run) {
        this.report(dir,'需要重新激活','服务中断 ' + String((e as Error).message).slice(0,120),true);
        const req = getRequest(dir);
        if (req.run === run) { const p = new Proposal(); p.message = '服务中断，请重新激活后再学习'; this.propose(dir,req,p); }
      }
      this.versions.close(); await d.finishTest('服务中断',1);
    }
  }
  private report(dir: string, phase: string, detail: string, force: boolean): void {
    const prev = this.health.phase; this.health.phase = phase;
    if (force || detail || prev === '连接异常') { this.health.detail = detail; }
    if (force || phase !== prev || Date.now() - this.lastWrite >= 3000) {
      writeState(dir,'health',JSON.stringify(this.health)); this.lastWrite = Date.now();
    }
  }
  private propose(dir: string, req: LearnRequest, p: Proposal): void {
    if (readState(dir,'active') !== req.run || getRequest(dir).at !== req.at) { return; }
    p.run = req.run; p.at = req.at; p.bundle = req.bundle; writeState(dir,'proposal',JSON.stringify(p));
  }
  private async step(driver: Driver, repo: RuleRepository, dir: string, run: string): Promise<boolean> {
    const bundle = await front(driver);
    if (this.bundle !== bundle) { this.bundle = bundle; }
    this.action.enter(bundle);
    const app = repo.index.get(bundle);
    const req = getRequest(dir);
    const requested = req.run === run && req.at > 0;
    if (req.at !== this.learnAt) {
      this.learnAt = req.at; this.caught = false; this.expired = false;
      this.reason = '未进入目标 App'; this.reasonRank = 0;
    }
    if (requested && !this.caught && !this.expired && Date.now() - req.at >= 45000) {
      const p = new Proposal(); p.message = '学习结束 · ' + this.reason;
      this.propose(dir,req,p); this.expired = true;
    }
    const learning = requested && !this.expired;
    if (!app) { return learning; }
    if (learning && req.bundle === bundle) {
      if (!this.caught) {
        if (app.versions.length && !this.applies(app)) { this.reason = '当前应用版本不适用'; return true; }
        const p = capture(await readPage(driver,app),app);
        if (await sameWindow(driver,bundle) && Date.now() - req.at < 45000) {
          const rank = /不唯一|定位依据|保护/.test(p.message) ? 3 : /可用/.test(p.message) ? 2 : 1;
          if (rank >= this.reasonRank) { this.reason = p.message; this.reasonRank = rank; }
          if (p.candidates.length) { this.propose(dir,req,p); this.caught = true; }
        }
      }
      return true;
    }
    if (!app.enabled || !this.applies(app)) { return learning; }
    const valid = (): boolean => {
      if (!this.applies(app) || readState(dir,'active') !== run || readConfigFile(dir,'store.head') !== repo.stamp) { return false; }
      const current = getRequest(dir);
      return current.run !== run || current.bundle !== bundle || (this.expired && current.at === this.learnAt);
    };
    await this.action.inspect(driver,app,repo.catalog.generic,valid,(key: string,result: string,code: string) => {
      logEvent(dir,run,bundle,key,result,code); this.health.detail = app.label + ' · ' + result;
    },repo.builtins.get(bundle) || []);
    return learning;
  }
  private applies(app: AppProfile): boolean {
    const ok = this.versions.allows(app);
    if (!ok) { this.health.detail = app.label + ' · 应用版本不匹配或需重新激活以核验版本'; }
    return ok;
  }
}
