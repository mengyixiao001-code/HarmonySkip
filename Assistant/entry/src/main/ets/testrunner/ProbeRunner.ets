import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';

export default class ProbeRunner implements TestRunner {
  onPrepare(): void {}
  onRun(): void {
    const args = abilityDelegatorRegistry.getArguments().parameters;
    if ((args['-s hsMode'] || args['hsMode']) === 'monitor') {
      import('./MonitorSession').then((session) => {
        return new session.default().onRun();
      }).catch(() => {
        abilityDelegatorRegistry.getAbilityDelegator().finishTest('运行模块加载失败', 1);
      });
      return;
    }
    import('./ProbeSession').then((session) => {
      return new session.default().onRun();
    }).catch(() => {
      abilityDelegatorRegistry.getAbilityDelegator().finishTest('测试模块加载失败', 1);
    });
  }
}
