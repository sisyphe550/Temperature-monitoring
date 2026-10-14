# CPU 温度预警交付与测试报告

2026-10-14；生产源码 `958398772918c3cf61cf5eb552bb24759197b755`；本机 Mac16,13 / macOS15.7.3 (24G419)，正式 Release、无fixture、普通用户权限、ad-hoc签名。

## 实现

CPU12合格热区同批Raw最大值持续达到可配置阈值才触发。默认90°C/5秒；降至85°C并持续10秒恢复。主图仍显示EMA。状态、来源故障和提交边界共用核心Snapshot；缺测/过期不补零、不补旧样本、不当成温度恢复。事件保留本会话最近50条。四项设置保存到UserDefaults。

主界面/弹窗/菜单共享预警状态；设置页可修改开关、阈值、持续时间及可选系统通知。通知去重和60秒冷却，不因授权失败停止采样。没有增加SQLite表、root/helper、SMC写入或外部采集CLI。

## 实际验证

| 项目 | 结果 |
|---|---|
| 完整Core | 413项/62组，0失败，23.854秒 |
| 既有覆盖率门槛 | 7426/8327=89.18%，>=80%；分母未改变 |
| 探针保护 | 8项通过，ProbeCore 55/55覆盖；不替代产品/实机 |
| 文档、API、证据门禁 | 文档检查、Swift6 API typecheck、binder44、course36、课程5criterion通过 |
| 独立审查 | 一次完整审查及其修复复核PASS；#54/55/56已修复，无剩余P1/P2 |
| 正式App | 真实CPU12/°C、35°C持续5秒触发与Raw峰值、五档短切换、历史CPU/SSD比较、规则变更原因、无效输入、关窗重开、配置跨进程恢复、正常退出均通过 |
| 系统通知 | 授权允许；UserNotifications Added request hasError0。API接受已验证，横幅/真实点击未观察 |

原失败完整回归411项/4issues及红测保留。#54修复暂停期间迟到通知；#55阻止旧无预警报告只改标签冒充预警证据；#56解除Snapshot等待held提交并在Receipt后按当前时钟重查TTL，避免复活/制造过期事件。有效断言、原异常参数和覆盖分母保留。

XCTest编译后在 enabling automation mode 超时，业务断言未运行，记录为环境限制；正式App的UI使用nativeCUA实际操作补验，没有把XCTest标为通过或删除有效断言。

短测可持续采样且界面响应。第一会话App约112–175MB RSS/Worker约8–11MB，第二会话约157MB/9.5MB；启动填充有增长，短测不证明长时曲线。原五分钟资源历史证据保留，新完整软件回归含有界容量/清理/生命周期。两次正常退出后App和Worker均不存在。

## 启动与演示

已测试的App副本：`/Users/sisyphus/Code/Go/Temperature monitoring/build/course-delivery-20261014/TemperatureMonitor.app`；同目录`启动说明.md`。复制后App与Worker SHA与正式短测一致。

```sh
open "/Users/sisyphus/Code/Go/Temperature monitoring/build/course-delivery-20261014/TemperatureMonitor.app"
```

设置 → CPU温度预警，修改后点击应用。演示可临时设置35°C/5秒；看完恢复90°C/5秒。默认系统通知关闭。提醒阈值不是硬件安全限值。改变规则结束旧事件会显示“规则变更”，不代表实际温度下降。

从源码重建：`bash scripts/build-app.sh`，再运行`bash scripts/launch-app.sh`。原用户工作区与旧交付App保留；本轮源码位于feature/cpu-warning独立worktree。

## 验收边界

本机课程交付5criterion及新REQ-125通过，不宣称全部132项正式硬件资格。真实自然降温恢复由确定性软件测试覆盖，本次未观察自然恢复；通知横幅/真实点击未观察，软件路由已测。菜单符号/弹窗共享状态经源码审查和软件测试，不把主窗口AX当成独立菜单栏显示证据。

本轮不验收真实系统睡眠、72小时耐久、五档各10分钟、精确p95/p99/skipped/首帧/显示延迟、公证、公开发行和跨机型认证。历史研究和失败证据没有回写。

Git执行适用五项同head CI、零blocking、独立审查后merge commit，保留开发分支；最终PR与合并状态以远端实际检查及本次交付消息为准。

## 证据

- [完整软件报告](software.json)与[软件证据说明](README.md)。
- [正式App短测报告](formal-app-short.json)、[界面观察记录](logs/formal-native-observations.json)、[系统通知原始日志](logs/formal-notification-system.log)。
- [独立审查原文](independent-review-original.md)、[结构化审查](independent-review.json)。
- [构建日志](logs/formal-release-build.log)、[最终Core日志](logs/final-full-core.log)、[覆盖原始结果](logs/final-core-coverage.log)。
