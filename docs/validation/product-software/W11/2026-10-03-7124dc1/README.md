# 7124dc1 Worker断管修复与最终短测

受测生产源码：`7124dc1644516f471d69930024589342c0ca34c9`；155份生产、构建及测试源与提交对象逐字节匹配。前次f42 CI一次Core通过、另一次signal13失败，原失败保留，未按重跑覆盖。

- 原生产WorkerClient通过公共discoverRaw/readRaw路径复现SIGPIPE；同一最终10秒有界断管fixture和用例，原源码RED(signal13)，候选GREEN。仅新建请求管道在spawn前设置F_SETNOSIGPIPE，EPIPE映射到既有协议错误及worker回收，未改全局信号策略。测试包含实际子PID已不存在(ESRCH)、正常帧、无效descriptor和已关闭FileHandle。生产API、schema、默认值不变。见[RED/GREEN报告](sigpipe/report.md)。该报告中早期超时、沙箱失败及失效的per-write getter试验单列，不能作为当前候选通过证据。
- 完整Core：355 tests / 57 suites，0失败；核心7120/8002=88.98%。[软件结果](full-core-summary.json)。
- Release构建、签名及上游边界通过。App SHA256=`eae5c0b46776eebfa7a297cae46ac0a0d08ad833fa574230897d2ee54da35651`；worker=`12356c172d67e4d6161543aa86a6a0616d5133e3121ac91bd0f9cb6e03c78c96`。见[源码与产物身份](source-and-build-identity.json)。
- 正式App短测1项PASS，87.162秒，14份自有附件：真实CPU12/可选项、五档各8秒、历史范围/点选、同会话重开、正常退出与会话清理；退出后本轮App/worker不存在。见[短测](short-ui/build-and-run-identity.json)。短测不替代五档600秒性能资格。
- [独立审查](independent-review.md)只批准本次软件修复及对应证据边界，不代表整个W11或当前GitHub CI/合并通过。

用户已明确跳过本轮物理休眠，不再执行；功能和软件生命周期回归保留。c354历史duration补证、原FAILED长测及f9历史回归保持原件，不继承为新产物完整资格。精确scheduler skipped、读批p95/p99、首帧/显示p95仍未测；Worker RSS对照未完成，不宣称泄漏或改善。100项接受/31项待验收/1项豁免/2项退役未因本次断管修复批量变化。PR26保持Draft，W11未完整完成。

API依据：[Apple XNU fcntl手册](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2)。仅调用平台API，没有复制XNU实现；独立管道的标志及全局SIGPIPE策略未改变，不声称同一管道的dup别名拥有独立标志。
