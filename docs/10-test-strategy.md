# 测试、验收向量与证据标准

更新：2026-09-18；C10基线v1。当前仅原型及文档契约检查有执行证据；下列产品测试供接手agent实施，不能标成已通过。

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

## 产品覆盖率与命令

分母包含`Packages/TemperatureCore/Sources/TemperatureCore/`与`Sources/SensorRuntime/`所有自有Swift业务代码：适配选择、协议/调度、校验、算法、存储、错误、生命周期。仅排除第三方未修改代码、C桥接薄ABI与App纯视图；C桥接由ABI/解码/资源生命周期及实机检查单独验收。不得排除难测的错误分支降低分母。

W01～W08实现以下命令后，CI核心行覆盖率至少80%，并保留LCOV/llvm-cov报告。关键向量与异常测试独立于覆盖率数字：

```sh
swift test --package-path Packages/TemperatureCore --enable-code-coverage
python3 scripts/check-core-coverage.py
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
python3 scripts/validate-handoff.py
```

上述产品文件尚待22任务创建，命令是实施后的验收入口。现有可立即执行的原型检查为`swift test --package-path prototypes/sensor-probe --enable-code-coverage`、`python3 scripts/check-probe-coverage.py`、`swift build --package-path prototypes/sensor-probe -c release`及`python3 scripts/test-probe-cli.py`。

原型8测试与55/55 ProbeCore覆盖不等于产品80%门禁。正式UI黑盒不能只测ViewModel；托管macOS CI不证明Air传感器。

## 硬件验收口径

W09首先确认身份、单位、固定集合，再以普通用户的正式App构建测试五档各10分钟，记录实际间隔、批耗时、skipped、失败、CPU/内存与来源新鲜度。正常空闲目标：skipped≤1%，读批p95≤所选周期，p99≤2×周期，首帧/显示延迟p95≤500ms；这些是v1验收门槛，未测通过。超标不删五档，登记缺陷并优化；受控负载段单列，仍要求界面响应、有界且缺口如实记录。

CPU/内存/能耗暂无百分比硬指标，资源有界上限按21执行；每个结果保存测量口径（CPU是否单核百分比）。72小时真实测试用默认200ms、记录首末小时与每小时资源，不能用几分钟或虚拟时钟冒充。受控CPU负载只用普通用户、限定时长，不改风扇、不禁用系统保护；出现系统严重热状态就停止负载并如实记录。

每次报告记录源码SHA、App/worker哈希、profile版本、机型/OS build、权限/签名、用例、输入、预期/实际、状态及原始证据。发生可复现缺陷按11建Issue并回归。现有2026-09-15证据原样保存；新增测试另建按日期/提交命名目录。
