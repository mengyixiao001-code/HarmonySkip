import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Catalog } from '../RuleModel';
export function readCatalog(ctx: common.Context): Catalog {
  const bytes = ctx.resourceManager.getRawFileContentSync('catalog.json');
  return JSON.parse(util.TextDecoder.create('utf-8').decodeWithStream(bytes)) as Catalog;
}
