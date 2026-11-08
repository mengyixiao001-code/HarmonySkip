import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

export function readConfigFile(dir: string, key: string): string {
  try {
    const value = fileIo.readTextSync(dir + '/' + key);
    // Missing is the only valid empty state; an existing zero-byte file must fail JSON validation.
    return value || ' ';
  } catch (e) {
    if ((e as BusinessError).code === 13900002) { return ''; }
    throw e as Error;
  }
}
export function readState(dir: string, key: string): string {
  try { return fileIo.readTextSync(dir + '/' + key); } catch (_) { return ''; }
}
export function writeState(dir: string, key: string, value: string): void {
  const path = dir + '/' + key;
  const tmp = path + '.' + Math.random().toString(36).slice(2) + '.tmp';
  const file = fileIo.openSync(tmp,fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    try { if (value) { fileIo.writeSync(file.fd,value); } } finally { fileIo.closeSync(file); }
    fileIo.renameSync(tmp,path);
  } catch (e) {
    try { fileIo.unlinkSync(tmp); } catch (_) {}
    throw e as Error;
  }
}
