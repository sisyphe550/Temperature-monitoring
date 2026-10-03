# 测试、验收向量与证据标准

更新：2026-10-03；实施契约v1族修订3。产品核心回归、fixture UI和正式Release本机短测已有分层执行证据，历史结果仍绑定原源码/产物；下列用例是验收标准，是否通过必须逐项核对对应证据，不能由一组结果推导全部产品通过。

受测生产源码`c354b0392a91367d42708d7424fd0e133af825b9`的[独立归档](validation/product-software/W11/2026-10-03-c354b03/README.md)区分实际duration证据、原XCTest失败、性能未测与用户跳过本轮物理休眠。c354五档清醒时长条件已分别observed：50/100/200/500ms原phase各约601秒；1000ms在同一App/worker/Session连续区间经独立clock、Cua与末端SQL补证641.637秒。原XCTest因最后一档AX控件缺失仍为FAILED，不能改suite通过。精确scheduler skipped、读批p95/p99及首帧/屏幕显示p95仍not_measured，性能门槛不变。用户2026-10-03 08:00UTC明确“跳过休眠测试”，本轮三轮物理睡眠/人工唤醒验收仅标skipped-by-user；已经触发的两次attempt观察保留partial，生命周期功能和软件回归继续保留。新SQL修复与其最终Core/Release回归须另绑定源码及App/worker身份，不能继承c354完整资格；W11和逐REQ未完成项仍按当前catalog与有效证据判定。

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
| TC-RELEASE | 最终ZIP/worker签名、Gatekeeper、公证、离线运行、权限复测 | 与发布清单相同SHA；没有凭证时明确未完成正式分发 |
| TC-ENDURANCE | 72h真实运行，默认200ms；五档各10min另测；虚拟长时压力 | 队列/Buffer/DB/WAL/日志均未破上限，TTL/缺口正确，无崩溃和未解释丢样本 |
| TC-ACCEPTANCE | 逐项132现行REQ附日志和构建/环境 | 不留无任务/无测试/无结果项；2退役明确不适用 |

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

## 硬件验收口径

W09首先确认身份、单位、固定集合，再以普通用户的正式App构建测试五档各10分钟，记录实际间隔、批耗时、skipped、失败、CPU/内存与来源新鲜度。正常空闲目标：skipped≤1%，读批p95≤所选周期，p99≤2×周期，首帧/显示延迟p95≤500ms；这些是v1验收门槛，未测不得标为通过。超标不删五档，登记缺陷并优化；受控负载段单列，仍要求界面响应、有界且缺口如实记录。

本轮UI长测分别记录清醒持续秒数、档位、温度与退出清理；SQL/collector记录成功样本完成间隔及资源观察值。当前正式App证据未导出精确scheduler skipped、读批开始/结束或可关联的屏幕呈现时间，不能用Raw相邻完成间隔、理想点数短缺或20秒一次的AX读取替代上述性能指标。五档持续性、真实睡眠和性能门槛必须分项判定；未测性能保持pending。

CPU/内存/能耗暂无百分比硬指标，资源有界上限按21执行；每个结果保存测量口径（CPU是否单核百分比）。用户已豁免本轮72/73h耐久；不得将短时测试标成长测通过。若未来恢复该验收，72小时真实测试用默认200ms、记录首末小时与每小时资源，不能用几分钟或虚拟时钟冒充。受控CPU负载只用普通用户、限定时长，不改风扇、不禁用系统保护；出现系统严重热状态就停止负载并如实记录。

每次报告记录源码SHA、App/worker哈希、profile版本、机型/OS build、权限/签名、用例、输入、预期/实际、状态及原始证据。发生可复现缺陷按11建Issue并回归。现有2026-09-15证据原样保存；新增测试另建按日期/提交命名目录。

## 修订3适用回归（2026-10-02）

TC-SENSOR/TC-UPSTREAM-BOUNDARY覆盖NVMe位置事实缺失、父树失败、非Internal、多候选、WorkerProtocol闭合枚举和Battery资格化；TC-SCHEDULE覆盖CPU非零耗时下Battery/SSD同相位不饥饿；TC-DB/TC-RETENTION覆盖临时错误相同payload重试、并发reservation和周期TTL；TC-VALIDATE/TC-ERROR覆盖CPU缺成员、超时恢复/耗尽、日志报告、过期重放拒绝。REQ映射与任务DAG不变，修复证据另存；模拟通过不等于正式硬件通过。用户已豁免72/73h、公证、公开发行与跨机型认证，本轮短时Release验证与上述软件回归仍必需。

## 当前源码回归与断管负例

当前生产源码`7124dc1644516f471d69930024589342c0ca34c9`追加Issue [#51](https://github.com/sisyphe550/Temperature-monitoring/issues/51)修复：新请求管道在spawn前配置SIGPIPE保护，断管EPIPE进入既有协议错误及worker回收；全局信号策略、公开接口、schema和默认值不变。同一公开接口用例在原f42源码signal13 RED、候选GREEN，实际子PID已回收。完整Core355项/57组PASS，覆盖7120/8002=88.98%；Release构建、签名、上游边界通过，正式App新短测1项87.162秒PASS。 [新证据](validation/product-software/W11/2026-10-03-7124dc1/README.md)保留原f42失败CI，不据并行日志顺序推断唯一触发测试。新增公开断管用例/fixture同源RED→GREEN，涵盖错误代码与实际子进程回收；单测涵盖正常newline帧、独立管道/全局SIGPIPE状态、-1无效描述符和已关闭FileHandle的Swift错误。完整回归计数355包含这些用例，不重复相加局部suite计数。 当前仍为100项接受、31项待验收、1项豁免、2项退役；本轮物理休眠按用户要求跳过，软件生命周期回归保留。原f42 CI失败、c354 FAILED长测和f9历史验证均保持原件；短测不等同完整硬件性能资格，PR26保持Draft。
