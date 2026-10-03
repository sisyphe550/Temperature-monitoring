# f9最终归档与六项TTL裁决补充独立审查

日期：2026-10-03。范围：最终归档身份、hash、正式短测重试记录、六项软件TTL局部裁决及REQ-094/110的剩余边界。未修改仓库，未重跑Core/UI/硬件测试，未启动GUI或睡眠。此前SQL/TTL生产审查见同目录`independent-review.md`；其“当时短UI失败”结论保持原样，本补充只审核后来重试的实际新记录。

## 结论

**本次限定范围无阻断发现。** 仅REQ-031/033/034/035/036/037从pending更新为product-accepted-local；其软件向量、对应源码、日志、必需TC及证据kind充分。100项accepted、31项pending、1项授权waived、2项retired的当前计数可复算。本结论不批准W11整体完成、完整正式App资格或PR合并。

## 独立执行的只读检查

脚本：`/tmp/temperature-final-f9-supplemental-check.py`；原始结果：`/tmp/temperature-final-f9-supplemental-check.json`，exit 0，failures=[]。

- `docs/validation/product-software/W11/2026-10-03-f9e850c/`审查时有34个文件，其中33个manifest条目，manifest自身按约定排除。每项大小/SHA256、gzip解压大小/SHA256全部匹配，清单和实际文件集合相等。
- source-and-build-identity中的153份生产、构建和测试源文件，逐一读取真实Git `f9e850cb6986ca9b22980849c503080c8b5d96ee`对象及当前工作树，全部SHA256相等。source与delivery都是实际f9提交；六项引用的所有证据source均为delivery祖先。
- 新正式App实际文件hash为`7bf8d21dcd825497484573ec57b79d773b3cb933e0e708791b3641a5d799722c`，worker为`d0b6d7dbc08299b292dccc6e7076f494ce18366d5c5b0d7c3ba602c79b040b65`，与source identity及短测identity相等；Release、fixture=false、Mac16,13、24G419边界明确。
- 14份自有App附件的大小/hash全部匹配。短测归档identity与正式构建身份一致；原始重试log实际读取并核对SHA256及字节数，包含TEST SUCCEEDED，testLocalReleaseAppRealHardwareUI成功149.48459994792938秒。
- 原bootstrap失败压缩日志实际包含TEST FAILED及bootstrapping错误，未被删除或覆盖。重用此前成功目录后重试通过，只证明此次执行通过，不能据此确定首次kill根因。

## 六项局部accepted的证据边界

逐条核对当前acceptance-v1与catalog。六项required_evidence_kinds均为software，映射TC均为TC-LIFECYCLE和TC-RETENTION；引用passed、非waiver软件证据覆盖这两组。新final-core-ttl的full-core-summary文件hash匹配，绑定实际f9源码与349 tests/55 suites、89.01%结果；明确真实SQLite和虚拟elapsed范围。

| REQ | 闭合的软件缺口 |
|---|---|
| 031 | 1s 3600s cutoff−1/0/+1ns删除与保留身份 |
| 033 | 1min 259200s cutoff−1/0/+1ns边界 |
| 034 | Trend 3600s边界 |
| 035 | prune前SQL仍含过期1min记录，threeDays查询独立过滤 |
| 036 | 同一生产prune逐层验证Raw/EMA、1s/10s/1min、Trend，并保留无已提交父桶样本 |
| 037 | Controller 59.999/60/119.999/120s虚拟elapsed、两次真实SQLite删除及维护重新登记 |

六项covered_cases明确定位新增测试，outstanding为空，acceptance-v1同步；对比f9提交中的原catalog，只有这六项verification变化。未由一组TC或一份软件通过推导其他REQ accepted，未新增整REQ睡眠豁免。

## 保留的未完成范围

- REQ-094仍pending：菜单栏/Popover、运行中UI重试/Fatal及其他未覆盖EARS用例未完成；c354原长测suite仍FAILED，五档仅duration observed，精确性能未测。
- REQ-110仍pending：新f9 App/worker整体资格未齐，正式五档每档仅8秒短测；c354长测是历史身份，不能继承为f9完整资格。四类平台清单与sources+schedules+lifecycle组合仍需按实际证据处理。
- 两项都明确本轮物理sleep由用户跳过，旧attempt只partial，不要求再次执行，不标passed；生命周期功能与软件测试保留。
- 精确scheduler skipped、读批p95/p99、首帧/显示p95仍未测；149秒短测、Raw间隔或SQL回放不能替代它们。
- GitHub exact-head CI、blocking Issue状态和是否合并不在本补充检查内，须由root另核对。

此前current-plan correctivepatch已集成，计划将c354与403历史身份分开，当前执行入口不再安排新物理睡眠；后续新证据必须按各自源码/产物绑定。历史归档和原失败结论没有因重试成功被改写。
