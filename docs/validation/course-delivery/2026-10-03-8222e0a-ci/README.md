# Core CI 测试编排调整

日期：2026-10-03；验证 checkout：8222e0a。生产和测试源码与f24f503一致，本次只调整CI编排及文档，不改App、测试断言或覆盖分母。

## 观察与处理

同一8222提交的push Core任务37127190195通过，pull_request任务37127192657在测试开始约1秒后停止输出，多组尚未结束。等待超过12分钟后人工取消以取得[原日志](cancelled-ci.log)。没有失败断言、崩溃或确定根因，不将这次调整称为产品死锁修复，也不把CANCELLED改写为PASS。对应[Issue #53](https://github.com/sisyphe550/Temperature-monitoring/issues/53)。

显式使用`swift test --package-path Packages/TemperatureCore --no-parallel --enable-code-coverage`关闭独立用例并行，保留每个用例内部的Task/async let、查询竞争、采样中断和并发退出断言。CI任务设置10分钟超时，超时仍失败。355个测试、所有有效断言及核心≥80%覆盖门槛不变。

## 本机完整核心回归

355项/57组通过，23.980秒；7109/8002=88.84%。日志逐行检查得到同时活动的独立测试和suite最大数均为1，所有启动记录均有对应通过记录，确认显式串行编排生效。[完整日志](serial-core.log)、[覆盖](serial-coverage.txt)、[摘要](serial-summary.json)。与先前88.93%相比是本次执行覆盖差异，未删代码、用例或调整分母，仍高于80%。

正式App、生产源码及有效UI测试不变；[本机正式App短测和唯一最终独立审查](../2026-10-03-5984b9e/README.md)继续适用。本次文档和CI命令修改不触发重复实机长测，不添加模型复现、负控或多轮审查。

先确认最终head的Core CI与其他独立门禁通过，再关闭#53触发blocking检查；[PR #26](https://github.com/sisyphe550/Temperature-monitoring/pull/26)的五项required CI全部通过且零blocking后才合并。本记录不预先声明外部CI或合并完成；合并后结果附在交付App旁的交付记录。
