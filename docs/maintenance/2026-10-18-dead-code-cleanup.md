# 死代码清理与保留边界

日期：2026-10-18。基线：`7b5f7b46ebb3b1e1799d35f4a6cc999736e2c0f0`（PR #58 已合入的 main）。分支：`feature/dead-code-cleanup`。

目标为保持当前课程 App 行为不变，清理能由源码、构建入口、现行契约、测试和 Git 演变共同确认的残留实现。未改变 contract revision 5、135项需求映射、CPU12、来源与单位、预警/分析、历史层级、生命周期或可选验收范围。历史 research/validation、课程 Word/PPT/图表和第三方许可资源不修改。

## 确认方法

检查实际 App/SwiftPM/Xcode/CI 入口，逐项搜索生产调用与测试引用，再对照现行设计和 Git 历史。仅“搜索不到调用”不足以删除框架回调、动态入口、契约类型、异常防御或仍在设计中要求的能力。未安装额外静态分析依赖，也不将未覆盖代码等同于死代码。

## 已清理

| 范围 | 清理内容与依据 | 保留的实际路径 |
|---|---|---|
| 核心模块 | 删除 `TemperatureCoreModule` 空枚举及占位文件；`d0f3b63` 建包占位，当前源码、测试及契约无引用 | SwiftPM仍从现有目录发现所有核心源码，不改变产品或target |
| 持久化队列 | 删除 `dequeueFlushable`、`requeueFront`、`oldestPendingAgeMS` 和只服务旧方法的 wall Date 参数/字段；`a97fd5a` 后正式提交不再调用这些方法 | `commit → flushUntil → dequeueThrough → commitWithRetry`，保留单调时钟年龄限制、Lease和Receipt |
| StorageWriter | 删除未调用的 `shouldFlush`、`validateOldestAge`、错误类型及两个配置副本 | 保留实际使用的 `maxOldestAgeMS` 与异常测试暂停机制；不删RuntimeConfiguration或默认值 |
| 数据维护 | 删除仅写的 `lastPruneElapsedNS`、两个无调用的MIN查询及无调用的schema检查包装 | 维护调度仍由controller负责；宽限检查仍用EXISTS查询；正式打开仍执行quickCheck和schema校验 |
| App | 删除无调用的实时控制查询属性、两个资源URL包装、协调器转发/查询方法和两个未产生的App错误分支 | 现有启动、设置、许可入口、运行时退出预算和recordFatal返回值 |
| 窗口 | 删除两个窗口控制器中只初始化、不读取的模型/actions属性 | 构造参数直接传入hosting view；保留delegate、关窗隐藏、标准重开和正常退出 |
| 启动元数据 | 删除协调器中第二次重复赋值 | 保留启动早期赋值，锁获取或孤儿清理失败时仍有诊断元数据（`a97fd5a`） |
| Worker | 删除HID内部缓存的两个只写字段、发现前重复清空及主循环末尾重复关闭 | 对外DiscoveredSource仍携带来源名称与身份；保留defer、close命令、deinit和连接清理 |
| 传输故障 | 删除丢弃operation/timedOut参数的薄包装，直接调用terminateWorker | 五个调用点的try/try?及错误传播保持一致，超时和协议错误语义不变 |
| 资格工具 | 删除两个无用Python常量及已经拒绝probe后不可达的参数追加分支 | 参数解析、probe拒绝、负向断言、正式App后端与全部资格子命令 |

只同步一个内部测试调用的已删除Date参数，未删除测试、断言或异常用例。生产与测试代码共17个文件，新增8行、删除147行，净减少139行；本说明文档不计入代码统计。

## 明确保留

- `FatalViewFallback`：当前没有调用，但现行错误设计及T07.5仍要求NSAlert兜底。保留并注明未接线事实；本轮不把这项设计要求当作已退役，也不声称该兜底路径得到运行验证。
- `MonitorShutdown.run`：没有正式控制器调用，属于旧public源码API；本轮保守保留。`ShutdownResult`和`ShutdownStepResult`仍在正式退出链路中使用。
- 预留状态和现行异常校验：未因当前很难触发而删除；未改Reservation合成相等性相关字段。
- App/Presentation薄类型别名、框架delegate/selector、worker入口、HID动态符号、Debug fixture及Release拒绝fixture策略。
- 72小时历史功能、软件睡眠生命周期、休眠/耐久资格工具及sensor-probe原型。当前不要求长测，不代表这些实现或工具无人使用。

这是一轮有证据的维护清理，不声明仓库内所有潜在死代码已经穷尽。保留项如需删除或补接，应先明确其契约和功能范围。

## 验证

基线全Core：445项/65组、0失败；23.823秒；7586/8493行，89.32%。

清理后结果：

- 针对性回归101项/14组、0失败，覆盖队列/背压、数据库/TTL/保留、Worker协议/回收及展示相关路径。
- 完整Core445项/65组、0失败，24.934秒；7576/8421行，89.97%。同一覆盖范围和门槛，分母变化来自实际删除源码，不是修改包含/排除规则。
- 正式Release App与SensorWorker构建成功；ad-hoc签名验证、TC-UPSTREAM-BOUNDARY及其负向fixture通过。
- 原生UI列入23项：20项实际通过、3项跳过、0失败，96.440秒。Release fixture拒绝由已有单元测试覆盖而在UI中跳过；真实App和五档10分钟用例需显式环境开关，均跳过；本轮正式App另做短测。
- 资格schema/runner共8项检查通过，禁止probe的有效负向断言保留。首次受限环境运行因Xcode缓存写权限退出74，未到业务断言；获得缓存访问后重跑通过。
- 课程政策40项、分析证据边界9项、覆盖率门禁fixture、文档和课程验收检查通过。
- 一次最终独立静态审查未发现功能或阻断缺陷。审查覆盖本轮17文件代码diff；不声称核验仓外私有消费者。移除的App public访问器/错误case及Core占位不属于现行api-v1契约，也不构成对外发布SDK。
- 正式Release本机短测：CPU12全部targetQualified，CPU主Raw样本实际涵盖50/100/200/500/1000ms；结束前观察时点为本会话241.93秒，已写4034条聚合记录。真实温度、单位、来源、Raw/EMA分列、系统nominal、上升/下降趋势与建议、设置、5分钟及1小时历史/点选可见。五档为短切换，非各10分钟；关窗/标准重开由本轮通过的XCUITest验证，人工CUA未独立确立窗口隐藏状态，不作为额外通过证据。通过正式退出按钮结束后，App及Worker均退出，本轮会话目录已删除。采样恢复200ms；未改90°C/5秒、启用预警、关闭通知的规则。实际未触发超温或非nominal整机状态，不声称重验这些硬件场景。

当前课程门禁和契约检查保持；覆盖率门槛、文件包含/排除规则和测试断言均不修改。测试日志保存在本机 `build/dead-code-cleanup-20261018/`；不执行真实休眠、长时间耐久或跨机认证。

## Git与审查边界

实施前已回读最新origin/main、main保护规则、仓库只允许merge commit且保留分支，以及零open blocking。必要检查仍为handoff-docs、probe-tests、blocking-issues、core-tests、app-build。一次独立审查的17文件代码diff与最终提交内容核对后才push；远端检查和最终集成状态以本轮PR实况为准。
