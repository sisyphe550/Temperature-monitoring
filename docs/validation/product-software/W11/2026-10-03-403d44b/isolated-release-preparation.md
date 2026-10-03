# 新正式Release验收准备（403d44b为起始基线）

本目录名不是新修复的生产SHA。源文件逐项hash见`isolated-release-source-snapshot.json`，提交后必须验证完全相等。此前e61a0e二进制下的运行中Fatal实机测试与50ms失败长测保留自身身份，不自动转移到新的cde202a二进制。

- #46：暂停history取消、startup/suspend admission/stop边界已软件RED/GREEN；退出取消的wake误报Fatal有独立RED并已应用同态guard，最终GREEN待集成。
- #47：RunLoop common退出入口与此前实际运行中Fatal自动退出证据已保存；新构建仍需自己的运行中Fatal复验。
- #48：35项证据工具及负例通过；37项pending被完整门禁拒绝。
- #49：历史查询一秒节流、相同history隔离重绘；新正式Release构建、严格签名及Release上游边界通过，性能改善尚未确认。
- 最新失败长测没有完成任一600秒阶段；随后测试必须用新独立run目录和同一冻结二进制，不能拼接旧时段。
- 用户已同意五档长测及后续真实睡眠/手动唤醒；三个真实睡眠回合与五档600秒保持未完成状态。
