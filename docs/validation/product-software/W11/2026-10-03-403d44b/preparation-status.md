# W11准备与失败证据边界

PR44已以merge403合入main，旧W11报告bytes保存。这里的403目录是本轮起始基线；新修复源码及正式App最终hash会在后续新提交证据目录记录，不能把本目录名称当成新的App代码SHA。

- 原长测未完成任一600秒phase。初步中断报告仅凭电源/AX无法判产品；后续Fatal/诊断/sample补证确认#46睡眠刷新竞争和#47退出死锁，前报告保留当时认识，不回写。
- 自有旧测试PID86292在取得保全证据后已通过单独授权TERM结束，随后初版修复App正常启动清理51c0旧Session。旧Fatal报告bytes仍与保全副本一致。
- AppKit harness的两个RED仅为自己的临时进程，watchdog结束自己handle；RunLoop GREEN证明调度方式，不代替正式App验收。
- 初版修复正式App已采样后注入自己Session写错误，30.35秒退出/清理。观察脚本遗漏Diagnostics/reports子目录而exit1；path-correction保存实际报告，最终代码仍需修正脚本复测。未将第一次exit1写为PASS。
- 新工具35tests与独立审查通过；94accepted/37pending/1waived只绑定403/a97/651冻结证据，新软件修复/硬件测试尚未由此接受。启动期间willSleep接线修复仍在进行。
