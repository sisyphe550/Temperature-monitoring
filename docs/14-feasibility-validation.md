# 已存证据与当前本机验证

更新：2026-10-03；实现契约revision3不变。本轮按[课程交付范围](course-delivery-scope.md)完成最小收尾，历史原型、validation/research不改写。下列验证路线已有工具/实现，不构成未来通过声明。

## 已经执行的历史范围

[2026-09-15报告](validation/2026-09-15-m4-air/validation-report.md)记录Mac16,13/M4/macOS15.7.3/24G419普通用户Release CLI：SMC枚举2147键、HID47服务、SMART可读、IOPS无Temperature字段及五档各60秒。原型cc5db3cf、8项测试和ProbeCore55/55仅证明原型范围，不替代产品。

[接口审计](research/2026-09-17-handoff-interface-audit.md)复核旧CSV中的12个Stats CPU键；[7124正式App归档](validation/product-software/W11/2026-10-03-7124dc1/README.md)证明原产物CPU12/max/EMA、五档短切换、历史和退出；[f0软件归档](validation/product-software/W11/2026-10-03-f0a7dde/README.md)保存新的同步回归。它们均保留原源码/二进制身份，不能预先覆盖当前最后一轮。

## 当前V2验证与可选扩展

| ID | 本轮动作 | 边界与产物 |
|---|---|---|
| V2-01 | 普通用户正式App确认CPU12、来源单位与Raw max→EMA数值 | source/App/worker SHA、profile和机型系统；不减少成员或推断物理核/准确度 |
| V2-02 | 保留SSD内置唯一SMART/Battery固定单源与Unavailable状态 | 实际来源/单位/优先级或明确不可用；单项故障CPU继续，不平均或替换口径 |
| V2-03 | 同一次正式App五档短切换及资源/响应观察，同次观察已填充的五分钟历史，五档短切换 | CPU TIME/RSS、阶段时间与UI响应；精确skipped/p95/p99、五档10min/压力负载为可选 |
| V2-04 | 本轮关窗重开同会话、正常退出；必要worker失败/晚到/软件sleep-wake回归 | 不留本轮App/worker或会话库；物理sleep/唤醒和额外真实强杀不执行 |
| V2-05 | 必要软件完整数据链、Raw/EMA、峰值/TTL、幂等、背压、缓存与Gap回归 | 全Core及覆盖≥80%，异常路径不能缩减；72h历史功能与软件TTL仍保留 |
| V2-06 | 本机ad-hoc Release构建/签名和课程证据交付 | 五criterion与Git门禁；72/73h长跑、Developer ID/公证、公开发行/跨机为可选 |

V2仍对应W02～W11和原50任务/DAG，未新增功能任务。其他软件温度接近只作参考，不证明物理位置或计量精度。真实CPU配置失败则记Issue/必要修复，不能靠降低集合或伪造值达到门槛。

## 证据约定与当前状态

新结果在日期/源码提交目录新增，保存report、environment、profile/能力、时序/资源、原日志、SHA256和适用范围。每项写实际输入/预期/结果、权限/签名、构建SDK/工具链、App/Worker身份；失败、partial、未执行如实记录，不用旧日志占位，不采集序列号等敏感硬件身份。

[c354归档](validation/product-software/W11/2026-10-03-c354b03/README.md)中的原FAILED长测、独立duration与未测性能保留。最新授权取消其作为当前硬门槛，不回写PASS；旧逐REQ100accepted/31pending/1waived/2retired保留。当前最终短测、课程证据绑定、一次独立审查、同head五CI及授权合并仍在收尾中，完成后交付并停止扩展。
