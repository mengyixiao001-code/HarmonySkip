import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const base = new URL('../Assistant/entry/src/main/',import.meta.url);
const files = ['RuleModel','rules/RuleRepository','platform/UiService','rules/Recognition',
  'session/VersionSnapshot','platform/VersionGate','session/ActionExecutor','session/SessionState','testrunner/MonitorSession'];
const script = files.map(name => readFileSync(new URL('ets/' + name + '.ets',base),'utf8')
  .replace(/^import .*;$/gm,'').replace(/export default /g,'').replace(/export /g,'')).join('\n');
const program = new vm.Script(stripTypeScriptTypes(script) + '\nthis.api = {AppProfile,AdRule,Rule,Feature,RuleConfig,validateRule,migrate,mergeCatalog,choose,confirmed,capture,learnedRule,readPage,parseSnapshot,RuleRepository,ActionExecutor,SerialQueue,MonitorSession,VersionGate,pending,beginLearn,clearLearn,statusText,events,normalEvent,sweepLogs,logEvent,uiService};');
export function harness() {
  const catalog = JSON.parse(readFileSync(new URL('resources/rawfile/catalog.json',base),'utf8'));
  const files = new Map();
  const context = {setTimeout,Date,MatchPattern:{REG_EXP:4},
    ON:{inWindow(bundle) {return {bundle,text(){this.filter='text';return this;},description(){this.filter='desc';return this;}};}},
    readCatalog:()=>catalog,readState:(_,k)=>files.get(k)||'',readConfigFile:(_,k)=>files.get(k)||'',
    writeState:(_,k,v)=>files.set(k,v)};
  program.runInNewContext(context);
  return {api:context.api, context, files, catalog};
}
export const node = (text,id='',enabled=true,clickable=true,desc='',type='Button') => ({
  getText:async()=>text,getId:async()=>id,getDescription:async()=>desc,getType:async()=>type,
  isEnabled:async()=>enabled,isClickable:async()=>clickable,click:async()=>{}
});
export function page(nodes,bundle) {
  return {findWindow:async()=>({isFocused:async()=>true,getBundleName:async()=>bundle}),
    findComponents:async(sel)=>{assert.equal(sel.bundle,bundle);return sel.filter==='desc'?[]:nodes;}};
}
