# 本机课程交付最终独立审查

日期：2026-10-03。审查者为未实施本轮生产修复和交付政策的独立 agent。本轮仅此一次最终审查；未重跑 Core、GUI、长测、模型复现或负控。

## 结论

**PASS：未发现阻塞当前本机课程交付的代码或证据问题。** 本结论不代替最终 PR head 的五项 required CI、零真实 blocking 及合并状态回读，不声明旧132项完整资格通过。

审查基线：main `403d44bab8f972461973c5a91699865b15515be2` 至 HEAD `5984b9e869467218e117976df7d7a320121b14d5`，以及当时尚待提交的课程报告/catalog/policy 引用。交付生产/构建输入相对 `7124dc1` 无变化；Core 与 UITests 测试相对 `f24f503` 无变化。最终文档状态回填不改变本次源码审查范围。

## 已核对

- 生产修复：正常睡眠期间历史请求返回取消，未将未启动/已停止错误改成成功；启动、停止和历史任务失效顺序保留真实故障路径。AppKit 退出经 common RunLoop 调度，允许异步关闭回复；实际退出证据保持独立。SIGPIPE 保护在 spawn 前仅配置新的请求 fd，EPIPE 走既有错误/子进程回收，未改变全局信号策略。TTL 查找保持 series、segment、1秒父窗与结束边界。历史自动更新限1Hz，主动选择仍立即更新；图表等值比较包含时间锚，未复用旧温度生成样本。
- 真实采集与门禁：固定CPU12、Qualified来源、°C、ReadingOutcome成功/失败边界、Raw max/EMA 与既有异常回归保留。课程政策包含134项分层和五个必需 criterion，软件不能替代三项正式App证据，覆盖下限仍80%；原100 accepted/31 pending/1 waived/2 retired未批量改为通过。
- `python3 scripts/validate-handoff.py --product-acceptance` 实际 PASS；`python3 scripts/tests/test-course-acceptance.py` 31项 PASS。证据文件hash、Git祖先关系和正式Release/fixture=false检查保持。
- 原完整Core日志实际为355项/57组 PASS、3.196秒。逐文件覆盖计数重新相加为7116/8002=88.93%，分母未缩减。
- 交付目录App/worker哈希与当前build及7124正式产物精确一致，分别为 `eae5c0b46776eebfa7a297cae46ac0a0d08ad833fa574230897d2ee54da35651` / `12356c172d67e4d6161543aa86a6a0616d5133e3121ac91bd0f9cb6e03c78c96`；交付副本 `codesign --verify --deep --strict` 通过。
- 当前报告将211.244秒XCTest AX NoMatch保留为FAILED，并单列同一正式App会话的原生UI补验。原有效自动短测断言全部恢复，未把失败改为绿灯。点选只引用同二进制7124的正式PASS，明确不声称本次原生坐标失败后点选通过。
- 原生资源105条采样记录与报告一致。填充历史后50ms窗口35次：App CPU中位57.2%，worker0.7%；App RSS首/末381312/396368KiB，worker40128/48528KiB。报告限定短时持续采样和操作响应，未据此声称长期零泄漏、严格A/B改善或精确性能达标。

## 非阻塞限制与文字整理

支持结论只限本机Mac16,13 / macOS15.7.3(24G419)与该ad-hoc产物；物理休眠、72/73h、五档各10min、精确SLO、公证/公开发行/跨机及旧132项全资格不在本轮门槛。短时RSS观察不足以排除长期泄漏；发生新的可复现资源异常仍须按真实缺陷处理，不能用范围缩减豁免。

当前入口文档中仍有“最终短测待确认”“交付路径待补录”“330s自动短测”等进行中措辞。建议在最终提交前改为本轮实际失败加原生补验及交付路径链接，避免后续agent重复测试；这是文档状态回填，不需要新Core或实机长测。

满足最新head required CI、Issue实际状态及Git流程后，可按用户已给出的授权执行merge commit并保留开发分支。
