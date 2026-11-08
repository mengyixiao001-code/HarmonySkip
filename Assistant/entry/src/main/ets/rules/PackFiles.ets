import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
export async function selectPack(ctx: common.UIAbilityContext): Promise<string> {
  const paths = await new picker.DocumentViewPicker(ctx).select({ maxSelectNumber: 1, fileSuffixFilters: ['.json'] });
  if (!paths.length) { return ''; }
  const f = fileIo.openSync(paths[0],fileIo.OpenMode.READ_ONLY);
  try {
    const size = fileIo.statSync(f.fd).size;
    if (size < 1 || size > 6 * 1024 * 1024) { throw new Error('规则包大小超出范围'); }
    const bytes = new ArrayBuffer(size);
    if (fileIo.readSync(f.fd,bytes) !== size) { throw new Error('文件未完整读取'); }
    return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(bytes));
  } finally { fileIo.closeSync(f); }
}
export async function exportPack(ctx: common.UIAbilityContext, text: string): Promise<boolean> {
  const paths = await new picker.DocumentViewPicker(ctx).save({ newFileNames: ['轻跳-个人规则包.json'] });
  if (!paths.length) { return false; }
  const f = fileIo.openSync(paths[0],fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    const bytes = new util.TextEncoder().encodeInto(text);
    if (fileIo.writeSync(f.fd,bytes.buffer) !== bytes.byteLength) { throw new Error('文件未完整写入'); }
  } finally { fileIo.closeSync(f); }
  return true;
}
