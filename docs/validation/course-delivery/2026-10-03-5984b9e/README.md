# 本机课程交付测试报告

日期：2026-10-03；课程 policy：5984b9e；App/Core 实际源码基线：f24f503（生产/构建输入与7124dc1相同）。正式 Release 重建、ad-hoc签名和复用边界通过，App/worker二进制与7124正式验证产物完全一致。当前课程标准见[范围](../../../course-delivery-scope.md)。

## 已验证

- 完整 Core 355项/57组通过，3.196秒；行覆盖7116/8002=88.93%，原分母/80%门槛保留。失败不造值、崩溃/死锁、数据/TTL、取消/退出及可选恢复回归通过。[软件摘要](full-core-summary.json)、[完整日志](full-core.log)、[覆盖](core-coverage.txt)。
- 同一正式 App 会话实际CPU12来源/°C、持续采样、50/100/200/500/1000ms切换、5分钟/1小时历史、关窗标准重开同会话、正常退出/会话清理均有观察。[正式App摘要](formal-app-summary.json)。点选保留相同App二进制的[7124正式证据](../../product-software/W11/2026-10-03-7124dc1/README.md)，本次原生坐标工具失败，不冒称新点选通过。
- 五分钟历史已填充后，50ms窗口35次资源观察：App CPU中位57.2%（41.8–88.2%），worker中位0.7%；App RSS约371–387MiB，worker约39–47MiB。原生切档/历史操作可响应；短测未见明显失控资源异常。RSS随填充、访问树和范围操作变化，不能据此证明绝无泄漏或严格A/B改善。[原生资源](native-resources.jsonl)。

## 测试自身失败与边界

新增长hold驱动的重复picker访问在约192秒发生XCTest AX NoMatch，原执行211.244秒FAILED，保留[日志](automated-attempt-ui.log)与[资源](automated-attempt-resources.jsonl)。App继续真实采样；使用原生UI补完核心操作。原五档8秒自动测试及所有原有效断言原样保留，临时330秒扩展未进入交付代码，不把失败改成绿灯。采样/历史和资源观察仍读取正式App，未以fixture代替。

本轮不验收真实睡眠、72/73h耐久、五档各10分钟、精确skipped/p95/p99/首帧/显示延迟、公证/公开发行或跨机型；72h历史功能和软件TTL仍保留。132项严格资格状态100 accepted /31 pending /1 waived /2 retired不变。当前支持证据仅本机Mac16,13/macOS15.7.3(24G419)。失败不补零/旧值的异常证据来自核心软件回归，不声称本次刻意诱发真实硬件失败。

## App 与启动

可运行App：`/Users/sisyphus/Code/Go/Temperature monitoring/build/course-delivery-20261003/TemperatureMonitor.app`。

```sh
open "/Users/sisyphus/Code/Go/Temperature monitoring/build/course-delivery-20261003/TemperatureMonitor.app"
```

需从源码构建时使用`bash scripts/build-app.sh`及`bash scripts/launch-app.sh`；不要运行DerivedData中缺worker的中间App。“测量更新时间未知”仅表示硬件接口无可验证测量时间戳，应用读取时间与真实温度仍有效。

最终独立审查、同head CI和合并状态由PR回读记录；本报告不提前宣称这些外部步骤通过。完成适用门禁后按用户授权merge commit并保留分支，交付即结束。

## 最终独立审查

本轮唯一一次[最终独立审查](independent-review.md)PASS，未发现本机课程交付blocking问题。审查建议的入口待测措辞已回填，未改变生产/测试代码，无需重复Core或实机测试。31项课程门禁边界测试与35项证据绑定测试通过。最终PR head五CI、零blocking及合并状态仍由实际PR回读；[PR26](https://github.com/sisyphe550/Temperature-monitoring/pull/26)。
