# 校验、EMA、Raw聚合与趋势契约

更新：2026-09-17；C10/C11基线v1。以下参数是实现选择，不是传感器精度或实测性能结论。机器可读值见[defaults-v1.json](contracts/defaults-v1.json)。

## 输入与顺序

接口成功、来源身份存在、单位证据成立且值有限时接纳；null/NaN/Infinity、长度/编码错误、源定义的无效哨兵按读取失败处理。没有统一“高于110°C就丢弃”规则，也不能把0°C通用地当错误。重复数值照常计数。

同一requestID仅处理一次；旧worker generation、同sampleID重复交付、同一series的非递增elapsed时间拒绝且记录。真正重复请求ID不触发Fatal；相同ID不同内容为协议/一致性失败。一个CPU批次内每source必须恰好一次。

原始来源Raw分别入Buffer、EMA和聚合。CPU主指标以**固定12成员同一次请求的Raw先求max**，再独立EMA、聚合；派生记录引用输入sampleID，不计为额外硬件读取。一个成员失败或批内时间跨度超过200ms，本批不生成主指标，走CPU读取重试；耗尽则关键能力Fatal。不静默改成剩余成员max。

## 时间、段与缺口

SystemClock用系统mach_continuous_time相对父进程会话基准计elapsed纳秒，并用mach_timebase_info换算；时间包括睡眠。ContinuousClock只用于异步等待剩余时长，不手写硬件时钟频率。实际Date另存wallUnixNS，TTL/dt/窗口/调度全部使用elapsed。图表横轴用“距现在多久”，tooltip显示该观测的实际墙钟；墙钟跳变>1s标记clockChange并分段，不改变历史年龄。

缺口条件：明确失败、sleep、背压暂停、来源/定义变化、时钟跳变，或相邻有效点`dt > max(3×max(previousPeriod,currentPeriod), 1s)`。一次连续缺口只建一个Gap，恢复时结束它并segment+1。正常档位切换保留历史，不因新档位比旧档位长而误判缺口。

失败后可显示有标记的旧缓存；缓存不进入Raw/EMA/count。新段的EMA、趋势从空状态开始，聚合按新段另存。

## EMA

`alpha = -expm1(-dt/tau)`；`ema = previous + alpha*(raw-previous)`。首点直接等于Raw。CPU主指标/热区tau=0.5s，SSD=2s，Battery=4s；参数变更必须新算法版本和新段。dt≤0拒绝，不能除以0或继续EMA。

参考验收：Raw=80初始化；0.5s后100，EMA=92.6424111766；再0.5s后100，EMA=97.2932943353，误差容限1e-8。平滑不改变Raw峰值分路。

## 窗口闭合与迟到

窗口以会话elapsed=0为原点，区间`[k×width,(k+1)×width)`，点恰好落边界属于下一窗口。width为1、10、60秒。每次新事件和每秒tick推进水位，但**只有所有开始时间小于窗口终点的在途请求都返回或超时、且返回事件已经加工后才能封窗**。调度器向加工器传递的advance时间是安全水位，不是随意的当前墙钟。

worker响应先附实际完成时间再一次性交付；跨窗口批次按每来源完成时间分配，派生点时间取最晚成员完成时间。超时后的旧响应丢弃，不重开已封窗口。worker最大1秒读期限使水位延迟有界。sleep/stop先终结在途请求，再封部分窗口。

启动、结束、段变更时允许部分窗口。无有效点不写Bucket，Gap和窗口水位表示空窗；父窗口按边界闭合，不等待实际收到10或6条子记录。部分覆盖记partial=true。

## 聚合

每层保存`min,max,sum,count,latest,latestSampleID,latestElapsedNS,coverageNS,partial`，avg=sum/count。1s从Raw生成；10s/1min从已闭合子窗口合并：min取小、max取大、sum与count相加，latest取最大elapsed，平局用sampleID序号。只合并同seriesID＋segment，定义变更不能跨层混合。

coverageNS定义为同段内有效观测所覆盖的时间并集：每个点从自身时间覆盖至`min(下一有效点时间, 点时间+当时请求周期, 窗口结束)`，最后点最多覆盖一个请求周期；不跨Gap。合并覆盖取子窗口覆盖和，上限窗口宽度。它是观测覆盖估计，不代表硬件测量持续有效时间。partial在覆盖少于窗口宽度、启动/结束截断或存在Gap时为true。

`[70,71,72,95,74]`→min70、max95、sum382、count5、avg76.4、latest74。A(avg60,count1)＋B(avg80,count3)→sum300,count4,avg75，不是70。一个10s窗口仅首尾1s有数据，仍在水位到10s时生成count合计及partial=true的父结果。

父子记录按顺序或同批提交后才允许TTL删除子层。迟到定义、重试幂等和缺口分段固定，不能由实现者自行补零/补旧值。

## 趋势

每秒水位tick对同段EMA按真实时间线性最小二乘回归，时间原点移到首点；CPU主指标10s、CPU热区5s、SSD30s、Battery60s。至少3点且末首跨度≥窗口80%，否则slope=NULL、direction=insufficient。窗口只保留最近指定时间的数据。

`abs(k) <= 0.02°C/s`为stable，大于为rising，小于负阈值为falling。阈值只是显示方向的死区，不是高温告警或测量准确度。缺口后重新积累完整覆盖；不跨缺口拟合。

## 串行与幂等

加工器一个actor串行处理。临时输出整体成功入持久化队列后交换内部状态；重试相同batch只做存储，不重跑EMA或累计count。纯算法违反不变量直接结构性错误；只有外部暂时执行失败可按06重试。算法断言与验收向量见[10](10-test-strategy.md)。
