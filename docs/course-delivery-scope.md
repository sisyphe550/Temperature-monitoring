# 本机课程交付范围

更新：2026-10-03。当前目标：在用户自己的MacBook Air完成课程演示、交付可运行ad-hoc Release App并合并本轮PR。实施契约仍v1族revision3，公开API、默认值、profile、schema与50项任务/DAG不变。本轮最小收尾进行中，以下条件不是未来通过或已合并声明。

## 最新直接授权（要点转述）

用户将目标收敛为本机课程演示，授权继续完成当前工作并最终merge交付。优先确认核心CPU温度监测和日常操作可用，不为个人单机用途继续严格132项全资格、五档各10分钟、物理睡眠/唤醒、72/73小时耐久、公证/公开发行或跨机认证，也不补精确skipped、读批p95/p99、首帧及显示延迟指标。本轮采用优化后的最小收尾：必要软件回归及全Core、一次正式App同会话短测和资源/响应观察、一次最终独立审查、同head五CI/零真实blocking后合并，完成即停。

这项最新授权覆盖此前“完成当前工作后暂停”以及“保留五档各10分钟/真实睡眠验证”的执行要求。此前失败、partial、skipped-by-user和not_measured证据仍保持原记录；收缩验收不等于它们通过，不重写历史validation/research。

## 功能与验收分类

机器政策为[course-delivery-v1.json](contracts/course-delivery-v1.json)，与[acceptance-v1](contracts/acceptance-v1.json)旧逐REQ矩阵分开。

| 分类 | 当前解释 |
|---|---|
| core | 本机核心温度链、来源/单位、失败不造值、必要数据与故障完整性；课程门槛必须满足 |
| auxiliary | 课程演示相关视觉、菜单/Popover、可选设备状态等辅助功能；历史和正常退出仍属于 core；不因可选硬件缺失省略探测/错误状态 |
| optional | 扩展资格、长测、物理sleep、公开发行/跨机及精确性能验证；本轮不阻塞本机目标，未测保持未测 |
| retired | REQ-012/114及对应逐物理核/Package保证；禁止恢复或改为PASS |

仍保留CPU固定12热区完整同批Raw max→EMA、°C与来源身份、Raw/EMA持久化、内存实时路径、有界与幂等、Gap/分层历史最长72小时、会话清理、日志/错误边界、许可及普通用户无写SMC/无Release fixture。**取消72/73h实机长跑没有删除72h历史功能**；软件TTL、缺口与睡眠生命周期回归继续适用。

## 五个课程criterion

| ID | 必需证据与判定边界 |
|---|---|
| COURSE-CPU | 正式Release本机真实CPU12、来源/单位、Raw max→EMA可见；结合必要软件异常回归证明失败不补0/旧值。成功短测未触发真实故障时不声称实机故障验证 |
| COURSE-FUNCTIONS | 正式启动、五档短切换、来源选择、历史范围/点选、关窗继续采样、标准重开同会话、正常退出及清理；菜单/Popover按本机实际操作记录 |
| COURSE-RESOURCES | 同一次短测记录App与Worker CPU/RSS、图表与操作响应，无明显异常；记录窗口/档位/时间、结果与限制，不据短测声称无泄漏或跨机达标 |
| COURSE-REGRESSIONS | 必要关键失败、数据完整性、断管/回收、可选恢复、历史/TTL、软件sleep/wake与退出清理回归保留；不新增物理睡眠或强杀真实App |
| COURSE-CORE | 当前完整产品Core通过、核心行覆盖≥80%，含异常路径且分母不缩减；保存原日志与覆盖报告 |

每条criterion绑定明确source_commit、App/Worker身份（适用时）、环境、输入/实际、结果和证据。课程五条不能由声明、整组TC绿灯或旧产品报告替代；旧逐REQ100accepted/31pending/1waived/2retired保留，不批量PASS。

## 最小收尾与工作包衔接

1. W09：使用当前源码构建并ad-hoc签名的正式App，同一会话完成五档短切换；首50ms填充最近5分钟图，其余档短切换。自动短测不稳定时保留失败记录，使用原生界面补验核心操作；已有有效断言保留。观察启动、来源/单位、历史/点选、菜单/Popover、关窗/标准重开和正常退出，同时侧录owned App及child Worker CPU/RSS；不加压力负载。不把请求档位等同硬件测量刷新率，也不把有图等同精确2000点。
2. W10：以本机ad-hoc App、源码与二进制SHA/签名/环境记录作为当前交付；Developer ID、公证ZIP、Gatekeeper公开发行与更多机型是可选路线。
3. W11：完成本轮全Core/必要回归及五criterion证据绑定，文档检查、一次最终独立审查；随后回读同PR head五CI、零真实blocking与仓库保护，再按用户授权push/调整PR状态/merge commit，保留开发分支。外部流程见[11](11-git-github-workflow.md)。五criterion不要求CI自身未来状态，避免自证循环。
4. 合并后回读merge commit两个parent与远端分支，给出可启动本机App路径、实际结果和边界，完成即停；没有新用户授权不扩大到长测、物理sleep、多轮审查、负控、压力负载或公开发布。

当前构建入口：`bash scripts/build-app.sh`，输出`build/TemperatureMonitor.app`；`bash scripts/launch-app.sh`执行标准LaunchServices启动。最终交付目录/哈希与实际结果由本轮delivery补录，不提前声明通过。

## 门禁与历史事实

```sh
python3 scripts/validate-handoff.py
python3 scripts/validate-handoff.py --product-acceptance
python3 scripts/validate-handoff.py --strict-product-acceptance
```

普通检查验证文档/绑定一致；course-local只判当前五criterion；strict模式保留旧全132项扩展资格，旧pending存在时拒绝。文档结构通过不证明实测真实性，最终审查要核原证据。五项required CI和真实blocking按11由外部流程检查，不能通过删除真实bug标签绕过。

[7124正式App归档](validation/product-software/W11/2026-10-03-7124dc1/README.md)、[f0软件归档](validation/product-software/W11/2026-10-03-f0a7dde/README.md)、[c354原FAILED长测](validation/product-software/W11/2026-10-03-c354b03/README.md)各自保留源码与产物身份。Issue #49既有记录支持CPU开销改善，未证明RSS增长解决；本轮是否仍有可复现异常由一次最终资源/响应观察判定，不能把可选精确性能未测虚称通过或用它强迫继续全资格实验。
