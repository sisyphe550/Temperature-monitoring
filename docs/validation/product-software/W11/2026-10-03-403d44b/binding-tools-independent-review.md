# W11 v2 工具独立复核

## 结论

完成约定工具范围复核；修复后的工具组合无新增重要问题。真实工作树最后一次独立运行35 tests PASS（exit0），binder dry-run PASS，普通handoff PASS。`--product-acceptance`按预期exit1拒绝37项pending，没有将94 accepted/1 waived解释为132全部验收。

本次只读工作树，没有修改repo/Git/远端，没有GUI、正式App或硬件运行。测试仅在/tmp建立Git fixtures。工具文件为未提交工作树快照，精确哈希见同目录JSON；后续修改应重新核对适用范围。

## 已复现并修复的边界

- delivery与实际HEAD脱离：旧v2只检查artifact source→delivery。独立孤立commit反例实际祖先exit1却accepted；现要求delivery→checked-out HEAD且source→delivery，真实commit对象与非commit/tag拒绝仍适用。
- required kinds省略/空列表：旧v2删除hardware required字段后软件+ci可accepted。现132条结果必须显式非空required_evidence_kinds；accepted必须满足这些种类，pending可保留部分证据但不会自动accepted。
- acceptance格式版本：旧v2接受acceptance-v1.version2；现版本1、catalog版本2、两者contract_revision3全部检查。
- waiver状态矛盾：旧v2在REQ127要求hardware却仅waiver时仍accepted；现waived仅REQ127、required恰为waiver、artifact kind/result成对，并要求用户授权本机豁免说明。
- formal-app-hardware现需结构化Release环境、fixture=false、固定bundle ID、App/worker哈希、model/OS build；CI或fixture不能仅换kind满足硬件条件。reference种类只能在其被声明为required时满足该种类，不会替代formal-app-hardware。

missing/empty required与version/waiver四条负例均观察RED（ValueError未抛），修改后GREEN。root加入HEAD祖先负例，formal gate agent加入环境五负例，独立合并快照与实际工作树35项均通过。

## 证据完整性与写入

Git cat-file要求真实commit；source→delivery→HEAD两段祖先检查。每份artifact核对仓内路径、实际SHA256、scope/environment/TC和result，不再由TC组存在批量推断REQ完成。132条active结果与2条retired分开；validate_bound核对结果/evidence/notes精确一致，retired旧binding不能潜入验证通过。

binder dry-run不写文档。阶段写入两个临时文件再替换；独立注入第二次rename OSError，两个文档均恢复原bytes且没有stage遗留；已纳入35项正式回归。该测试证明已处理的IO错误回滚，不声明断电或进程强杀下两文件事务原子性。

handoff-docs与app工作流checkout均fetch-depth0，后续CI具有祖先检查所需历史。本轮未用任何CI成功状态代替尚未执行的产品验收。

## 最后核对

- HEAD/交付基线：403d44bab8f972461973c5a91699865b15515be2；delivery与HEAD祖先检查exit0。
- 132active：94 product-accepted-local、37 pending-product-acceptance、1 product-waived；2 retired均not-applicable。
- 正式短测证据继续绑定a97生产SHA及既有App/worker哈希；未执行真睡眠、长历史、物理右键等仍在对应pending边界。工具结构校验不代替报告的人工内容审查。
- 检查日志：`/tmp/temperature-w11-v2-final-independent-tests.log`、`/tmp/temperature-w11-v2-final-independent-dry.json`、`/tmp/temperature-w11-v2-final-independent-handoff.json`、`/tmp/temperature-w11-v2-final-independent-product-negative.json`。
- 机器记录：`/tmp/temperature-w11-v2-final-independent-review.json`。

工具定位：{"acceptance: version must be 1": [61], "def _validate_formal_environment": [100], "must be an ancestor of checked-out HEAD": [151], "must be an ancestor of delivery_commit": [169], "f\"{requirement_id}.required_evidence_kinds\", nonempty=True": [210], "waived requires only waiver": [232, 236], "def validate_bound": [272]}
