# SIGPIPE 修复最终独立只读审查（2026-10-03）

## 结论

本次 WorkerClient SIGPIPE 修复与6项新增软件测试未发现阻断问题，可进入该修复提交的证据归档与新提交 CI。审查对象为源提交 `7124dc1644516f471d69930024589342c0ca34c9`，基线为 `f42ec002dc4121b187ff610bdcd55bc8d2da7cd1`。已独立核对4个源码/测试文件的 Git 提交内容、当前工作树、诊断复制件和补丁重建结果，完全一致。

这一结论只覆盖断管写入修复。没有据此宣称 W11 全部验收通过、旧五档长测完整通过、真实睡眠通过，或新提交 CI 已通过。PR 合并仍依赖新提交实际 CI 和现行阻断事项处理。

## 生产实现与错误边界

仓库根目录：`/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring`。

1. `Packages/TemperatureCore/Sources/SensorRuntime/WorkerClient.swift:287` 在新建 stdin pipe 上设置 F_SETNOSIGPIPE，然后才 `process.run()` 和发布 IOHandles。该段没有 await，其他任务不能经已发布 IOHandles 提前关闭这次的新句柄；setter 新增的 fileDescriptor getter 使用时对象仍有效。配置或启动失败关闭全部6个自有端点并原样抛出错误，源码检查通过；未动态穷举所有启动失败组合。
2. `:406` 使用实际描述符配置 helper；fcntl 失败即时读取 errno、返回 POSIXError。单元测试以明确 `-1` 验证 EBADF，不再直接关闭 FileHandle 拥有的内核 fd；没有并发 fd 复用、双重所有权的旧测试构造。
3. `:412` 保留 Foundation 完整请求写入与末尾换行。仅直接 NSPOSIXErrorDomain/EPIPE 或 Foundation 包装的 NSUnderlyingErrorKey/POSIX EPIPE 转为既有 workerExitedUnexpectedly；其他错误原样重抛，没有恢复旧值、补零或改变传输协议。
4. `:190` 的原分支继续先回收 worker，再返回既有 sensorProtocol、underlyingCode=exit。公开接口测试实际覆盖 spawn → submitRequest → writeRequest → typed failure → 回收路径。不会因断管使整个宿主进程默认 SIGPIPE 退出。
5. 两个新增 helper 的可见性为 internal，公开接口、契约、schema、defaults 未变；fixture 位于 ProtocolWorker 独立 target，Release 构建脚本仍只安装 SensorWorker。

Apple 的 [fcntl(2) 官方说明](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2) 规定 F_SETNOSIGPIPE 的非零值抑制无读端 pipe/socket 写入的信号。该实现不修改全局 SIGPIPE 处置。对 pipe，Apple [内核实现](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_descrip.c) 把标志存于描述符关联的 fileglob；dup 别名可能共享该标志，因此精确结论是“保护自有请求 pipe、独立另一个 pipe 不变”，不推广到同一文件对象的所有别名均不变。

## 新增测试与确定性对照

公开测试 `WorkerBrokenPipeIntegrationTests.swift:8` 的 fixture 在关闭 stdin 后才写出 discover catalog，作为 readRaw 前的时序保证；存活上限10秒，正常错误回收立即终止它。整个 discover/read/assertion 执行块遇到可抛错误都 await close。测试先保存真实 child PID，断管后检查 childProcessID=nil，并执行 `kill(pid,0)` 后立即保存 errno，再断言 -1/ESRCH；不会把内部字段清空等同于 OS 进程消失。

| 实际日志 | 独立实读结果 | 证据范围 |
| --- | --- | --- |
| `/tmp/temperature-sigpipe-red-green/public-red.log` | Build 成功1.35s；unexpected signal13 | 完整 f42 原 WorkerClient 与最终同一公开测试/10s fixture；主要 RED |
| `/tmp/temperature-sigpipe-red-green/public-green.log` | 2 tests /1 suite PASS，0.617s | 同公开测试/fixture、新生产源码；typed exit 与 OS 回收；false16轮只是辅助 |
| `/tmp/temperature-sigpipe-red-green/unit-green.log` | 4 tests /1 suite PASS | SIGPIPE 全局处置不变、独立 pipe 标志不变、完整换行帧、无效 fd EBADF、已关闭 FileHandle 抛 Swift error |
| `/tmp/temperature-w11-sigpipe-final-core.log` | 355 tests /57 suites PASS，2.790s | 根 agent 执行的最终全量 Core；包含本次6项测试，不能与过滤套件重复相加 |
| `/tmp/temperature-w11-sigpipe-release-smoke.log` | TEST SUCCEEDED；正式短 UI 1 test PASS，87.162s | 根 agent 执行的本机新 Release 短测；不是600秒五档验收或性能测量 |

已读取原始 coverage JSON，按项目覆盖率筛选/计算函数独立重算 `7120/8002 = 88.98%`，满足≥80%核心生产 Swift 门槛。范围为 TemperatureCore/SensorRuntime；不代表 App UI、C bridge、worker entry 或全部硬件覆盖率。

原始覆盖率文件：`Packages/TemperatureCore/.build/arm64-apple-macosx/debug/codecov/TemperatureCore.json`，SHA256 `cbf55da4780e0e28a74eefe8f92494335ce6b42e349dce5264832a2a14715844`。

## 身份与完整性检查

- `/tmp/temperature-sigpipe-red-green/evidence-manifest.json`：34项、34个唯一路径；每项实际 bytes/SHA256 全部匹配。manifest SHA256 `4a35e0ca82e90459de479d72f08a7b572c1ddb2e4ae3c7215b5eadb9f6d347a9`。
- source-hashes.json 的全部9个源/补丁身份与磁盘一致；完整 f42 基线 WorkerClient 与 Git 对象一致。
- production.patch SHA256 `ec5ee344542b5fe281b7d177761c0e3d47eeac74a33ba7941f29dc27161e6d65`。
- tests.patch SHA256 `93672b6186ad2b552f09a9adbdf5f229b3f1ed4540ebcb21b858df5aae36d242`。
- 生产 WorkerClient SHA256 `3e354752bab5fea10546708a86378114149908500cef60bc93b1c0e9f90a3a29`。
- 本机实际 App 主程序 SHA256 `eae5c0b46776eebfa7a297cae46ac0a0d08ad833fa574230897d2ee54da35651`；实际 worker SHA256 `12356c172d67e4d6161543aa86a6a0616d5133e3121ac91bd0f9cb6e03c78c96`。已读取这两个二进制重新计算；签名/upstream 检查日志通过。新暂存归档的 source-and-build-identity.json 绑定155份源码/构建/测试文件（含新增两测试），已独立逐项与源提交 Git 对象及当前工作树核对一致；最终归档落库与重新 seal 由根 agent 完成。

独立检查 JSON：`/tmp/temperature-worker-sigpipe-independent-check.json`，记录全部核对结果、日志哈希、Git 源提交、coverage 与二进制哈希；failures=[]。

## 保留的失败与结论边界

- 初次 public discovery timeout 是 fixture 设置失败，不能作为 SIGPIPE RED；旧2秒 fixture结果不能替代最终10秒与OS断言的同源对照。
- `green-fd.log` 名称不代表通过：它记录已关闭 FileHandle getter 的 ObjC exception/signal6，属于已淘汰的 per-write 配置原型。baseline-closed-handle.log 则实际证明原 Foundation write 抛可捕获 Swift error；最终 writeRequest 没有新增该 getter。
- 早期直接 raw fd close 构造有并发所有权风险，已从最终测试删除，不作为安全性通过证据。runtime-green.log 是旧2秒版本且与公开/unit覆盖重复，不能作最终总数或最终测试身份。
- f42 CI 一次 Core PASS、一次 signal13 FAILED 表明已有不稳定缺陷；并行测试输出顺序没有证明其唯一触发测试。此次公开确定性 RED/GREEN 证明生产断管缺陷和修复接线，不声称锁定 CI 唯一触发点。
- 基线已有 `drainStderr:319–320` 在异步队列内读取 FileHandle.fileDescriptor，可能存在 close-before-queue-start 的竞态。此次没有复现该独立风险、没有修改该路径，也没有证明已解决。该项作为未解决的源码风险保留，不计为本次新增回归，不声称所有关闭句柄竞态都已消除。
- 原长测 XCTest 失败及后续同会话1000ms duration观察保持原状态；read-batch、first-frame、display/性能指标未测的项目保持未测。用户跳过的是这轮物理睡眠/手动唤醒验证，软件生命周期功能/异常路径仍保留，不扩成整个需求豁免。

本独立审查只读源码、Git 对象、证据和现有二进制；未修改仓库、未启动 GUI、未重跑测试、未访问传感器、未执行真实睡眠。
