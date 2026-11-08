import { common } from '@kit.AbilityKit';
import { readState, writeState } from '../ProbeState';
import { AppProfile, RuleConfig, Rule, AdRule, Proposal, learnedRule } from '../RuleModel';
import { RuleRepository } from '../rules/RuleRepository';
import { readCatalog } from '../rules/Catalog';
import { selectPack, exportPack } from '../rules/PackFiles';
import { activate } from '../platform/LocalHdc';
import { beginLearn, clearLearn, events, Event, pending, statusText, getRequest } from '../session/SessionState';

@Entry
@Component
struct Index {
  @State port: string = '';
  @State status: string = '待激活';
  @State working: boolean = false;
  @State config: RuleConfig = new RuleConfig();
  @State proposal: Proposal = new Proposal();
  @State notice: string = '';
  @State learning: string = '';
  @State preview: RuleConfig | undefined = undefined;
  @State diagnostic: string = '';
  @State expanded: string = '';
  private repo?: RuleRepository;
  private timer: number = -1;
  private activationFailure: string = '';

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private dir(): string { return this.ctx().getApplicationContext().filesDir; }
  aboutToAppear(): void {
    this.port = readState(this.dir(),'port');
    try {
      const repo = new RuleRepository(this.dir(),readCatalog(this.ctx()));
      repo.refresh(true); this.repo = repo; this.config = repo.pack; this.notice = repo.warning;
    } catch (e) { this.notice = '无法加载配置 · ' + (e as Error).message; }
    this.refresh(); this.timer = setInterval(() => this.refresh(),2000);
  }
  aboutToDisappear(): void { clearInterval(this.timer); }
  onPageShow(): void { this.refresh(); }
  private refresh(): void {
    if (this.working) { return; }
    try {
      this.status = this.activationFailure ? '启动失败 · ' + this.activationFailure : statusText(this.dir());
      this.proposal = pending(this.dir());
      const req = getRequest(this.dir());
      this.learning = req.run === readState(this.dir(),'active') ? req.bundle : '';
      this.diagnostic = events(this.dir()).slice(-12).reverse().map((e: Event) =>
        new Date(e.at).toLocaleTimeString() + (e.run === readState(this.dir(),'active') ? '  本次  ' : '  历史  ') + e.bundle + '  ' + e.key + '  ' + e.result + ' ' + e.code).join('\n');
    } catch (e) { this.notice = (e as Error).message; }
  }
  private async start(monitor: boolean): Promise<void> {
    if (this.working || !this.repo) { return; }
    this.working = true; this.status = '正在连接'; this.notice = ''; this.activationFailure = '';
    try { await activate(this.ctx(),this.port,monitor,this.config.apps,(s: string) => { this.status = s; }); }
    catch (e) { this.activationFailure = (e as Error).message; this.notice = this.activationFailure; }
    finally { this.working = false; this.refresh(); }
  }
  private edit(bundle: string, update: (a: AppProfile) => void): boolean {
    if (!this.repo) { return false; }
    try {
      const pack: RuleConfig = JSON.parse(JSON.stringify(this.config)) as RuleConfig;
      const app = pack.apps.find((a: AppProfile) => a.bundle === bundle);
      if (!app) { return false; }
      update(app); this.repo.commit(pack); this.config = this.repo.pack; return true;
    } catch (e) { this.notice = (e as Error).message; return false; }
  }
  private learn(bundle: string): void {
    try { beginLearn(this.dir(),bundle); this.notice = '请立即切换到目标应用，45 秒内捕捉广告后回来确认。'; this.refresh(); }
    catch (e) { this.notice = (e as Error).message; }
  }
  private approve(old: AdRule): void {
    const p = pending(this.dir());
    if (!p.at || p.at !== this.proposal.at || !p.candidates.some((r: AdRule) =>
      r.id === old.id && r.text === old.text && r.anchor === old.anchor)) { this.refresh(); return; }
    if (this.edit(p.bundle,(a: AppProfile) => {
      const r = learnedRule(old,'learn.' + p.at);
      if (!a.rules.some((v: Rule) => JSON.stringify(v.must) === JSON.stringify(r.must) &&
        JSON.stringify(v.target) === JSON.stringify(r.target))) { a.rules.push(r); }
      a.enabled = true;
    })) { clearLearn(this.dir()); this.notice = '已确认并保存'; this.refresh(); }
  }
  private async pick(): Promise<void> {
    if (!this.repo) { return; }
    this.preview = undefined;
    try { const raw = await selectPack(this.ctx()); if (raw) { this.preview = this.repo.preview(raw); } }
    catch (e) { this.notice = '导入失败 · ' + (e as Error).message; }
  }
  private applyImport(): void {
    if (!this.preview || !this.repo) { return; }
    try {
      this.repo.commit(this.preview); this.config = this.repo.pack; this.preview = undefined; clearLearn(this.dir()); this.notice = '已导入';
    } catch (e) { this.notice = (e as Error).message; }
    this.refresh();
  }
  private async share(): Promise<void> {
    try { if (await exportPack(this.ctx(),JSON.stringify(this.config))) { this.notice = '已导出规则包'; } }
    catch (e) { this.notice = (e as Error).message; }
  }
  build() {
    Scroll() {
      Column({space: 12}) {
        Text('轻跳 0.3.9').fontSize(26).fontWeight(FontWeight.Bold)
        Text(this.status).fontSize(18).fontColor('#195D50')
        TextInput({placeholder:'本机无线调试端口',text:this.port}).type(InputType.Number).maxLength(5)
          .onChange((v: string) => { this.port = v; })
        Row({space: 10}) {
          Button('启动广告跳过').enabled(!this.working && !!this.repo).onClick(() => { this.start(true); })
          Button('停止').enabled(!this.working).onClick(() => {
            writeState(this.dir(),'active','stopped'); clearLearn(this.dir()); this.refresh();
          })
        }
        Text('页面已消失不代表已验证提前跳过；按钮仍在表示未关闭。').fontSize(12)
        Text(this.notice).fontColor('#855419')
        if (this.learning) {
          Text('学习目标  ' + this.learning)
          if (this.proposal.message) { Text(this.proposal.message) }
          ForEach(this.proposal.candidates,(r: AdRule) => {
            Text('广告标记“' + r.anchor + '” · 按钮“' + r.text + '” · ' + (r.id || '无 ID，要求唯一跳过'))
            Button('确认并保存按钮').onClick(() => { this.approve(r); })
          },(r: AdRule) => r.id + r.text)
          Button('结束学习').onClick(() => { clearLearn(this.dir()); this.refresh(); })
        }
        Row({space: 10}) {
          Button('导入规则包').enabled(!!this.repo).onClick(() => { this.pick(); })
          Button('导出规则包').enabled(!!this.repo).onClick(() => { this.share(); })
        }
        if (this.preview) {
          Text('导入预览 · 将替换全部个人规则和开关').fontWeight(FontWeight.Bold)
          ForEach(this.preview.apps,(a: AppProfile) => {
            Text(a.label + ' · ' + a.bundle + (a.enabled ? ' · 开启' : ' · 关闭') + (a.bank ? ' · 银行' : ''))
            ForEach(a.rules,(r: Rule) => { Text(JSON.stringify(r)).fontSize(12) },(r: Rule) => r.key)
          },(a: AppProfile) => a.bundle)
          Button('确认上述规则及银行启停').onClick(() => { this.applyImport(); })
          Button('取消导入').onClick(() => { this.preview = undefined; })
        }
        ForEach(this.config.apps,(a: AppProfile) => {
          Column({space: 6}) {
            Row() {
              Text(a.label).fontSize(19).layoutWeight(1)
              Toggle({type:ToggleType.Switch,isOn:a.enabled}).enabled(!a.bank || a.rules.length > 0)
                .onChange((v: boolean) => { if (v !== a.enabled) { this.edit(a.bundle,(x: AppProfile) => { x.enabled = v; }); } })
            }.width('100%')
            Text(a.bank ? '仅使用已确认专用规则' : '内置通用开屏 + 已确认专用规则').fontSize(13)
            Row({space: 8}) {
              Button('学习当前广告').onClick(() => { this.learn(a.bundle); })
              Button('规则 ' + a.rules.length).onClick(() => { this.expanded = this.expanded === a.bundle ? '' : a.bundle; })
            }
            if (this.expanded === a.bundle) {
              Text(a.bundle + ' · ' + (a.versions.join('、') || '所有版本'))
              ForEach(a.rules,(r: Rule) => {
                Text(JSON.stringify(r)).fontSize(12)
                Button('移除 ' + r.key).onClick(() => { this.edit(a.bundle,(x: AppProfile) => {
                  x.rules = x.rules.filter((keep: Rule) => keep.key !== r.key);
                  if (x.bank && !x.rules.length) { x.enabled = false; }
                }); })
              },(r: Rule) => r.key)
            }
          }.padding(12).width('100%').backgroundColor('#EEF4F1').borderRadius(12)
        },(a: AppProfile) => a.bundle + JSON.stringify(a))
        Text('最近诊断').fontWeight(FontWeight.Bold)
        Text(this.diagnostic || '暂无记录').fontSize(12)
        Button('清空诊断').onClick(() => { writeState(this.dir(),'cleared',Date.now().toString()); this.refresh(); })
        Button('90 秒模拟验证').enabled(!this.working && !!this.repo).onClick(() => { this.start(false); })
      }.padding(18).width('100%')
    }.width('100%').height('100%')
  }
}
