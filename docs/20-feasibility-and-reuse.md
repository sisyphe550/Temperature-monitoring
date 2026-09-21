# 全项目可行性、来源与设计覆盖

更新：2026-09-21；实施契约v1族修订2交接审计。**现行需求均有具体实施路线；不等于所有功能已实测，也不等于每个细节都能从上游直接复制。** 本表区分三类依据：E1本机证据、E2开源/官方实现路线、D本项目确定的组合设计。

## 接口与受物理限制的要求

| 现行能力/限制 | 依据 | 采用方案 | 文档/验收任务 |
|---|---|---|---|
| CPU来源读取 | E1 12键各2279条；E2 Stats、macmon | 固定12键只读SMC，缓存元数据 | 03、硬件审计；W02/W09 |
| CPU主温度 | E1成员可读；D数学计算 | 固定成员Raw max→EMA，名称CPU热区最高温度 | 01/05；W04/W05 |
| SSD | E1 SMART600次；E2 SDK、Stats | 唯一内置NVMe composite；未知身份不可用 | 03；W02/W09 |
| 电池 | E1三SMC键初值；E2 Stats/MacMonitor/IOPS SDK | IOPS→TB1T→TB2T→TB0T，启动固定单源 | 03；W02/W09 |
| HID温度 | E1事件可读；E2 macmon | 诊断适配；无本机CPU服务则不作兜底 | 03；W02 |
| 逐物理核/Package/绝对热点 | 没有充分接口语义证据 | 删除逐核与物理Package承诺；以明确定义派生指标替换主值 | 01/15；TC-DOCS |
| 50ms与刷新率/精度 | E1短时调用计时；无源刷新/校准证据 | 保留请求档位，取消新硬件测量/±0.1°C等不成立推断 | 03/10；W05/W09 |
| 同步接口阻塞 | E2同步IOKit API；D隔离 | 普通用户自有worker、有限队列与进程回收，不虚构取消API | 02/06/08；W02/W06 |

所有具体接口入口、所有权、单位、冲突与精确证据见[硬件审计](research/2026-09-17-handoff-interface-audit.md)。尚缺实机验证已经变为W09的执行步骤与明确通过/失败结果，不能作为没有方案的笼统TODO。

## 软件其余部分

| 部分 | 可复用依据 | 本项目必须实现的部分 | 权威设计 |
|---|---|---|---|
| 原生菜单栏/分组面板/来源列表 | E2 MacMonitor AppDelegate/PopoverView、Stats Popup/Widget、SwiftTempBar数字排版 | 接入EMA、状态、历史主窗口，移除CPU占用率网格及无关功能 | 07、UI来源清单 |
| 采集分层/缓存/只读桥接 | E2 macmon、Stats；已有原型 | 版本化registry、固定成员、调度/退避/超时协议 | 02/03/08 |
| EMA/趋势/Raw峰值 | D标准数学公式与确定验收向量 | 实际dt、tau、缺口、样本加权、窗口水位 | 05/10；不是上游整套实现 |
| SQLite/TTL/持久化 | E2 SQLite事务、WAL、约束文档；D项目schema | 有界交付、幂等、分层保留、当前会话清理 | 04、schema-v1.sql |
| 并发/隔离/窗口生命周期 | E2 Swift/AppKit/Foundation能力 | actor与专用队列边界、worker协议、单实例锁、退出预算 | 02/08/13 |
| 故障/报告/恢复 | E2上游错误读取路径；D用户原定重试规则 | 关键/可选矩阵、稳定错误码、报告轮转和Fatal时序 | 06/13 |
| 测试/CI/Git | 现有Swift Testing、GitHub Actions；E2 GitHub规则API | 产品覆盖、阻塞Issue检查、实机矩阵与评审证据 | 10/11/22 |
| 打包/签名/公证 | E2 Apple Developer官方工具 | worker嵌入、构建脚本、最终配置复测、ZIP与校验清单 | 09/13/22 |

不能说这些参考软件已经替本项目实现了Raw/EMA双写、72小时会话历史、教学验收或全部故障策略；对应D设计已经给出接口、参数、DDL和测试向量，可直接开发。

## 复用执行边界

| 范围 | 允许方式 | 固定门禁 |
|---|---|---|
| macmon现有原型桥接 | `modified`，只读SMC/HID ABI | third-party-v1登记固定commit/路径/许可hash/notice；Release不得出现写SMC |
| Stats、MacMonitor、SwiftTempBar、mactop MIT文件 | method-only，或未来逐文件copied/modified | 实际复制前更新third-party-v1与ThirdPartyNotices；保留版权、许可和修改说明 |
| MacFanControl R04、Philip Turner R07 | method-only | 当前许可材料不足，禁止复制或近似改写源码 |
| 项目算法、持久化、生命周期、展示状态 | 本项目实现 | 按21的ReadingOutcome、资格化来源、SessionPersistence、Lease/Receipt、PresentationState实现，不归因于上游 |

source/UI manifest记录研究输入，third-party-v1记录实际导入；二者均不能替代正式App验证。`TC-UPSTREAM-BOUNDARY`验证失败不补旧值/0°C、名称与数量不产生物理语义、同名不同registryID不合并、Release无root/helper/风扇写入/fixture，以及所有copied/modified文件均有登记。

## 仍依赖外部环境的完成条件

- 完整Xcode：本机目前只有CLT。W01可完成核心包；W07/W08的原生App/UI测试需要Xcode。
- 真实目标Air：现有机型可以做W09；其他Air只有取得实机报告才新增支持，不影响首个profile实现。
- Developer ID/公证凭证：W10正式分发需要维护者提供；未提供时可完成本地App，不能伪造公证状态。
- 仓库管理员权限：W00/W11启用强制门禁需要权限；无权限仍可形成完整PR，但不能声称已受保护或擅自合并。

这些是明确执行依赖，不是尚未选择的架构。当前没有残留“要先发明逐核温度API”这样的设计前置条件。C11已确认无需数据库强制往返，实时内存路线生效。

因此，CPU温度核心目标具有已跑通的原型读取路径和明确产品实现契约；UI、存储、加工、故障及发布也均有可执行设计。尚未完成的是生产实现与正式App实机/72小时/签名验收，不能表述为“只需照抄上游即可完成”。
