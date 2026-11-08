import { commonEventManager } from '@kit.BasicServicesKit';
import { AppProfile } from '../RuleModel';
import { readState, writeState } from '../ProbeState';
import { VersionSnapshot } from '../session/VersionSnapshot';
export class VersionGate {
  private sub?: commonEventManager.CommonEventSubscriber;
  private dir: string = ''; private run: string = '';
  private invalid: boolean = true;
  private loaded: boolean = false;
  private names: Map<string,string> = new Map();
  async start(dir: string, run: string): Promise<void> {
    this.dir = dir; this.run = run;
    try {
      this.sub = await commonEventManager.createSubscriber({events:['usual.event.PACKAGE_REPLACED',
        'usual.event.PACKAGE_ADDED','usual.event.PACKAGE_REMOVED','usual.event.PACKAGE_CHANGED']});
      commonEventManager.subscribe(this.sub,() => { this.invalid = true; });
      this.invalid = false; writeState(dir,'version.ready',run);
    } catch (_) { this.invalid = true; }
  }
  allows(app: AppProfile): boolean {
    if (!app.versions.length) { return true; }
    if (this.invalid) { return false; }
    if (!this.loaded) {
      if (readState(this.dir,'version.complete') !== this.run) { return false; }
      const raw = readState(this.dir,'version.snapshot');
      if (!raw) { return false; }
      try {
        const snapshot = JSON.parse(raw) as VersionSnapshot;
        if (snapshot.run !== this.run || !Array.isArray(snapshot.apps)) { return false; }
        for (const record of snapshot.apps) { this.names.set(record.bundle,record.name); }
      } catch (_) { this.invalid = true; return false; }
      this.loaded = true;
    }
    return app.versions.includes(this.names.get(app.bundle) || '');
  }
  close(): void {
    try { if (this.sub) { commonEventManager.unsubscribe(this.sub); } } catch (_) {}
  }
}
