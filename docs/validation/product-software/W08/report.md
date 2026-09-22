# W08 App 集成验证报告

记录时间：2026-09-22。
分支：`feature/w08-app-integration`。

## 任务范围

| 任务 | 提交 | 说明 |
|---|---|---|
| T08.1 | `78b9515` | 生产资源、AppSessionRuntime、SessionCoordinator 扩展 |
| T08.2 | `48fa445` | SensorWorker、build-app.sh、嵌入与 ad-hoc 签名 |
| T08.3 | 本提交 | EndToEndTests、app-build CI、TC-UPSTREAM-BOUNDARY、本报告 |

## Core / E2E 测试

```sh
swift test --package-path Packages/TemperatureCore --filter 'EndToEndTests|TC-UPSTREAM-BOUNDARY'
swift test --package-path Packages/TemperatureCore
python3 scripts/validate-handoff.py
```

| 检查 | 结果 |
|---|---|
| EndToEndTests + TC-UPSTREAM-BOUNDARY | **10/10** 通过 |
| 全量 Core 测试 | **244/244** 通过 |
| validate-handoff | passed（含 app-build workflow 登记） |

### EndToEndTests 覆盖

- 12 源 CPU 软件闭环：Raw → EMA → SQLite → 历史
- 会话退出删除 DB/WAL/SHM
- Gap 批次持久化
- 写队列背压拒绝额外 reserve
- DB BUSY 重试策略

### TC-UPSTREAM-BOUNDARY 覆盖

- 12 来源不推断 10 物理核
- 同名 HID、不同 registryID 不合并
- 缺 HID 事件 / NVMe Kelvin 0 不 fabrication
- 上游 rollback 不 replay 旧样本
- SensorBridge 源码无写 SMC / 提权符号

## App 构建与边界扫描

```sh
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 build/TemperatureMonitor.app
python3 scripts/check-upstream-boundary.py
python3 scripts/test-upstream-boundary-gate.py
```

| 检查 | 结果 |
|---|---|
| Release App + 嵌入 SensorWorker | 通过 |
| ad-hoc codesign verify | valid on disk |
| Release 二进制禁 fixture/protocol 符号 | 通过 |
| 未登记 copied 文件红 fixture | 门禁拒绝 |
| App 资源与契约 revision 2 逐字一致 | 通过 |

## UI 测试

```sh
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

| 检查 | 结果 |
|---|---|
| XCUITest | **8/8** 执行，**7** 通过，**1** skip（Release fixture 策略） |

## CI

新增 [`.github/workflows/app.yml`](../../../../.github/workflows/app.yml)：

- job 名：`app-build`
- 记录 Xcode / Swift / SDK 版本
- E2E → build-app.sh → codesign → TC-UPSTREAM-BOUNDARY → XCUITest → validate-handoff

`configure-repository.sh` 新增 `--require-app-build`；维护者可在 workflow 首次绿后启用 required check。

## 实现摘要

- Release 路径：`Bundle.main.sensorWorkerExecutableURL` → `AppSessionRuntime` → `WorkerClient` + `QualifiedSensorClient`
- Debug 仍可用 `--ui-fixture`；Release 拒绝 fixture 启动（`UIFixtureLaunchPolicy`）
- 产物固定为 `build/TemperatureMonitor.app`，内嵌同构建 `Contents/MacOS/SensorWorker`

## 限制与 W09 项

- `ProfileRegistry` 仍只资格化 12 个 CPU 键；Battery/SSD Registry 集成留后续
- 无 Developer ID / 公证；Gatekeeper 分发不在本 W 范围
- 实机 12 键、五档、sleep/wake、72h 留 W09
- HID/NVMe worker 发现为底层事实；实机资格需 W09 证据

## 关联需求（本 W 有证据子集）

REQ-098、100～108、112、124、126/127 中 App 工程、worker 嵌入、本地构建、Release 边界与 CI 相关条目；硬件验收与正式发布不在本 W 范围。
