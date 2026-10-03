# WorkerClient SIGPIPE 独立诊断与候选验证（2026-10-03）

## 结论与证据范围

1. 已确定性复现产品传输缺陷：正常 SIGPIPE 默认处置下，worker 的请求管道没有读端时，生产 `WorkerClient` 写请求会直接终止父进程（signal 13）。此条件可以由 worker 意外退出产生，不局限于测试的无效 origin 注入。
2. CI 原日志 `/tmp/temperature-f42-core-ci-failed.log:955` 记录 signal 13。并行测试以及 stdout/stderr 缓冲/到达时序不能定位唯一触发测试，**没有证明 CI 必然是 `malformedOrFutureParentOriginRejectsWorkerStartup` 导致**。该测试确实让真实 worker 在 `WorkerClock` 初始化时拒绝启动，是可证伪的候选触发器。
3. 最终公开接口测试/软件 fixture 完全相同，完整 f42 原生产源码 RED signal13 → 候选源码 GREEN，证明修复接入真实 spawn/submitRequest/writeRequest 路径。其 GREEN 还确认既有 `sensorProtocol`/`underlyingCode=exit`、`childProcessID=nil` 和实际 child PID 的 `kill(pid,0)=-1/ESRCH`。
4. 本子任务仅修改 `/tmp`，没有启动 GUI 或采集传感器，没有重启 Worker RSS A/B。根 agent 集成、全量 Core、正式 App 与 CI 的状态由根 agent 单独验证。

## 源码映射

基线提交 `f42ec002dc4121b187ff610bdcd55bc8d2da7cd1`。原件 `/tmp/temperature-sigpipe-red-green/WorkerClient-baseline.swift` SHA256 `7915319f626ca44e25d1936c7fd7848ab3ea39e9dc11b13f313fc30d66b3da0b`。

仓库路径根为 `/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring/Packages/TemperatureCore/`。

- 基线 `Sources/SensorRuntime/WorkerClient.swift:226` 在 IO queue 调用真实 `writeRequest`；`:392–395` 使用 `FileHandle.write(contentsOf:)`，没有 pipe 级 SIGPIPE 保护。
- 基线 `:287–299` 启动 worker 后发布 stdin/stdout/stderr；`:190–192` 已有 `workerExitedUnexpectedly` → terminate → sensorProtocol/exit 路径；`:196–198` generic catch 原样抛底层错误。
- `Sources/SensorWorker/SensorWorkerEntry.swift:11` 先构造 `WorkerClock`，其失败先于 `HardwareSession` 初始化；`Sources/SensorWorker/WorkerClock.swift:10–14` 拒绝无法解析或大于当前 origin 的 parent origin。
- `Tests/SensorRuntimeTests/SessionClockRegressionTests.swift:29–36` 以 invalid/UInt64.max 注入上述拒绝；这只是候选 CI 触发器。
- 候选复制件 `Sources/SensorRuntime/WorkerClient.swift:287–301` 在新 pipe 描述符上先配置，再 process.run；失败关闭全部6端，尚未发布 IOHandles。`:406–410` 配置 helper 使用 Int32 fd；`:412–426` 原 Foundation 写入仅针对直接/underlying POSIX EPIPE 映射既有 transport exit，其余错误原样保留。

## API 依据与最小设计

Xcode macOS26.2 SDK `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/usr/include/sys/fcntl.h:292–293` 提供 F_SETNOSIGPIPE73/F_GETNOSIGPIPE74。[Apple xnu fcntl(2)](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2) 第245–266行规定：非零参数只禁止该描述符上的 SIGPIPE，默认0；适用于无 reader 的 pipe/socket。本改动仅使用系统 API，没有复制上游实质源码。

独立 C 探针 `/tmp/temperature-sigpipe-red-green/fd_probe.c` 在默认 SIGPIPE 下验证：未保护进程 returncode=-13；保护后 write=-1/EPIPE32，目标 fd flag0→1、另一个 pipe仍0，失效 fd fcntl=-1/EBADF9。见 `fd-probe-results.json`。

将 fd 配置放 spawn 前，避开 deadline `interruptTransportIO()` 关闭 FileHandle 后新增访问其 fileDescriptor 的风险。探索性 per-write 配置方案已被淘汰：`green-fd.log` 显示已关闭 FileHandle 的 getter 抛 ObjC NSException/signal6；`baseline-closed-handle.log` 则证明原 Foundation 写入同一关闭对象会抛可捕获 Swift error。最终代码保留这条原写入行为。

仅 F_SETNOSIGPIPE 仍不满足原错误边界：`red-unmapped.log` 记录 Cocoa512 包装 POSIX32；故精确映射 EPIPE 至既有 workerExitedUnexpectedly，让 `perform` 的现行分支返回 MonitorFailure。没有全局 SIG_IGN、没有新 public API/default/schema/contract 字段、没有直接 POSIX 替换整个 write 循环。

## 最终测试身份与结果

- 最终 public source：`TemperatureCore/Tests/SensorRuntimeTests/WorkerBrokenPipeIntegrationTests.swift` SHA256 `157f0e4a6c2ece4531d86abcb59dafceaf80a2c4aa5fde3c607b073052443bc9`。
- 最终 fixture：`TemperatureCore/Tests/Fixtures/ProtocolWorker/main.swift` SHA256 `10ebb08ea5cac80ff46660bb684da8019f153d0ae8a198bb09a020ba3ca1b897`。fixture 先关闭 stdin 再发送 catalog 作为时序 barrier，存活有界10秒；父客户端正常错误回收立即结束它。
- 最终 production source SHA256 `3e354752bab5fea10546708a86378114149908500cef60bc93b1c0e9f90a3a29`。

| 证据 | 实际结果 | 范围 |
| --- | --- | --- |
| `public-red.log` | exit1，signal13，build成功1.35s | 完整原 f42 + 最终 public source/fixture |
| `public-green.log` | exit0，2tests/1suite，0.617s | 同一最终 case，typed failure、OS回收；false16轮辅助 |
| `unit-green.log` | exit0，4tests/1suite | 最终unit源码、同候选生产源码；默认signal策略/其他pipe不变、完整newline帧、-1 fd错误、关闭FileHandle写入Swift error |
| `invalid-origin-green.log` | exit0，1test/1suite | 原 malformed/future origin 拒绝测试，不访问硬件 |
| `runtime-green.log` | exit0，34tests/4suites，2.291s | 先前2秒fixture版本的纯软件4suite回归；未包含最终OS断言更新，且与public/unit重复，不可相加当总数 |

初始直接 helper signal13 RED 使用仅 private→internal 的访问级别修改；其测试源与最终新增 configure helper 的 unit 源不同，不能宣称整个最终unit文件在旧源码可编译/同源红绿。**最终公开 case/fixture 同源红绿**是生产接线的主要证据。

`red-unmapped.log` 的早期 closed-fd 构造曾直接关闭 FileHandle 拥有的 fd；独立审查指出并发 fd 复用/双所有权风险，该构造已从最终测试删除，最终只用明确 -1 fd 验证配置失败，不用早期该 case 宣称安全性通过。其断管 EPIPE 类型失配输出仍是映射必要性的证据。

非预期首跑均保留：`red-first.log` 沙箱模块缓存拒绝（环境失败，不是 RED）；`public-first-setup-timeout.log` 200ms discovery 启动超时（fixture设置失败，不是 SIGPIPE）；per-write探索 `green-fd.log` signal6。旧2s public对照保存 `public-red-2s.log` / `public-green-2s.log`；10s且未加OS断言的中间RED保存 `public-red-10s-before-os-check.log`。

## 补丁与范围

- `/tmp/temperature-sigpipe-red-green/production.patch` SHA256 `ec5ee344542b5fe281b7d177761c0e3d47eeac74a33ba7941f29dc27161e6d65`：仅 WorkerClient。
- `/tmp/temperature-sigpipe-red-green/tests.patch` SHA256 `93672b6186ad2b552f09a9adbdf5f229b3f1ed4540ebcb21b858df5aae36d242`：两个新测试文件、ProtocolWorker fixture。
- `/tmp/temperature-sigpipe-red-green/source-hashes.json`、`run-summary.json`、`evidence-manifest.json`：源身份、实际 exit/count、所有日志/补丁 SHA256。

补丁 apply--check 通过；本 agent 未应用仓库。固定 `/tmp/temperature-sigpipe-red-green/run-tests.sh` 参数白名单、固定copy package/cache、jobs1，不接受任意命令。测试 fixture 在 `Package.swift:50–52` 仅属于 ProtocolWorker target；正式 `SensorWorker` 使用独立 `Sources/SensorWorker` target；`scripts/build-app.sh:8,59` 选择并安装 SensorWorker。源码边界检查没有把新 fixture 注入 SensorWorker/App，Release具体二进制边界由根 agent 新构建检查。

公开 GREEN 证明 EPIPE recovery 路径和一次回收；不声称已动态注入所有 spawn配置失败/Process.run失败 cleanup 组合，6端清理为源码独立审查。没有把软件 fixture 结果当作正式硬件 App 验收，没有据此恢复五档长测完整通过或真实睡眠通过。
