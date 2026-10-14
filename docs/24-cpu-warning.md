# CPU温度预警设计与验收

更新：2026-10-14；用户已授权按本方案更新文档后开发。实施契约v1族修订4。目标是本机课程使用和演示；本页描述待实现行为，测试证据另存，不代表已通过。

## 1. 范围和默认规则

监控对象仅为 `cpu.zone.max`：当前profile固定12个Qualified CPU热区同批完整Raw最大值。不是逐物理核心、物理Package、外壳温度或硬件损坏诊断。主界面继续显示EMA；预警使用Raw，提示必须说明使用了哪一种值。

默认启用预警；触发温度90°C，连续有效应用读取达到5秒触发。恢复温度为触发温度减5°C；连续有效读取低于或等于恢复温度10秒后恢复。系统通知默认关闭，由用户开启。90°C等值是产品默认规则，不是Apple官方安全限值。

用户可修改enabled、thresholdC、durationSeconds、systemNotificationsEnabled。温度必须有限且在5..120°C；持续秒数必须有限且在1..300。恢复回差5°C、恢复持续10秒、通知冷却60秒、会话事件上限50由 `contracts/defaults-v1.json` 的 `cpu_warning` 唯一定义。配置非法须给出可见原因并采用有效默认规则，不能静默关闭监控。

## 2. 状态及时间

CPUWarningRule、CPUWarningState、CPUWarningEvent、CPUWarningSnapshot的精确结构见[API契约](contracts/api-v1.swift)。状态包括关闭、正常、待触发、预警、待恢复和无法判断；Snapshot与RunningPresentationState携带同一warning边界，页面不组合独立报警布尔值。

- 新的完整有效CPU Raw最大值 >=阈值时开始/继续待触发；以相邻应用采样Timestamp.elapsedNS计算持续，达到规则时间才触发。
- 低于触发阈值的有效样本中断待触发。活跃预警只有有效样本 <=恢复阈值且持续10秒才结束为recovered；两阈值之间保持预警，恢复计时重新开始。
- 同温度的新合法读数可以计时。Freshness.unknown不否定真实读取；不宣称硬件传感器与应用采样同步刷新。UI刷新和重复Snapshot不是新样本。
- CPU周期切换不重置同一连续段的累计；任何持续判断均不使用样本数乘周期。仅实际Gap中断累计。
- 失败、CPU成员不齐、超时、过期、来源/连续段变化、软件生命周期中断均重置待触发/待恢复。活跃事件结束为interrupted(reason)，状态为unableToAssess；缺测绝不产生温度恢复。新的有效样本开始新累计。
- 开关或规则任一字段变化时结束当前事件为disabled或ruleChanged，重新计时，不标recovered。相同规则重复应用不改状态、不造事件。
- pending.since是首次高温候选样本时间；event.started是满足持续条件的实际触发样本时间。墙钟变化不改变持续与冷却。

## 3. 提交边界与事件

预警状态机在MonitorEngine actor的已有串行mutation边界内暂算，仅匹配ProcessingReceipt成功后与Raw/EMA一起推进真实内存状态。提交失败、拒绝回执、旧generation、乱序/非法数据、请求重放不产生可见预警或重复事件。不得在UI、历史查询或采样成功但未提交的回调发送通知。
快照读取不等待正在进行的持久化提交，只发布已提交值；快照允许到期中断，禁止生成新样本或触发/恢复事件。匹配Receipt后统一按当前时钟重查本批CPU样本TTL；若等待期间已到期，或已发布预警发生过期中断，则以当前已发布的事件历史重新暂算本批，不能用旧暂算副本复活事件，也不能用迟到的过期样本新触发。该语义不依赖是否有快照消费者。


事件记录触发身份、时间、规则阈值/持续时间、Raw峰值及active/ended原因。事件只保存在当前会话的有界内存中，保留最近50条。退出后不恢复事件或温度，当前SQLite schema/user_version=1不变。配置偏好经UserDefaults保存四个可变字段，允许跨启动恢复。

## 4. 界面与系统通知

设置页增加CPU温度预警分组、阈值/持续秒数、两开关、恢复说明、应用按钮及输入错误。Dashboard、Popover、菜单栏共享状态：预警符号配合文字和辅助功能描述，保留温度live/cached/stale语义；主窗口提供本会话事件列表。关窗继续判断；标准重开保留同会话状态且不重复通知；正常退出停止检测。

使用UserNotifications普通本地通知，用户开启时才申请alert权限，不申请critical-alert entitlement。未申请、允许、拒绝、不可用及投递错误可见；拒绝后不反复弹框。权限或投递失败不停止采样、不升级为采集Fatal。点击当前会话通知打开已有主窗口。

已提交的活动事件驱动提醒，同事件只尝试一次，不同事件间至少60秒；持续高温不定时重复发送。异步授权/投递前后重查会话、规则和活动事件。距event.started达到60秒的迟到通知不发送；规则变化、事件结束、Fatal或退出取消待发请求。去重内存有界。add成功表示系统接受请求，不证明横幅必达；正式ad-hoc App授权/投递必须实际验证。历史已投递通知不是当前实时温度。软件暂停采集时pause通知dispatcher，取消待发并清除旧快照；成功恢复后resume同会话，保留去重和冷却，在新快照前不投递。Fatal/退出stop后不可resume。

## 5. 实施文件和衔接

- Core：Warnings/规则类型与纯Evaluator、MonitorEngine提交接入、PresentationTypes快照字段。
- SensorRuntime：SessionMonitorController的规则设置方法；App SessionCoordinator传递动作。
- TemperaturePresentation：warning状态转发、配置偏好与通知策略/dispatcher的可测试逻辑。
- App：AppSessionRuntime装配、AppDelegate动作、共享预警视图、Settings、Dashboard、Popover、StatusItem、UserNotifications薄适配器及Xcode文件引用。
- Configuration及资源：cpu_warning解码/校验，三份defaults副本同步；相关版本资源随revision4同步。传感器键表、worker协议、SQLite温度schema不变。

实施计划见[预警任务计划](superpowers/plans/2026-10-14-cpu-warning.md)，并映射W12/T12.1..T12.5和TC-WARNING。接口、默认值、需求正文hash、追踪、验收、任务及实际代码在同一原子契约提交同步。

## 6. TC-WARNING验收

软件验证：阈值/时间边界、尖峰、持续高温、回差恢复、同值新样本、五档切换、失败/Gap/过期/来源变化、未知硬件更新时间、幂等/拒绝提交、规则变化、50条上限、图表重建不丢状态；规则存取与非法偏好；通知拒绝/失败/冷却/去重及异步失效。

正式App短测：真实CPU12/单位、降低用户阈值后持续触发、页面与菜单状态、事件记录、关窗重开无重复、配置恢复、开启通知的授权/投递结果、正常退出。恢复逻辑用确定性软件测试覆盖；如本机未观察到自然恢复应如实标未观察，不施加过热压力、不把调整阈值记为温度恢复。模拟数据仅用于测试，不进入Release。

运行一次最终完整Core回归及现有>=80%覆盖门槛、必要五CI和一次最终独立审查。验收不恢复物理睡眠、72h耐久、五档10分钟、公证/公开发行/跨机资格。真实缺陷仍需Issue和回归。

证据新增到按日期/源码命名的validation目录；2026-10-03无告警证据只描述旧版本，不能用于本次REQ-125。测试/文档变更不触发重复实机长测。

## 7. 开发与交付

基线origin/main d02f7f2，分支feature/cpu-warning，隔离worktree保留原工作区。适用文档门禁、测试、独立审查和同head CI通过后按项目Git流程提交、push、PR并交维护者合并；使用merge commit，保留开发分支。新功能完成状态必须以本次证据填写。
