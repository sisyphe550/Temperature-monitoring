# Agent实施交接入口

更新：2026-09-18；设计基线v1。目标：接手agent无需读取本对话即可按确定的范围、接口、参数、测试和Git流程完成本地App，并在发布条件具备时完成正式分发。

## 先读的六份资料

1. [现行需求01](01-requirements.md)：132项现行、2项退役。
2. [可行性与复用20](20-feasibility-and-reuse.md)：E1实测、E2上游路线、D项目设计及局限。
3. [实施契约21](21-implementation-contracts.md)：JSON默认值/profile、Swift类型、SQL schema、逐REQ映射。
4. [架构02](02-architecture.md)与[组件08](08-component-design.md)：实时数据路径、worker与模块文件边界。
5. [执行计划22](22-agent-implementation-plan.md)：W00～W11文件、依赖、测试和完成条件。
6. [Git流程11](11-git-github-workflow.md)：PR所在分支、强制门禁、Issue和merge commit。

其他专项03～10/13给出细则；16只登记已决定设计与实际执行依赖。15/18/19和research/validation保存来源与历史，不得用旧记录恢复当前已删除要求。

## 已经决定，不重新开题

| 项目 | 本版执行选择 |
|---|---|
| 硬件 | Apple Silicon Air；首个profile Mac16,13 M4，其他机型不自动套键表 |
| CPU主指标 | Stats映射的12个CPU热区Raw max→EMA，名称“CPU热区最高温度” |
| 删除承诺 | 逐物理核温度/core_id、物理Package、绝对热点、硬件同频刷新、虚构准确度 |
| 附件 | SSD内置NVMe composite；Battery IOPS→TB1T→TB2T→TB0T；不支持显式Unavailable |
| 数据 | 内存Raw/EMA实时；SQLite批量保存Raw/EMA/聚合/趋势；最长72h、仅当前会话 |
| 进程 | Swift主App＋普通用户自有SensorWorker；无root/外部CLI/远端业务服务 |
| 前端 | MacMonitor分组面板＋Stats来源列表＋本项目历史主窗口，按07适配 |
| 验证 | 模拟/契约/CI证明软件行为；正式App在目标Air上的报告证明硬件与发布配置 |

C10用户授权清理不合适内容、补齐完整交接；上述产品收敛和工程参数在授权下形成设计基线，不虚构逐参数用户确认。C11用户明确课程不强制数据库往返，优化内存路径已确定。

## 当前仓库实际状态

- 有独立只读原型、8项原型测试、CI及2026-09-15 Mac16,13/15.7.3/24G419证据。
- 生产Packages/TemperatureCore、App和Xcode工程尚未创建；22里的产品命令用于相应任务完成后执行，不能误报今天已通过。
- 文档在`feature/v0-sensor-validation`／Draft PR #4。W00在该基线完成门禁引导并由维护者合入main后，其他独立功能从最新main起分支。不能仅从旧main开发。
- 既有原型/原始CSV/历史报告不能因产品范围调整而修改；新实测写新目录并记录源码SHA。

## 执行者启动检查

```sh
git status --short
git branch --show-current
git log -3 --oneline
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -typecheck docs/contracts/api-v1.swift
xcode-select -p
swift --version
```

先检查用户改动，不覆盖或reset。CLT可完成文档/核心验证；App/UI阶段需要完整Xcode16.4或通过相同测试的兼容版本。需要上游代码时按manifest的repository＋commit取只读副本，校验hash并保留许可；不要依赖本次审查临时目录，也不要直接运行第三方监控软件替代产品。

## 接手任务与证据

执行22，每个任务结束更新17/acceptance-v1映射对应的验证报告（保留设计任务关系，不把pending批量改成pass）。每个报告至少记录：REQ/TC、源码与App/worker哈希、工具链/profile、环境、输入、预期/实际、结果和日志位置。未执行写未执行；替身测试与实机分列。

遇到真实实现问题：复现→Issue，标blocking则禁止跨阶段/合并；在既定边界内修复并回归。只有发现证据与设计实质冲突才修订契约，不能私自缩CPU成员、丢Raw、改TTL、关闭门禁或恢复逐核目标来减少工作。

## 完成的两种状态

**本地完整App完成：** 132项适用功能及流程按10/22完成，菜单栏/窗口/真实来源/SQLite/故障生命周期可运行，目标Air通过五档与长期验证，输出可复核App与报告；正式签名相关项明确等待外部输入时不能标整项目发布完成。

**正式交付完成：** 上述条件＋Developer ID/公证＋最终包复测＋所有适用发布要求通过，维护者完成PR合并及分发决策。

外部输入清单已限定为完整Xcode、实机、仓库管理员权限和签名/公证凭证。缺凭证不阻塞本地开发；缺对应机型不能扩大兼容声明。文档完整也不能预先保证未来系统私有接口永不变化。
