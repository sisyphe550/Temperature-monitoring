# f9e850c 存储修复与软件/正式App短测

源码：`f9e850cb6986ca9b22980849c503080c8b5d96ee`。153份生产、构建及测试源文件逐字节与该提交对象相等。生产仅改Raw/EMA父一秒窗口的两行索引查找；接口、schema、默认值和对齐规则不变。

- 完整Core：349 tests / 55 suites，0失败；核心7095/7971 = 89.01%。[软件结果](full-core-summary.json)只证明软件/真实SQLite向量，不能等同硬件性能或物理睡眠。
- SQL预期RED两项规模断言失败，同一测试候选GREEN；旧窗口32→2048时，Raw/EMA VM工作量从随窗口增加变为1358/978恒定。实际Store回归覆盖partial父桶、系列/分段、半开边界、cutoff、成员级联和幂等。[修复结果](sql-fix-summary.json)。
- Release构建、签名、上游边界通过；App `7bf8d21d…`，worker `d0b6d7db…`。[身份](source-and-build-identity.json)保存完整hash。
- 首次UI运行器在建立连接前被kill，exit65，无用例启动，保留原失败。重用先前成功的测试目录后，正式App短测1项PASS/149.485s；14个自有App附件，实际CPU12/可选项、五档8秒、历史范围、点选、同会话重开和退出清理。[短测](short-ui/build-and-run-identity.json)。未证实首次kill根因，未将短测当600s资格。
- [独立审查](independent-review.md)批准SQL/TTL的软件范围，审查时短测尚失败，后续重试单独存实际结果，不改其历史结论。

c354的五档duration观察与原FAILED suite保留在相邻不可变目录，不能继承为本版本完整性能通过。精确scheduler skipped、读批p95/p99、首帧/显示p95仍未测；用户已经明确跳过本轮物理睡眠测试。72h软件历史保留。Worker RSS对照仅准备、尚无可用执行结果，不宣称泄漏或改善。

本归档只支持六项已明确的软件TTL缺口局部绑定；其他REQ、CI与blocking按当前目录和GitHub实际状态处理，W11未完整完成。
