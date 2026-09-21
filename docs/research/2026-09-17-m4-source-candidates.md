# M4 Air 已记录来源与候选映射

整理日期：2026-09-17；数据采集日期：2026-09-15。本表仅重新分析已有证据，未重新读取硬件。

原始输入：[capabilities.json](../validation/2026-09-15-m4-air/capabilities.json)，SHA-256 `f24cfbda375eb81d53385be3492bc630e8b0afb36fa52bcac9a76fe929c690e5`。

环境：Mac16,13／Apple M4／10个物理CPU核心／macOS15.7.3 (24G419)。来源定义与上游固定链接见 [复核方案](../19-reference-informed-design.md)。

## 解释边界

- 共249个记录：200个SMC T*候选、47个HID服务、1个SMART来源、1个缺失的电源字段；不等于249个有效或独立温度传感器。
- 数值是初次枚举的解码快照，不是本次读数、同时刻快照或负载测试结果。SMC/HID字段虽名为celsius，原报告仍将单位解释与物理映射标为待验证；本表不提升其证据等级。
- 表中保留六位小数仅用于转录核对，不表示测量精度；完整数值与原始字节以输入JSON为准。
- SMC键区分大小写；HID冒号前序号仅在原型该进程内稳定。没有证明同名/同值来源是别名，不合并。
- 状态沿用原文件；`decoded_mapping_unverified`只表示已解码，不表示已经确认物理含义或精度。非法/未知类型保持空值。
- IORegistry电池诊断值2968未列入周期来源，单位未知，禁止直接换算。

## 优先验证的SMC候选

| 原始键 | 初次解码数值 | 候选解释／限制 |
|---|---:|---|
| `Te05` | 37.965702 | R01 M4 E域候选；不是物理核编号 |
| `Te0S` | 36.528202 | R01 M4 E域候选；不是物理核编号 |
| `Te09` | 37.631798 | R01 M4 E域候选；不是物理核编号 |
| `Te0H` | 36.882187 | R01 M4 E域候选；不是物理核编号 |
| `Tp01` | 42.260826 | R01 M4 P域候选；不是物理核编号 |
| `Tp05` | 42.021843 | R01 M4 P域候选；不是物理核编号 |
| `Tp09` | 41.013321 | R01 M4 P域候选；不是物理核编号 |
| `Tp0D` | 42.391827 | R01 M4 P域候选；不是物理核编号 |
| `Tp0V` | 44.818958 | R01 M4 P域候选；不是物理核编号 |
| `Tp0Y` | 42.714760 | R01 M4 P域候选；不是物理核编号 |
| `Tp0b` | 40.832726 | R01 M4 P域候选；不是物理核编号 |
| `Tp0e` | 41.979595 | R01 M4 P域候选；不是物理核编号 |
| `TCMz` | 76.046875 | R02 CPU主读数候选；M4语义/响应未验证 |
| `TCMb` | 44.818958 | R02 CPU主读数候选；M4语义/响应未验证 |
| `TPMP` | 26.970428 | R02/R04命名冲突；禁作已确认映射 |
| `Ts1P` | 20.875000 | R02/R04命名冲突；禁作已确认映射 |
| `T5SP` | 26.970428 | 存储相关候选；不等于SMART composite |
| `TH0T` | 25.591721 | 存储相关候选；不等于SMART composite |
| `TH0x` | 25.591721 | 存储相关候选；不等于SMART composite |
| `TB0T` | 23.599991 | 电池候选；与HID关系未确认 |
| `TB1T` | 23.599991 | 电池候选；与HID关系未确认 |
| `TB2T` | 22.599991 | 电池候选；与HID关系未确认 |

以上12个R01 CPU候选全部可读，但本机物理核心数为10。该集合仍是验证输入，不是生产映射表。其余候选的正常轮询参与资格由V2-01/02决定。

## 全部已记录来源

| # | Provider | 原始ID | 类型 | 初次解码数值 | 原始状态 | 本次分类备注 |
|---:|---|---|---|---:|---|---|
| 1 | AppleSMC | `T5SP` | `flt ` | 26.970428 | `decoded_mapping_unverified` | 存储相关候选；不等于SMART composite |
| 2 | AppleSMC | `TAOL` | `flt ` | 20.898438 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 3 | AppleSMC | `TB0T` | `flt ` | 23.599991 | `decoded_mapping_unverified` | 电池候选；与HID关系未确认 |
| 4 | AppleSMC | `TB1T` | `flt ` | 23.599991 | `decoded_mapping_unverified` | 电池候选；与HID关系未确认 |
| 5 | AppleSMC | `TB2T` | `flt ` | 22.599991 | `decoded_mapping_unverified` | 电池候选；与HID关系未确认 |
| 6 | AppleSMC | `TCHP` | `flt ` | 27.186401 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 7 | AppleSMC | `TCMb` | `flt ` | 44.818958 | `decoded_mapping_unverified` | R02 CPU主读数候选；M4语义/响应未验证 |
| 8 | AppleSMC | `TCMz` | `flt ` | 76.046875 | `decoded_mapping_unverified` | R02 CPU主读数候选；M4语义/响应未验证 |
| 9 | AppleSMC | `TDBP` | `flt ` | 22.875000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 10 | AppleSMC | `TDeL` | `flt ` | 22.250000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 11 | AppleSMC | `TG0B` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 12 | AppleSMC | `TG0C` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 13 | AppleSMC | `TG0H` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 14 | AppleSMC | `TG0V` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 15 | AppleSMC | `TG1B` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 16 | AppleSMC | `TG2B` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 17 | AppleSMC | `TH0T` | `flt ` | 25.591721 | `decoded_mapping_unverified` | 存储相关候选；不等于SMART composite |
| 18 | AppleSMC | `TH0x` | `flt ` | 25.591721 | `decoded_mapping_unverified` | 存储相关候选；不等于SMART composite |
| 19 | AppleSMC | `TIOP` | `flt ` | 25.520721 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 20 | AppleSMC | `TMVR` | `flt ` | 26.535507 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 21 | AppleSMC | `TPD0` | `flt ` | 30.852341 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 22 | AppleSMC | `TPD1` | `flt ` | 28.933319 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 23 | AppleSMC | `TPD2` | `flt ` | 29.173203 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 24 | AppleSMC | `TPD3` | `flt ` | 28.053772 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 25 | AppleSMC | `TPD4` | `flt ` | 28.693451 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 26 | AppleSMC | `TPD5` | `flt ` | 31.412048 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 27 | AppleSMC | `TPD6` | `flt ` | 29.253159 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 28 | AppleSMC | `TPD7` | `flt ` | 32.451508 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 29 | AppleSMC | `TPD8` | `flt ` | 28.133728 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 30 | AppleSMC | `TPD9` | `flt ` | 28.293655 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 31 | AppleSMC | `TPDA` | `flt ` | 28.053772 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 32 | AppleSMC | `TPDB` | `flt ` | 28.693451 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 33 | AppleSMC | `TPDC` | `flt ` | 28.453568 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 34 | AppleSMC | `TPDD` | `flt ` | 28.053772 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 35 | AppleSMC | `TPDE` | `flt ` | 28.533524 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 36 | AppleSMC | `TPDF` | `flt ` | 28.773407 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 37 | AppleSMC | `TPDX` | `flt ` | 32.451508 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 38 | AppleSMC | `TPMP` | `flt ` | 26.970428 | `decoded_mapping_unverified` | R02/R04命名冲突；禁作已确认映射 |
| 39 | AppleSMC | `TPSP` | `flt ` | 26.171600 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 40 | AppleSMC | `TR0Z` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 41 | AppleSMC | `TR1d` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 42 | AppleSMC | `TR2d` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 43 | AppleSMC | `TR3d` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 44 | AppleSMC | `TR4d` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 45 | AppleSMC | `TR5d` | `ioft` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 46 | AppleSMC | `TRD0` | `flt ` | 26.374649 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 47 | AppleSMC | `TRD1` | `flt ` | 25.814926 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 48 | AppleSMC | `TRD2` | `flt ` | 24.935379 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 49 | AppleSMC | `TRD3` | `flt ` | 24.855423 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 50 | AppleSMC | `TRD4` | `flt ` | 24.535583 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 51 | AppleSMC | `TRD5` | `flt ` | 24.695511 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 52 | AppleSMC | `TRD6` | `flt ` | 25.015335 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 53 | AppleSMC | `TRD7` | `flt ` | 25.175262 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 54 | AppleSMC | `TRD8` | `flt ` | 24.695511 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 55 | AppleSMC | `TRDX` | `flt ` | 26.374649 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 56 | AppleSMC | `TSCD` | `flt ` | 27.331375 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 57 | AppleSMC | `TVA0` | `flt ` | 18.652290 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 58 | AppleSMC | `TVD0` | `flt ` | 44.818958 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 59 | AppleSMC | `TVDi` | `si32` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 60 | AppleSMC | `TVM0` | `flt ` | 30.507904 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 61 | AppleSMC | `TVMD` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 62 | AppleSMC | `TVS0` | `flt ` | 24.289455 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 63 | AppleSMC | `TVS1` | `flt ` | 23.644325 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 64 | AppleSMC | `TVV0` | `flt ` | 32.451508 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 65 | AppleSMC | `TVVi` | `si32` | — | `unsupported_type_or_nonfinite` | 未映射；仅保留诊断 |
| 66 | AppleSMC | `TVXh` | `flt ` | 31.747723 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 67 | AppleSMC | `TVXm` | `flt ` | 30.507904 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 68 | AppleSMC | `TVXs` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 69 | AppleSMC | `TVh0` | `flt ` | 31.747723 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 70 | AppleSMC | `TVh1` | `flt ` | 31.316170 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 71 | AppleSMC | `TVh2` | `flt ` | 31.747723 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 72 | AppleSMC | `TVm0` | `flt ` | 30.638502 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 73 | AppleSMC | `TVm1` | `flt ` | 31.957758 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 74 | AppleSMC | `TVm2` | `flt ` | 30.507904 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 75 | AppleSMC | `TVmS` | `flt ` | 40.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 76 | AppleSMC | `TVmd` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 77 | AppleSMC | `TW0P` | `flt ` | 26.751480 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 78 | AppleSMC | `Ta00` | `flt ` | 25.156250 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 79 | AppleSMC | `Ta01` | `flt ` | 30.156250 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 80 | AppleSMC | `Ta04` | `flt ` | 25.328125 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 81 | AppleSMC | `Ta05` | `flt ` | 30.328125 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 82 | AppleSMC | `Ta08` | `flt ` | 25.375000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 83 | AppleSMC | `Ta09` | `flt ` | 30.375000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 84 | AppleSMC | `Ta0K` | `flt ` | 25.218750 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 85 | AppleSMC | `Ta0L` | `flt ` | 30.218750 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 86 | AppleSMC | `Ta0O` | `flt ` | 24.968750 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 87 | AppleSMC | `Ta0P` | `flt ` | 29.968750 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 88 | AppleSMC | `Ta0R` | `flt ` | 25.078125 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 89 | AppleSMC | `Ta0S` | `flt ` | 30.078125 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 90 | AppleSMC | `Te04` | `flt ` | 31.265701 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 91 | AppleSMC | `Te05` | `flt ` | 37.965702 | `decoded_mapping_unverified` | R01 M4 E域候选；不是物理核编号 |
| 92 | AppleSMC | `Te06` | `flt ` | 45.171875 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 93 | AppleSMC | `Te08` | `flt ` | 30.931797 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 94 | AppleSMC | `Te09` | `flt ` | 37.631798 | `decoded_mapping_unverified` | R01 M4 E域候选；不是物理核编号 |
| 95 | AppleSMC | `Te0A` | `flt ` | 43.703125 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 96 | AppleSMC | `Te0G` | `flt ` | 30.182186 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 97 | AppleSMC | `Te0H` | `flt ` | 36.882187 | `decoded_mapping_unverified` | R01 M4 E域候选；不是物理核编号 |
| 98 | AppleSMC | `Te0I` | `flt ` | 41.812500 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 99 | AppleSMC | `Te0R` | `flt ` | 29.828201 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 100 | AppleSMC | `Te0S` | `flt ` | 36.528202 | `decoded_mapping_unverified` | R01 M4 E域候选；不是物理核编号 |
| 101 | AppleSMC | `Te0T` | `flt ` | 42.546875 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 102 | AppleSMC | `Te0U` | `flt ` | 35.789845 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 103 | AppleSMC | `Te0V` | `flt ` | 45.171875 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 104 | AppleSMC | `Te0W` | `flt ` | 34.340313 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 105 | AppleSMC | `Te0X` | `flt ` | 42.796875 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 106 | AppleSMC | `Tg0C` | `flt ` | 29.207041 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 107 | AppleSMC | `Tg0D` | `flt ` | 33.807041 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 108 | AppleSMC | `Tg0G` | `flt ` | 29.371500 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 109 | AppleSMC | `Tg0H` | `flt ` | 33.971500 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 110 | AppleSMC | `Tg0K` | `flt ` | 30.052221 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 111 | AppleSMC | `Tg0L` | `flt ` | 34.652222 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 112 | AppleSMC | `Tg0O` | `flt ` | 29.165934 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 113 | AppleSMC | `Tg0P` | `flt ` | 33.765934 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 114 | AppleSMC | `Tg0U` | `flt ` | 31.607748 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 115 | AppleSMC | `Tg0V` | `flt ` | 36.207748 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 116 | AppleSMC | `Tg0X` | `flt ` | 30.946962 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 117 | AppleSMC | `Tg0Y` | `flt ` | 35.546963 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 118 | AppleSMC | `Tg0d` | `flt ` | 30.271635 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 119 | AppleSMC | `Tg0e` | `flt ` | 34.871635 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 120 | AppleSMC | `Tg0j` | `flt ` | 29.864920 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 121 | AppleSMC | `Tg0k` | `flt ` | 34.464920 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 122 | AppleSMC | `Tg0m` | `flt ` | 29.835638 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 123 | AppleSMC | `Tg0n` | `flt ` | 34.435638 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 124 | AppleSMC | `Tm0B` | `flt ` | 26.751480 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 125 | AppleSMC | `Tp00` | `flt ` | 35.160828 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 126 | AppleSMC | `Tp01` | `flt ` | 42.260826 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 127 | AppleSMC | `Tp02` | `flt ` | 60.890625 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 128 | AppleSMC | `Tp04` | `flt ` | 34.921844 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 129 | AppleSMC | `Tp05` | `flt ` | 42.021843 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 130 | AppleSMC | `Tp06` | `flt ` | 56.031250 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 131 | AppleSMC | `Tp08` | `flt ` | 33.913322 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 132 | AppleSMC | `Tp09` | `flt ` | 41.013321 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 133 | AppleSMC | `Tp0A` | `flt ` | 54.312500 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 134 | AppleSMC | `Tp0C` | `flt ` | 35.291828 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 135 | AppleSMC | `Tp0D` | `flt ` | 42.391827 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 136 | AppleSMC | `Tp0E` | `flt ` | 64.875000 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 137 | AppleSMC | `Tp0U` | `flt ` | 37.718960 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 138 | AppleSMC | `Tp0V` | `flt ` | 44.818958 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 139 | AppleSMC | `Tp0W` | `flt ` | 73.093750 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 140 | AppleSMC | `Tp0X` | `flt ` | 35.614761 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 141 | AppleSMC | `Tp0Y` | `flt ` | 42.714760 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 142 | AppleSMC | `Tp0Z` | `flt ` | 65.125000 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 143 | AppleSMC | `Tp0a` | `flt ` | 33.732727 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 144 | AppleSMC | `Tp0b` | `flt ` | 40.832726 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 145 | AppleSMC | `Tp0c` | `flt ` | 63.843750 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 146 | AppleSMC | `Tp0d` | `flt ` | 34.879597 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 147 | AppleSMC | `Tp0e` | `flt ` | 41.979595 | `decoded_mapping_unverified` | R01 M4 P域候选；不是物理核编号 |
| 148 | AppleSMC | `Tp0f` | `flt ` | 76.046875 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 149 | AppleSMC | `Tp1A` | `flt ` | 32.306736 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 150 | AppleSMC | `Tp1B` | `flt ` | 40.606735 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 151 | AppleSMC | `Tp1C` | `flt ` | 50.734375 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 152 | AppleSMC | `Tp1E` | `flt ` | 32.515827 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 153 | AppleSMC | `Tp1F` | `flt ` | 40.815826 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 154 | AppleSMC | `Tp1G` | `flt ` | 50.718750 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 155 | AppleSMC | `Tp1Q` | `flt ` | 32.277016 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 156 | AppleSMC | `Tp1R` | `flt ` | 40.577015 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 157 | AppleSMC | `Tp1S` | `flt ` | 50.328125 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 158 | AppleSMC | `Tp3O` | `flt ` | 42.254509 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 159 | AppleSMC | `Tp3P` | `flt ` | 73.093750 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 160 | AppleSMC | `Tp3S` | `flt ` | 37.035297 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 161 | AppleSMC | `Tp3T` | `flt ` | 50.734375 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 162 | AppleSMC | `Tp3W` | `flt ` | 39.812180 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 163 | AppleSMC | `Tp3X` | `flt ` | 76.046875 | `decoded_mapping_unverified` | 前缀启发式CPU候选；未验证语义 |
| 164 | AppleSMC | `Ts00` | `flt ` | 28.402891 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 165 | AppleSMC | `Ts01` | `flt ` | 28.402891 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 166 | AppleSMC | `Ts02` | `flt ` | 29.234375 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 167 | AppleSMC | `Ts04` | `flt ` | 29.092031 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 168 | AppleSMC | `Ts05` | `flt ` | 29.092031 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 169 | AppleSMC | `Ts06` | `flt ` | 30.437500 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 170 | AppleSMC | `Ts08` | `flt ` | 29.440876 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 171 | AppleSMC | `Ts09` | `flt ` | 29.440876 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 172 | AppleSMC | `Ts0A` | `flt ` | 31.234375 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 173 | AppleSMC | `Ts0C` | `flt ` | 30.123272 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 174 | AppleSMC | `Ts0D` | `flt ` | 30.123272 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 175 | AppleSMC | `Ts0E` | `flt ` | 32.656250 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 176 | AppleSMC | `Ts0G` | `flt ` | 31.351366 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 177 | AppleSMC | `Ts0H` | `flt ` | 31.351366 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 178 | AppleSMC | `Ts0I` | `flt ` | 35.015625 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 179 | AppleSMC | `Ts0K` | `flt ` | 32.578911 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 180 | AppleSMC | `Ts0L` | `flt ` | 32.578911 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 181 | AppleSMC | `Ts0M` | `flt ` | 39.734375 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 182 | AppleSMC | `Ts0O` | `flt ` | 30.582129 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 183 | AppleSMC | `Ts0P` | `flt ` | 22.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 184 | AppleSMC | `Ts0Q` | `flt ` | 30.582129 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 185 | AppleSMC | `Ts0R` | `flt ` | 33.046875 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 186 | AppleSMC | `Ts0S` | `flt ` | 32.125000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 187 | AppleSMC | `Ts0T` | `flt ` | 32.125000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 188 | AppleSMC | `Ts0U` | `flt ` | 38.625000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 189 | AppleSMC | `Ts0h` | `flt ` | 32.603828 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 190 | AppleSMC | `Ts0i` | `flt ` | 39.734375 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 191 | AppleSMC | `Ts1P` | `flt ` | 20.875000 | `decoded_mapping_unverified` | R02/R04命名冲突；禁作已确认映射 |
| 192 | AppleSMC | `Tz11` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 193 | AppleSMC | `Tz12` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 194 | AppleSMC | `Tz13` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 195 | AppleSMC | `Tz14` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 196 | AppleSMC | `Tz15` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 197 | AppleSMC | `Tz16` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 198 | AppleSMC | `Tz17` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 199 | AppleSMC | `Tz18` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 200 | AppleSMC | `Tz1j` | `flt ` | 0.000000 | `decoded_mapping_unverified` | 未映射；仅保留诊断 |
| 201 | HID | `0:PMU2 tdev4` | `IOHIDEventFloat` | 27.381668 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 202 | HID | `1:PMU tdev4` | `IOHIDEventFloat` | 26.896454 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 203 | HID | `2:PMU tdie5` | `IOHIDEventFloat` | 29.413071 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 204 | HID | `3:PMU2 tdie10` | `IOHIDEventFloat` | 25.015335 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 205 | HID | `4:PMU tdev6` | `IOHIDEventFloat` | 27.381668 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 206 | HID | `5:PMU2 tdie3` | `IOHIDEventFloat` | 24.855423 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 207 | HID | `6:PMU tdie9` | `IOHIDEventFloat` | 28.693451 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 208 | HID | `7:` | `IOHIDEventFloat` | — | `error:0xe00002f0` | HID候选；物理含义未确认 |
| 209 | HID | `8:PMU2 tdev1` | `IOHIDEventFloat` | -22.212830 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 210 | HID | `9:PMU tdie2` | `IOHIDEventFloat` | 29.413071 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 211 | HID | `10:PMU2 tdie7` | `IOHIDEventFloat` | 24.935379 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 212 | HID | `11:PMU tdie13` | `IOHIDEventFloat` | 28.613495 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 213 | HID | `12:PMU tdev2` | `IOHIDEventFloat` | 27.310654 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 214 | HID | `13:PMU2 tdev5` | `IOHIDEventFloat` | 26.390533 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 215 | HID | `14:PMU tdie6` | `IOHIDEventFloat` | 30.772369 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 216 | HID | `15:PMU tcal` | `IOHIDEventFloat` | 51.820007 | `decoded_mapping_unverified` | 疑似校准来源；不纳入CPU主指标 |
| 217 | HID | `16:gas gauge battery` | `IOHIDEventFloat` | 23.599991 | `decoded_mapping_unverified` | 电池候选；同名实例保留；未证明去重关系 |
| 218 | HID | `17:PMU tdev3` | `IOHIDEventFloat` | 25.630188 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 219 | HID | `18:PMU tdev7` | `IOHIDEventFloat` | 27.550308 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 220 | HID | `19:PMU2 tdie4` | `IOHIDEventFloat` | 25.095306 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 221 | HID | `20:PMU tdie10` | `IOHIDEventFloat` | 28.533524 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 222 | HID | `21:PMU2 tdev2` | `IOHIDEventFloat` | 25.810654 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 223 | HID | `22:PMU tdie3` | `IOHIDEventFloat` | 28.933319 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 224 | HID | `23:PMU2 tdie8` | `IOHIDEventFloat` | 25.495102 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 225 | HID | `24:gas gauge battery` | `IOHIDEventFloat` | 23.599991 | `decoded_mapping_unverified` | 电池候选；同名实例保留；未证明去重关系 |
| 226 | HID | `25:PMU tdie14` | `IOHIDEventFloat` | 28.853363 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 227 | HID | `26:gas gauge battery` | `IOHIDEventFloat` | 22.000000 | `decoded_mapping_unverified` | 电池候选；同名实例保留；未证明去重关系 |
| 228 | HID | `27:PMU2 tdie1` | `IOHIDEventFloat` | 26.054810 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 229 | HID | `28:PMU tdie7` | `IOHIDEventFloat` | 29.892822 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 230 | HID | `29:PMU tdev8` | `IOHIDEventFloat` | 27.071014 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 231 | HID | `30:NAND CH0 temp` | `IOHIDEventFloat` | 24.000000 | `decoded_mapping_unverified` | NAND候选；不等于SMART composite |
| 232 | HID | `31:PMU2 tdie5` | `IOHIDEventFloat` | 24.855423 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 233 | HID | `32:PMU tdie11` | `IOHIDEventFloat` | 28.453568 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 234 | HID | `33:gas gauge battery` | `IOHIDEventFloat` | 23.000000 | `decoded_mapping_unverified` | 电池候选；同名实例保留；未证明去重关系 |
| 235 | HID | `34:PMU2 tdev3` | `IOHIDEventFloat` | -22.232285 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 236 | HID | `35:PMU tdie4` | `IOHIDEventFloat` | 28.133728 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 237 | HID | `36:PMU2 tdie9` | `IOHIDEventFloat` | 24.615555 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 238 | HID | `37:PMU tdev5` | `IOHIDEventFloat` | 27.358002 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 239 | HID | `38:PMU2 tdie2` | `IOHIDEventFloat` | 25.974854 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 240 | HID | `39:PMU tdie8` | `IOHIDEventFloat` | 30.692413 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 241 | HID | `40:PMU tdev1` | `IOHIDEventFloat` | -22.265045 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 242 | HID | `41:PMU2 tcal` | `IOHIDEventFloat` | 51.820007 | `decoded_mapping_unverified` | 疑似校准来源；不纳入CPU主指标 |
| 243 | HID | `42:gas gauge battery` | `IOHIDEventFloat` | 22.599991 | `decoded_mapping_unverified` | 电池候选；同名实例保留；未证明去重关系 |
| 244 | HID | `43:PMU tdie1` | `IOHIDEventFloat` | 28.133728 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 245 | HID | `44:gas gauge battery` | `IOHIDEventFloat` | 23.599991 | `decoded_mapping_unverified` | 电池候选；同名实例保留；未证明去重关系 |
| 246 | HID | `45:PMU2 tdie6` | `IOHIDEventFloat` | 25.095306 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 247 | HID | `46:PMU tdie12` | `IOHIDEventFloat` | 28.933319 | `decoded_mapping_unverified` | HID候选；物理含义未确认 |
| 248 | NVMeSMART | `device:0:TEMPERATURE` | `uint16_le_kelvin` | 23.850000 | `ok` | SMART composite；K−273.15；本机周期读取已通过 |
| 249 | IOPowerSources | `source:0:Temperature` | `missing` | — | `field_absent` | 公开字段声明°C；本机字段缺失 |
