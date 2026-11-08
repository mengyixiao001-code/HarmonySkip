# 轻跳 0.3.9

轻跳在已启用的鸿蒙应用中识别开屏和弹窗，找到唯一的目标后复查并尝试关闭。Assistant 是助手，Fixture 是独立测试页。两者使用不同包名和回执。助手需要手机调试测试服务。

## 使用

1. 在本机签名的 nova 16 上覆盖安装“轻跳助手-0.3.9-本机签名.hap”。首次进入会迁移 0.2.1 名单和已确认规则。无需卸载。
2. 开启无线调试，输入系统显示的当前端口，点“启动广告跳过”。如果系统弹出授权提示，在手机上处理。运行状态依据最近成功的测试服务调用更新。停止后如需继续，请重新激活。
3. 要学习某款 App，先在助手中点该 App 的“学习当前广告”，随即切换过去。45 秒内读取到唯一可学习按钮后，返回助手核对包名、广告标记、按钮文字、ID，再点“确认并保存按钮”。等候确认时该 App 暂停自动点击。“结束学习”会取消当前请求。
4. 每款 App 的开关控制该包名。银行只使用经过预览确认的专用规则。每条规则默认每次进入最多尝试一次，另一条规则可以继续处理下一层。展开“规则”可查看或移除个人规则。
5. “导出规则包”用系统文件选择器保存本地 JSON。“导入规则包”先校验并展示完整预览，确认后替换现有个人规则和开关，缺少的内置应用会补回。需要保留原有个人修改时，先导出，再在导出文件上编辑。
6. 最近诊断显示最近 12 条。普通操作记录每 60 分钟自动清理，清理前最多保留 80 条；连接异常、结果不明及未知异常不受该数量限制，保留到手动清空。记录会话、时间、包名、规则编号、结果与错误码。“已尝试”和“结果不明”均不计作“确认关闭”。

## 工程

| 目录或文件 | 职责 |
| --- | --- |
| `Assistant/entry/src/main/resources/rawfile/catalog.json` | 随包升级的内置名单和规则 |
| `Assistant/entry/src/main/ets/rules` | 规则校验、迁移、索引、匹配与规则包读写 |
| `Assistant/entry/src/main/ets/platform` | 本机 HDC、UiTest 串行队列、页面读取、版本核验 |
| `Assistant/entry/src/main/ets/session` | 点击复查与限额、学习请求、健康和诊断 |
| `Assistant/entry/src/main/ets/testrunner` | 延迟导入、持续会话和 90 秒独立回执对照 |
| `Assistant/entry/src/main/ets/pages` | 管理界面 |
| `Assistant/native` | HDC 私有 Unix 套接字桥 |
| `Fixture` | 普通引导、模拟开屏/弹窗、两层弹窗、无 ID 学习页 |
| `tests` | 针对实际 ArkTS 模块的 Node 回归和可导入的测试规则包 |

[规则格式与示例](规则格式.md) · [0.3.9 重新激活修复](验证记录-0.3.9.md)

## 构建与测试

使用 Node 22.13 或更高版本，在本工程根目录执行 `node --test tests/*.test.mjs`。Assistant 为 0.3.9（versionCode 14），Fixture 为 0.2.0（versionCode 2）。本机工具位于 Windows 的实际 LocalApplicationData 目录。以下 PowerShell 在 Assistant 或 Fixture 根目录执行。

```powershell
$toolsRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'HarmonySkipTools'
$env:DEVECO_CLI_CLT_PATH = Join-Path $toolsRoot 'DevEco26/command-line-tools'
$env:DEVECO_SDK_HOME = Join-Path $env:DEVECO_CLI_CLT_PATH 'sdk'
$env:JAVA_HOME = Join-Path $toolsRoot 'jdk-parallel/jdk-21.0.13.0.2+1'
$env:Path = "$env:JAVA_HOME\bin;$env:DEVECO_CLI_CLT_PATH\tool\node;$env:DEVECO_CLI_CLT_PATH\bin;$toolsRoot\node_modules\.bin;$env:Path"
hvigorw.bat --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
```

Git 仓库不包含本机签名配置。首次克隆后，分别把 Assistant 和 Fixture 根目录中的 build-profile.template.json5 复制为 build-profile.json5，再配置自己的签名。分发的源码 ZIP 已使用无签名模板替换这两个配置。验证安装包保存在本机“验证包”目录，不提交到 Git。

## 回退到 0.2.1 行为

保留“验证包/轻跳-0.2.1-源码.zip”和旧签名包。升级前的 rules 原文保留在助手私有目录的 rules 和 rules.pre030，另有本机私有备份。回退时停止会话并导出需要保留的 0.3.0 配置，将 0.2.1 源码解压至独立工作目录，使用同一包名和有效签名，将 versionCode 调整为高于手机当前已安装值（从 14 回退时可用 15），重新构建后覆盖安装。确认旧版读取的 rules 与升级前备份一致。有差异时用备份恢复 rules，再打开旧版。后续再次升级也需要更高的 versionCode。

## 历史版本 0.2.x（升级前的使用与验证记录）

开启手机无线调试，输入当前端口，点“启动广告跳过”。看到“运行中”后可以关闭无线调试，随后正常使用手机。运行会话没有 90 秒的模拟验证限制；系统结束测试服务后需要重新激活。可通过助手状态和“停止”按钮控制会话。

拼多多、淘宝、京东、美团、抖音、微博默认启用待验证的通用开屏规则。仅在页面有明确广告标记、且只有一个可用的跳过控件时尝试关闭，每次进入一款应用最多尝试一次。中国银行、中国工商银行等待学习确认规则后启用。登录、协议、支付等页面的保护条件会阻止规则匹配。

遇到广告时，先在助手里找到对应 App，点“学习当前广告”后立即切换到广告页，接下来的 45 秒会持续捕捉候选，稍后回到助手确认。学习过程只记录候选关闭按钮的标识、文字和广告标记，不点击候选按钮，不持久化整页文本。没有 ID 的“跳过”按钮可以在广告标记和唯一按钮条件下识别，普通“关闭”或叉号仍需要稳定 ID。确认并保存后即结束学习等待。

0.2.1 修正了微博短开屏的捕捉时机，并在读取控件前按广告和保护标记筛选，减少整页遍历延迟。真机读取证实微博 16.10.0 的广告标记为“广告”、按钮为“跳过”，控件 ID 为空。USB 真机运行会话 1793777521259 记录了两次微博广告自动关闭。学习无 ID 按钮的匹配已加入回归测试；后续冷启动未再出现可学习广告，因此该次真人广告的学习确认流程仍待实际出现时验证。

八款 App 均已在本机确认安装。2026-11-04 的首次采样中，拼多多、淘宝、京东没有出现可确认的广告按钮，因此尚无真实 App 命中率数据。其他五款尚待广告页面采样。页面中混排的推荐内容、没有关闭按钮的视频广告也需要逐个判断。

### 旧版手机验证

1. 安装两个针对本机签名的调试 HAP。在手机开发者选项中开启无线调试，记下页面显示的端口号。
2. 打开「轻跳验证助手」，输入端口号，点「激活本次验证」。如果系统询问是否允许调试，请确认。看到「验证中」后再继续。
3. 拔掉 USB 线，关闭无线调试。打开「轻跳测试页」，在普通引导页停留几秒。引导页的「跳过」应保留。
4. 点「展示模拟开屏广告」后松手。观察倒计时结束后是否自动出现「广告已关闭」。回到助手刷新，核对两边的回执数字。验证弹窗时重新激活，再选「展示模拟广告弹窗」。
5. 每次验证最长 90 秒，最多尝试点击一次。「停止」取消当前验证。若关闭调试后失效，记录两边的状态。只有回执一致才算点击成功，拔线和关闭无线调试须在手机上实际完成。

### 旧版构建记录

在 API 26 的 DevEco Studio 中分别打开 Assistant 和 Fixture，使用自己的开发者账号和设备配置调试签名。如果导出的源码中缺少 build-profile.json5，在对应工程目录复制 build-profile.template.json5 并改名即可。也可以使用华为 DevEco CLI，分别在两个工程根目录运行以下命令。先运行一次 `devecocli auth login` 完成账号登录。

```text
devecocli signature generate
devecocli build --product default --modules entry --build-mode debug
```

每个工程的调试包输出在自己的 `entry/build/default/outputs/default/`。手机需要与签名配置匹配。完整源码和日志中请勿分享本机的签名配置、证书或口令。

### 旧版实现和验证

首次激活使用手机自己的 HDC 连接，只尝试回环或本机网卡地址。助手内部通过私有目录中的 Unix 套接字与 HDC 客户端通信。原生适配层的源码在 Assistant/native，若需重建，可运行 `python Assistant/native/build.py <Windows-SDK的native目录>`。执行端按测试 App 的包名和前台窗口查找广告标记和关闭控件，点击前复查页面编号，点击后核对目标 App 的回执。本阶段仅适配模拟页面。

在根目录执行 `node --test tests/probe.test.mjs tests/rules.test.mjs`（Node 22.13+），可以在电脑上对实际识别代码进行模拟测试，覆盖倒计时、普通引导、切换前台应用、银行规则确认和回执缺失等场景。

### 2026-11-04 真机结果

在 nova 16、HarmonyOS 7.0.0.111（API 26）上，两个包已完成个人开发者签名并安装。USB 对照测试返回成功。独立激活后，用户按流程拔掉 USB 并关闭无线调试，再触发模拟开屏广告，随后重新连接供读取结果。

断线测试的会话编号为 `1793776480136`，助手记录为“开屏验证成功，回执 1793776543862”。测试页同时显示“广告已关闭”，并返回相同编号 `1793776543862`。回执生成时间在本次激活后约 64 秒，处于 90 秒验证窗口内。

此结果验证了一次本机激活后的模拟开屏关闭。0.2.0 持续识别会话、真实 App 命中情况、模拟弹窗断线测试、长时间后台存活以及重启恢复仍需后续验证。

手机端调试组件来自 [HapInstaller v1.0.0](https://github.com/LMV475/hap-installer/releases/tag/v1.0.0)。从该发布包使用了 arm64 HDC 动态库及其 C++ 运行库。已核对原包 SHA-256 `bd20b09ae6cc503e2953e1e2e6ccc9e60f8de1d7b4e863ef78cb9820973c3dd5`。许可见 licenses 目录。
