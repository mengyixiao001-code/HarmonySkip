import hdc from 'libhs_session.so';
import { common } from '@kit.AbilityKit';
import { AppProfile } from '../RuleModel';
import { osAccount } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { readState, writeState } from '../ProbeState';
import { clearLearn, getHealth, Health } from '../session/SessionState';
let serverStarted: boolean = false;
let outstanding: boolean = false;
function delay(ms: number): Promise<void> { return new Promise<void>((resolve) => { setTimeout(resolve, ms); }); }

function command(text: string, temp: string, target: string = ''): Promise<string> {
  if (outstanding) { return Promise.reject(new Error('上一条连接请求仍在执行，请稍后再试')); }
  outstanding = true;
  return new Promise<string>((resolve, reject) => {
    const timer = setTimeout(() => { reject(new Error('连接超时，请检查手机上的无线调试端口和授权提示')); }, 12000);
    try {
      hdc.run(text, temp, target).then((out: string): void => {
        outstanding = false; clearTimeout(timer); resolve(out.trim());
      }).catch((): void => {
        outstanding = false; clearTimeout(timer); reject(new Error('本机调试任务未完成'));
      });
    } catch (e) { outstanding = false; clearTimeout(timer); reject(new Error('无法调用本机调试组件')); }
  });
}

async function connectPhone(temp: string, port: string, report: (s: string) => void): Promise<string> {
    const addresses: string[] = ['127.0.0.1'];
    try {
      const net = await connection.getDefaultNet();
      const props = await connection.getConnectionProperties(net);
      for (const link of props.linkAddresses) {
        const own = link.address.address;
        if (/^\d{1,3}(\.\d{1,3}){3}$/.test(own) && !addresses.includes(own)) { addresses.unshift(own); }
      }
    } catch (_) { /* Loopback also works without an active network on some builds. */ }
    for (const own of addresses) {
      const addr = own + ':' + port;
      report('正在连接本机 ' + addr);
      const result = await command('tconn ' + addr, temp);
      if (/denied/i.test(result)) { throw new Error('本次无线调试授权被拒绝'); }
      if (!/connect ok/i.test(result)) { continue; }
      report('已连到本机，等待手机允许无线调试');
      for (let i = 0; i < 25; i++) {
        const listing = await command('list targets -v', temp);
        writeState(temp,'connection.targets',listing);
        const targets = listing.split('\n')
          .map((s: string) => s.trim().split(/\s+/));
        const connected = targets.filter((row: string[]) => row[2] === 'Connected');
        if (connected.some((row: string[]) => row[0] === addr)) {
          const probe = await command('shell echo HS_SESSION_OK', temp,addr);
          if (probe.split(/\s+/).includes('HS_SESSION_OK')) { return addr; }
        }
        await delay(1000);
      }
      throw new Error('已连接 ' + addr + '，但未取得无线调试授权');
    }
    throw new Error('本机调试未连通，请核对无线调试端口并允许系统授权');
  }


export async function activate(ctx: common.UIAbilityContext, port: string, monitor: boolean, apps: AppProfile[], report: (s: string) => void): Promise<void> {
  if (!/^[1-9][0-9]{0,4}$/.test(port) || Number(port) > 65535) { throw new Error('请输入无线调试页面显示的端口号'); }
  if (!serverStarted) { hdc.start(ctx.tempDir); serverStarted = true; await delay(600); }
  const target = await connectPhone(ctx.tempDir,port,report);
  const dir = ctx.getApplicationContext().filesDir;
  writeState(dir,'port',port);
  const run = Date.now().toString();
  writeState(dir,'active',run); clearLearn(dir); writeState(dir,'mode',monitor ? 'monitor' : 'probe');
  if (monitor && apps.some((a: AppProfile) => a.versions.length > 0)) {
    await prepareVersionQuery(dir,ctx.tempDir,run,apps,target);
  }
  const args = 'aa test -b local.harmonyskip.assistant -m entry -s unittest ProbeRunner -s hsRun ' + run +
    (monitor ? ' -s hsMode monitor -w 0' : ' -w 100');
  await command('shell nohup ' + args + ' </dev/null >/dev/null 2>&1 &',ctx.tempDir,target);
  for (let i = 0; i < 16; i++) {
    if (readState(dir,'active') !== run) { throw new Error('启动已取消或被新会话替代'); }
    const health = getHealth(dir);
    if (monitor ? health.run === run && health.successfulChecks > 0 &&
      health.beat > 0 && Date.now() - health.beat >= 0 && Date.now() - health.beat < 15000 &&
      ['运行中','学习中'].includes(health.phase) : !!readState(dir,run)) { return; }
    await delay(350);
  }
  if (readState(dir,'active') === run) {
    const failed = new Health(); failed.run = run; failed.phase = '需要重新激活';
    failed.detail = '未收到服务成功检查的回执';
    writeState(dir,'health',JSON.stringify(failed));
  }
  throw new Error('测试服务启动未确认，请重新激活并检查系统授权');
}

async function prepareVersionQuery(dir: string, temp: string, run: string, apps: AppProfile[], target: string): Promise<void> {
  // aa test replaces the UI process. The authorized shell must finish the version
  // lookup after the runner subscribes to package changes, independently of the UI.
  const user = await osAccount.getAccountManager().getOsAccountLocalId();
  if (!Number.isInteger(user) || user < 0) { throw new Error('无法确定手机用户'); }
  const sandbox = '/data/app/el2/' + user + '/base/local.harmonyskip.assistant/files';
  // HDC may overwrite existing sandbox files but cannot create files here.
  writeState(dir,'version.snapshot',''); writeState(dir,'version.complete','');
  const commands = [
    'cd ' + sandbox + ' || exit 1',
    'for i in $(seq 1 40); do [ "$(cat active)" = "' + run + '" ] || exit 1; ' +
      '[ "$(cat version.ready 2>/dev/null)" = "' + run + '" ] && break; sleep 0.25; done',
    '[ "$(cat version.ready)" = "' + run + '" ] || exit 1',
    'out=version.snapshot', '{',
    'printf \'{"run":"' + run + '","apps":[\'',
    'sep=""'
  ];
  for (const a of apps) {
    if (!a.versions.length || !/^[A-Za-z][A-Za-z0-9_.]*$/.test(a.bundle)) { continue; }
    commands.push('v=$(bm dump -n ' + a.bundle + ' | grep \'"versionName"\' | tail -1 | sed \'s/^.*"versionName":[[:space:]]*//;s/,$//\')',
      'if [ -n "$v" ]; then printf \'%s{"bundle":"' + a.bundle + '","name":%s}\' "$sep" "$v"; sep=,; fi');
  }
  commands.push('printf \']}\'', '} > "$out" || exit 1', 'if [ "$(cat active)" = "' + run + '" ]; then printf ' + run + ' > version.complete; fi');
  writeState(dir,'version-query',commands.join('\n'));
  await command('shell nohup sh ' + sandbox + '/version-query </dev/null >/dev/null 2>&1 &',temp,target);
}
