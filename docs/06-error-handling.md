# 故障、重试、能力缺失与退出

更新：2026-09-17；C10基线v1。参数保留用户原定重试次数；CPU主指标为必需，SSD/Battery为能力可选。可选不等于省略实现，必须完成检测、读取适配与明确状态。

## 判定顺序

1. 先区分能力不支持、权限不足、未映射与运行读取失败。未配置profile或无法建立必需CPU定义时停止监测并报告；不猜测新机型。
2. 可选SSD/Battery的缺失/权限不足/单项读取耗尽只使该项Unavailable，CPU与历史继续。底层同一个worker损坏导致CPU也失效时按CPU关键能力处理。
3. 不能按固定成员生成CPU主指标，经过本轮重试仍失败，则Fatal；不需要等所有物理来源同时失败。
4. 存储、加工、必需UI链路的耗尽或结构性故障Fatal。非法能力报告、相同ID不同内容等不应盲目重试。

## 重试所有权

| 操作 | 额外尝试 | 依次等待 | 唯一所有者 |
|---|---:|---|---|
| 一轮传感器读取失败/无效值 | 3 | 50/100/200ms | SamplingService；CPU重读整固定集合，可选项只重读该项 |
| SQLite暂时操作失败 | 5 | 100/250/500/1000/2000ms | StorageWriter；busy_timeout=0 |
| 加工服务暂时执行失败 | 3 | 50/100/200ms | MonitorEngine；纯算法逻辑错误立即Fatal |
| UI历史查询暂时失败 | 3 | 100/250/500ms | HistoryQuery；此路径不再叠加SQLite的5次重试 |

次数均不含首次尝试。等待从上次尝试结束计；成功立即终止。全部读数均为真实新读取，失败不补值。读取1秒截止与重试等待分别计时；不能宣传总共350ms内必然恢复。UI读取耗尽用UI-DATA-001；非UI业务读库耗尽用DB-READ-004，避免嵌套放大。

普通调度与重试共用worker串行通道。退避期间其他任务可以按CPU→SSD→Battery优先级执行，但不启动第二条同来源重试链；旧周期机会计skipped而不积压补采。持续失败可选项每60秒单次恢复探测，最多3轮；成功需连续3次本周期读数有效才恢复显示并开始新定义/段。3轮都失败后本会话停探测；睡眠唤醒可重新发现。永久unsupported/mappingUnknown仅唤醒或用户重启后再发现。

## 错误码与严重性

| 错误码 | 固定语义 | 处理 |
|---|---|---|
| APP-INIT-001 | 应用/会话初始化失败 | Fatal |
| APP-PLATFORM-002 | 非Air/未配置机型/系统过低 | 停止监测并显示原因后退出 |
| SENSOR-DISCOVER-001 | 必需CPU来源发现不足 | Fatal；可选缺失用能力状态 |
| SENSOR-READ-002 | 读取重试耗尽 | CPU必需Fatal；可选degraded |
| SENSOR-VALUE-003 | 连续无效编码或温度值 | 耗尽前可作为底层原因；最终读取耗尽保留SENSOR-READ-002 |
| SENSOR-TAG-004 | 来源/定义身份无法建立或冲突 | 必需Fatal；未知可选标mappingUnknown |
| SENSOR-TIMEOUT-005 | 驱动请求超过截止时间 | 回收worker，按读取预算重试；旧generation丢弃 |
| SENSOR-PROTOCOL-006 | 帧超限、格式/版本错误、响应ID冲突 | 回收worker；结构性Fatal |
| DB-OPEN-001 | SQLite打开失败 | BUSY/LOCKED按DB预算；否则Fatal |
| DB-INIT-002 | Schema创建失败 | Fatal |
| DB-WRITE-003 | 写入重试耗尽 | Fatal |
| DB-READ-004 | 非UI业务读取重试耗尽 | Fatal |
| DB-CLEAN-005 | 清理超过120秒宽限仍无法完成 | Fatal |
| DB-CORRUPT-006 | 当前库完整性损坏 | Fatal，不重建掩盖 |
| DB-SCHEMA-007 | 当前库schema不兼容 | Fatal |
| DB-BACKPRESSURE-008 | 最老待写批次超过10秒 | Fatal |
| DB-CAPACITY-009 | 容量硬限或磁盘不足 | Fatal |
| DB-INTEGRITY-010 | 相同ID不同载荷 | Fatal |
| PROC-VALIDATE-001 | 校验器自身故障 | Fatal；正常拒绝无效读数不是此错误 |
| PROC-EMA-002 / PROC-AGG-003 / PROC-TREND-004 | 对应加工失败 | 暂时失败按预算，否则Fatal |
| UI-DATA-001 | UI查询预算耗尽 | Fatal |
| UI-RENDER-002 | 展示模型不变量无法满足 | Fatal；无法捕获的原生崩溃走系统诊断 |

代码不因重试/严重性改变而重编号。能力状态与错误码分开：Unsupported、PermissionDenied、MappingUnknown无需伪造测量值，也不靠反复重启保证恢复。

## 缓存与Fatal

第一次失败立即给旧值标“暂未更新”；距最后有效点超过`max(3×当前周期,2s)`后隐藏数值，只显示过期占位。这里是应用观测年龄，与硬件更新时间未知是不同状态。

Fatal：停止新调度 → 固定原始错误 → 独立日志/JSON报告 → MainActor错误窗口/系统对话框展示错误码和“重启应用”说明。提供“打开报告”和“退出”；用户退出或可见后30秒倒计时结束进入停止流程。渲染不可用则用NSAlert兜底；再失败用OSLog/stderr并结束，不递归触发新的Fatal。

退出收尾预算5秒：完成或终结在途读取、交付已接纳批次、关闭句柄与DB、删除会话。不能完成的步骤记录状态并结束应用，由下次启动清理；不承诺断电、强杀或内核不可回收时立即清理。细节见[13](13-operations-distribution.md)。

## 诊断内容

JSON包括error_code、severity、timestamp、component、operation、retry_count、sourceID（适用时）、sessionID、appVersion、model、osVersion/build、provider、mappingVersion、definitionVersion、underlyingError与未完成收尾步骤。日志独立于监控库，不写机器序列号、不自动上传。报告写入失败保留原始错误，通过OSLog/stderr和窗口内可复制文本兜底。
