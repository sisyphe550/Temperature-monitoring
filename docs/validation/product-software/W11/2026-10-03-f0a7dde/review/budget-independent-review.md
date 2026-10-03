# Optional Budget 与共享测试时钟独立只读审查（2026-10-03）

## 结论与范围

基于44070基线的最终三文件候选未发现阻断问题：Budget用例修正、Generation原clock实现提取、新增TestSupport/OptionalPhaseClock。当前工作树三文件逐字节等于候选；全部补丁hunk已按44070 Git对象在内存重建吻合。没有修改生产代码或产品需求。

本结论覆盖Budget/Generation/helper候选，Wake与SleepAdmissionRace补丁尚须单独审查；整组最新全量Core/coverage、源提交绑定和新head CI由根agent后续完成。原44070 CI FAIL不能回写为通过。

## 等待机制与回归目标

1. 500ms冻结阶段，以550ms重试和700ms发布等待分别识别采样/publisher task；后续按task身份筛选未来sleep，只接受deadline>now，排除同截止的其它任务以及已经被唤醒的旧sleep。
2. 初始550/650/850重试后等待同SAM的1000ms sleep，保证失败处理、隔离与随后CPU回调完整返回；不再依赖25ms虚拟步进/5ms墙钟轮询或40ms猜测callback结束。
3. 三轮恢复失败在60.85/120.85/180.85秒精确推进，读次数恰好5/6/7。总提交计数仅在真实store.commitBatch成功后增长，但计数包含所有批次，不等于SSD专属失败Receipt计数；同SAM新sleep才是整个失败回调与预算状态完成的流程边界。
4. 初始SQL确认SSD gap=1、raw=0；恢复失败仍raw=0，不用错误事实补温度样本。CPU重连后新代CPU真实raw>0、SSD raw=0，跨普通SSD deadline与额外61秒恢复窗口后仍optional7/newOptional0；新代SSD快照仍不可用。
5. Generation仅改clock类型名和提取类，原来源换代、真实commit/SQL1/2/3、前两次不可用及第三次恢复的语义未变。共享helper仍在测试target内，没有修改基础TestClock或生产clock/API。
6. 2ms/125ms轮询只决定检查条件频率，不决定虚拟推进速率；保持4秒/2秒有界等待，超时带phase/elapsed/task-labelled sleeps和外层reads/commits/catalog/snapshot上下文，不宣称任意系统饥饿下均通过。

## 独立实读证据

| 最终证据 | 实际结果 | 说明 |
| --- | --- | --- |
| ci-44070-failed.log | Budget FAIL，Cocoa256，5.244s；Generation两参数PASS | 没有原失败阶段信息，不能唯一定位helper阶段 |
| model-red.log | 1test/2cases FAIL；125ms在initial-unavailable、虚拟775ms、optional3超时 | 第4次850ms重试仍待推进；受控软件模型，不是硬件性能压力 |
| negative-control-red.log | 1test/2cases FAIL，12issues，2.318s | 仅复制源码移除CPU重连对optionalStoppedKinds的remove/continue guard；两参数变为optional10/newOptional3，预算重启被抓到 |
| candidate-green.log | 2tests/4cases PASS，2.429s | 原生产复制件恢复后最终Budget+提取后Generation，2/125均通过；预算optional7/newOptional0 |

负控与最终GREEN使用同一最终测试源（包括gap1和最终unavailable断言）。非throwing #expect失败后仍可打印BUDGET_PHASE_COMPLETE，不能用流程marker宣称PASS。model-compile-first和较早candidate/negative日志保留，编译失败及旧断言版本不替代最终证据。

## 完整性与源码身份

- 基线：`44070d6ea5d8dbe3e64a1c0ddc206f5bd2597f97`。
- tests.patch SHA256 `65629685d39071778682334da0b61fe20e0d4bddb9bf5ed6f8f320cde574cbe1`。
- Budget候选 SHA256 `74783e93c50a2c4345575f72a406f8a5200d411d411f988a3e796d07ec2d43a2`。
- 提取后Generation SHA256 `712e20cd493db0ca63974b40bd02654d9cc53124ff364ed1d28350e07d943ee5`。
- OptionalPhaseClock SHA256 `51c8249850b9a41dabcf14c703c5244372cb3b7e3843eccdbb9e511103dbce22`。
- evidence-manifest.json 22项/22个唯一路径，逐项bytes/SHA256通过；SHA256 `e83d0050154a552bf960d76a94c803911928783b1d02f40846abb9c71997eb20`。source-hashes全部9项一致。
- 独立核对最终复制包Sources与Package.swift共66文件，与44070 Git生产对象完全相同；负控已恢复。当前App/Package Sources与Package.swift/Xcode工程/build-app输入相对7124差异为空。

机器核对：`/tmp/temperature-final-budget-independent-check.json`，failures=[]。本审查未运行测试、GUI或传感器，未修改仓库。

## 保留边界

模型精确证明initial-unavailable的推进耦合，不证明真实44070 CI唯一阶段。保留原正式App7124测试身份；本次测试修正不等于新实机执行，不替代五档长测失败/独立duration观察，未测性能项目仍未测，物理睡眠本轮跳过不扩大成软件生命周期需求豁免。
