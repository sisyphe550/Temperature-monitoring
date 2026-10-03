# 测试、验收向量与证据标准

更新：2026-10-03；实施契约v1族修订3。当前本机课程门槛为[课程范围](course-delivery-scope.md)及[五criterion政策](contracts/course-delivery-v1.json)，全132项资格是可选扩展。软件、fixture、正式Release实机和发行证据分开，旧失败/未测结果保持，不因范围收缩批量通过。当前最小收尾仍进行中。

## 自动化和实机分层

| 用例组 | 固定输入/操作 | 预期/通过条件 |
|---|---|---|
| TC-PLATFORM | Mac16,13+15.7.3；低版本；非Air；未知Air | 正确profile；不合格机型/版本拒绝；未测build不进入正式支持矩阵 |
| TC-SENSOR | 12个CPU键齐全/缺1/编码改变；IOPS缺字段；TB1T成功；SMART0K/300K | 完整集合才派生；Battery按优先级固定单源；SSD0不可用、300K=26.85°C；不猜HID/IORegistry单位 |
| TC-VALIDATE | null、NaN、±Inf、−274°C、重复70、同ID异值、旧generation | 非法拒绝；重复成功值保留；ID冲突报错；晚到旧代不进入算法 |
| TC-SCHEDULE | TestClock前进，各CPU五档；默认；中途换档；慢调用；退避 | 计划时刻正确，修改后nextDue重算，旧请求沿用旧period；不重叠、不补采积压；skipped/失败计数分开 |
| TC-BUFFER | 50ms连续>300s、周期切換、32series上限 | 最近300s半开TTL、每Buffer≤8192、无未交付数据被覆盖；32包含派生 |
| TC-EMA | 80@0s、100@0.5s、100@1s，tau0.5 | 80、92.6424111766、97.2932943353，绝对误差≤1e-8；非正dt拒绝 |
| TC-AGG | Raw70/71/72/95/74；A60×1+B80×3；稀疏10s；同秒换段 | max95/avg76.4；合并avg75；边界闭合且partial；不同段不同主键 |
| TC-TREND | 以0.1°C/s增长、0.01°C/s增长、−0.1°C/s、仅2点、覆盖不足80%、含Gap | rising/stable/falling；不足时slopeNULL；不跨Gap |
| TC-STORAGE | 一个不可变批次两次提交；提交成功但ack丢失；同ID异载荷；rollback | 不重复Raw/EMA/count；异载荷DB-INTEGRITY-010；事务不留下半份加工结果 |
| TC-RETENTION | 虚拟时间跨300s/1h/24h/72h；父层未提交；sleep>72h；清理失败 | 查询立即过滤；父层先提交；空窗不补0；超过120s宽限失败，不无限增大 |
| TC-HISTORY | 5min/1h/24h/72h，各8series，超8、无数据、2000点降采样 | 层级正确、≤16000点、max95保留、缺口断线；任意过去范围不提供 |
| TC-ERROR | 四种重试先失败后成功/全部失败；CPU缺1；可选失败；查询锁竞争 | 次数不含首次且不嵌套；可选继续，CPU主值无法生成耗尽Fatal；固定错误码 |
| TC-LIFECYCLE | sleep/wake、墙钟±1h、双实例、正常退出、强杀后启动、拒绝清理符号链接 | 同会话保留非过期数据、换段、不回拨TTL；第二实例不清库；只删自己会话 |
| TC-UI | 菜单栏左右键、Esc、点击外部、⌘W/⌘Q、无值/缓存/过期、浅深色、键盘、小屏 | 符合07；摄氏一位小数；关窗口不断采样；没有逐核温度/告警/自启动 |
| TC-UPSTREAM-BOUNDARY | Stats旧值回退、SwiftTempBar缺事件/名称分类、12来源对10物理核、同名不同registryID、Release产物扫描、缺第三方登记/许可 | 旧值不生成新样本；缺事件不生成0°C；名称/数量不产生物理语义；不同registryID不合并；无写SMC/root/helper/fixture；copied/modified未登记即失败 |
| TC-WORKFLOW | 失败CI、open blocking Issue、过期head检查、未保护main | 必须拒绝合并；merge commit且保留远端分支；通过不能只看旧SHA |
| TC-DOCS | 134ID/132active/2retired、链接、DDL、参数、任务与正文hash | `validate-handoff.py`通过；已删除项不进入实现任务 |
| TC-RELEASE | 当前本机Release/worker ad-hoc签名和身份；可选Developer ID、公证ZIP、Gatekeeper/发行复测 | 本机交付绑定实际SHA；未执行公证不标通过，也不阻塞当前本机课程 |
| TC-ENDURANCE | 可选72/73h真实运行与五档各10min；必要软件虚拟时间TTL/有界回归保留 | 本轮不执行实机长跑；未测不标通过。72h历史功能、TTL与数据边界不变 |
| TC-ACCEPTANCE | 当前五课程criterion绑定原证据；旧132项逐REQ矩阵保留 | course-local与旧strict资格分别判定；pending不批量接受，2退役不适用 |

## 必须覆盖的交叉场景

1. 同批A/B为(100,20)、(20,100)，算法测试alpha固定0.5：先max再EMA仍100；各源EMA后max为60，不能混淆。
2. 请求从0.99s开始到1.02s结束；1s封窗等待安全水位，按每源完成时间入窗，不让晚到回复改已经提交的桶。
3. 在同一秒内重连，旧generation在新请求之后返回；只有新代进入数据链，来源/定义/segment隔离。
4. 写队列高水位时已有一条在途读取：预留容量足以容纳整批，暂停后不再启动新请求；已接纳数据最终提交或明确Fatal，不能静默丢弃。
5. SQLite提交成功但返回链路丢ack，使用相同batchID重试；Raw/EMA/聚合各一份。相同ID不同payload必须失败。
6. 查询取消、锁竞争、WAL过软限、磁盘满、报告目录不可写；UI缓存/过期和独立错误兜底仍可观察。
7. 默认CPU档位每次新会话为200ms；频率切换不清历史、不重置无Gap的EMA；五分钟内存显示与EMA持久化同时存在。
8. 构造上游常见错误路径：成功一次后失败、事件字段缺失、显示名相同但registryID不同、12个温度来源但10个物理核。结果必须保持失败/能力状态和独立身份，不能补旧值、补0°C、合并来源或生成Core编号。
9. 将一个未登记的copied/modified测试文件放入许可门禁夹具，验证CI失败；对正式Release App及worker扫描写SMC符号、root/helper调用和测试fixture，任何命中阻断发布。

## 产品覆盖率与命令

分母包含`Packages/TemperatureCore/Sources/TemperatureCore/`与`Sources/SensorRuntime/`所有自有Swift业务代码：适配选择、协议/调度、校验、算法、存储、错误、生命周期。仅排除第三方未修改代码、C桥接薄ABI与App纯视图；C桥接由ABI/解码/资源生命周期及实机检查单独验收。不得排除难测的错误分支降低分母。

W01～W08实现以下命令后，CI核心行覆盖率至少80%，并保留LCOV/llvm-cov报告。关键向量与异常测试独立于覆盖率数字：

```sh
swift test --package-path Packages/TemperatureCore --enable-code-coverage
python3 scripts/check-core-coverage.py
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
python3 scripts/validate-handoff.py
```

上述产品文件和命令已存在，用于当前修复分支的产品验收；原型检查仅用于探针回归：`swift test --package-path prototypes/sensor-probe --enable-code-coverage`、`python3 scripts/check-probe-coverage.py`、`swift build --package-path prototypes/sensor-probe -c release`及`python3 scripts/test-probe-cli.py`。

原型8测试与55/55 ProbeCore覆盖不等于产品80%门禁。正式UI黑盒不能只测ViewModel；托管macOS CI不证明Air传感器。

## 本轮正式App与资源观察

W09使用当前源码构建的正式Release App，普通用户、无fixture。确认真实CPU12/来源单位和数值，执行启动、五档短切换、历史范围/点选、菜单/Popover、关窗重开同会话及正常退出。首50ms档约330秒覆盖最近5分钟图，其他四档各8秒；同会话观察owned App/child Worker CPU/RSS及交互，不使用压力负载，也不重复五档10分钟或物理睡眠。

COURSE-CPU结合正式App成功读取与必要软件失败回归证明边界；实际硬件短测未发生故障时，不声称实机故障路径已触发。失败不补0/旧值、CPU缺成员不能派生max、SQLite故障不发布未提交状态等必须保留；关键数据、管道、生命周期、退出/残留清理软件回归属于COURSE-REGRESSIONS。正常退出本次App/Worker结束且本会话目录消失；不额外强杀第二次真实App。

COURSE-RESOURCES记录时间、档位/图表、owned PID/PPID、CPU单核100%口径、累计CPU TIME、RSS KiB及操作响应。比较50ms稳定后段的区间CPU与RSS变化，报告明显异常、趋稳或观察不足；不发明百分比阈值，不把预热/填图缓存等同泄漏。短测只支持本机本轮观察，不能证明全部硬件无泄漏或准确延迟百分位。

每份报告保存source/App/worker SHA、profile、机型/OS build、权限/签名、输入、预期/实际、时长、结果及原始证据。真实可复现缺陷按11建Issue并回归，真实blocking未解决不得合并。

## 可选严格资格

旧扩展资格保留五档各10分钟空闲/受控负载、真实sleep/wake及72/73h耐久；对应旧性能目标skipped≤1%、读批p95≤周期/p99≤2×周期、首帧/显示p95≤500ms留在strict模式，不是当前课程门槛。未测保持未测，不能用Raw相邻完成间隔、理想点数短缺或间歇AX快照替代精确指标。若未来明确恢复该范围，再新增实机证据；不修改历史报告。

取消长跑不删除72h分层历史、容量/TTL120秒清理宽限或软件sleep/wake；CPU成员、周期、单位、失败状态、算法与schema不变。原型/CLI、CI和模拟不替代正式App实机；当前本机短测不替代可选扩展资格。

## 修订3适用回归（2026-10-02）

TC-SENSOR/TC-UPSTREAM-BOUNDARY覆盖NVMe位置事实缺失、父树失败、非Internal、多候选、WorkerProtocol闭合枚举和Battery资格化；TC-SCHEDULE覆盖CPU非零耗时下Battery/SSD同相位不饥饿；TC-DB/TC-RETENTION覆盖临时错误相同payload重试、并发reservation和周期TTL；TC-VALIDATE/TC-ERROR覆盖CPU缺成员、超时恢复/耗尽、日志报告、过期重放拒绝。REQ映射与任务DAG不变，修复证据另存；模拟通过不等于正式硬件通过。最新课程范围将实机长测、公证/发行/跨机与精确性能列为可选，本轮正式App短测和上述必要软件回归仍必需。

## 本轮门槛与已有证据

```sh
python3 scripts/validate-handoff.py --product-acceptance
python3 scripts/validate-handoff.py --strict-product-acceptance
```

course-local检查COURSE-CPU/FUNCTIONS/RESOURCES/REGRESSIONS/CORE，strict保留旧全132项资格；不是同一完成状态。核心≥80%及异常分母不变。最终独立审查、同head五CI和零真实blocking在11的外部流程回读，不让文档CI要求自身未来完成。

[7124归档](validation/product-software/W11/2026-10-03-7124dc1/README.md)保留断管错误/子进程回收、完整Core和原正式App短测；[f0归档](validation/product-software/W11/2026-10-03-f0a7dde/README.md)保留Generation/Budget/Wake/SleepAdmissionRace的提交边界同步、失败及负控。旧逐REQ仍100accepted/31pending/1waived/2retired；本轮全Core与正式短测须另绑定实际源码/产物，不因这些链接预先通过。
