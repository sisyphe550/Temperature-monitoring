# 已存原型证据与后续资格验证

更新：2026-09-18。设计路线已固定，硬件验证结果按构建/环境分别记录。首轮原始目录不改写。

## 已经执行的范围

[2026-09-15报告](validation/2026-09-15-m4-air/validation-report.md)：Mac16,13、M4、15.7.3/24G419、普通用户Release CLI；SMC枚举2147键、HID47服务、NVMe SMART可读、IOPS无Temperature字段。五档各60秒共128645条读取记录，50ms漏采1/1200；其他短时结果见报告。

原型代码版本cc5db3cfbb7ce921153b4fd5be9c6d1ccaa89f3c，8项Swift Testing及ProbeCore55/55覆盖、CLI回归/Release构建。已有Issue1～3修复了CLT测试框架、SMART插件生命周期和观察窗口问题。

2026-09-17源码/旧CSV审计另确认12个Stats CPU键各2279条；Battery三SMC键、TCMz/TCMb只有初始快照。详见[接口审计](research/2026-09-17-handoff-interface-audit.md)。这些是已有数据的复核，不能称本轮新采样。

## 接手agent需要执行的V2

| ID | 动作 | 产物与失败处理 |
|---|---|---|
| V2-01 | 按固定12键读取，普通用户正式App，空闲/有限CPU负载/恢复 | 源集合、单位/编码、实际批跨度、来源分类；缺成员不能缩集合，建Issue |
| V2-02 | Battery单源周期采样、IOPS缺字段分支、SSD内置属性唯一性 | 记录来源选择/属性与不可用原因；不能用NAND替代SMART或平均同名电池 |
| V2-03 | 同集合缓存前后、五档各10min | p50/p95/p99/max、skipped/错误/CPU/内存，按10门槛；不按键数估算提升 |
| V2-04 | 真sleep/wake＋假worker卡住/晚到/崩溃＋换档 | 无旧代样本、句柄与子进程有界、来源换段；记录权限/生命周期 |
| V2-05 | 模拟确定序列贯通内存实时与SQLite，再接真实profile | Raw/EMA均存、峰值、TTL、幂等、背压、缓存、图表缺口 |
| V2-06 | 最终构建/签名下72小时、首次运行/退出/崩溃残留 | 完整数据/资源报告；没有凭证时不声称公证版通过 |

V2对应22的W02～W10，不是开始写任何软件前的无期限研究。首先实现可测试适配与数据链，再以真实App证明当前配置。其他软件读数相近只作对照，不证明物理位置或精度。

## 证据文件约定

新目录`docs/validation/<日期>-<model>-<短SHA>/`保存report.md、environment.json、profile.json、capabilities.json、timing.csv.gz、readings.csv.gz、summary.json、sha256.txt及测试日志。每个结果标pass/fail/unsupported/not-run，不能用空文件或旧日志占位。

report含源码/App/workerSHA、机型/OS build、用户权限、签名/沙箱、编译器/SDK、配置、负载方式/持续时间、测试输入与预期/实际、指标计算口径及限制。压缩原始数据但不删除失败样本状态；敏感标识如序列号不采集。

发现实际接口不支持时按03/06已经定义的行为处理；如果关键CPU配置失败，发行验收失败，不再向用户承诺“再找一个神奇私有API”。删除的逐物理核要求不参与任何V2通过条件。
