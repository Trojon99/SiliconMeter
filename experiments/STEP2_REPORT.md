# Step 2 — M1 Max / macOS 27.0 遥测实测报告

实测日期：2026-09-23；系统：macOS 27.0 (26A428)，arm64；芯片：Apple M1 Max，8 P + 2 E，64 GiB。仓库从无提交的 `main` 建立 `codex/telemetry-step2` 分支；实验代码与结果均在 `experiments/`。没有构建菜单栏应用、数据库或评分逻辑，也没有提交。完整的紧凑数据和代表性原始样本见 [`results/step2-2026-09-23.json`](results/step2-2026-09-23.json)。

**判断：** 在**普通用户、非 App Sandbox** 的本机程序中，CPU 分组使用率、GPU 活跃率与状态加权频率、`GPU Energy` 功率、选定温度、VM/swap/压力状态，以及 `AMC Stats` 带宽都产生了有负载响应的值。CPU/DRAM 的 `Energy Model` mJ 通道在对应满载时仍为零，不能作为功率。默认 App Sandbox 会拒绝 IOReport 订阅和 AppleSMC 打开。以下结论仅对应这台机器和这个 OS build。

## 决策表

“开销”依据后文的组合实测，不能精确拆成每个指标的独立成本。`v0.1` 表示下一步候选指标，不是已实现的产品功能。

| 指标 | 实测后端；本机能否工作、可靠性 | 预期常驻成本 / 建议间隔 | API 状态 | v0.1 |
|---|---|---|---|---|
| 总 CPU 使用率 | Mach `host_processor_info` 差分；**是**，受控负载方向正确 | 低 / 2 s | 公开 | 保留 |
| P/E 使用率 | 同一 Mach 样本 + 设备树核映射；**是**，分组自洽 | 几乎不增加采集 / 2 s | Mach 公开；设备树属性未公开保证 | 保留，仅 M1 Max 映射已验证 |
| GPU 活跃率 | IOReport `GPUPH`；**是**，约 37% 基线、77% 中等、100% 重负载 | 低至中 / 2 s | 私有 | 保留，标为全机活跃率 |
| GPU 状态加权频率 | `GPUPH` P1–P6 × IORegistry `voltage-states9`；**是，区间估算**，重负载 1296 MHz | 已含于 GPU 组 / 2 s | 私有通道 + 未公开设备属性 | 保留并标“估算” |
| CPU 功率 | IOReport `CPU Energy`、簇/核 mJ 通道；**否**，满载仍全为零 | 即使可订阅也无有效值 | 私有 | 删除/推迟 |
| GPU 功率 | IOReport `GPU Energy` nJ 差分；**是**，负载响应明显，绝对精度未校准 | 中 / 2 s | 私有；硬件能量模型为估算 | 保留，注明估算 |
| DRAM/系统功率 | `DRAM0` mJ 在高带宽负载仍为零；系统 SMC 功率键本次未校准 | 未定 | 私有 | 推迟 |
| CPU 温度 | AppleSMC `Tp05`；**是**，约 51→60°C；是选定 P 核传感器，不是全芯片最高温 | 低 / 5 s | 私有 SMC 协议 | 保留并按传感器标注 |
| GPU 温度 | AppleSMC `Tg05`；**是**，约 51→61°C | 低 / 5 s | 私有 SMC 协议 | 保留并按传感器标注 |
| 统一内存计数 | `HOST_VM_INFO64` + `hw.memsize`；**是**，包含压缩、连线、活跃、非活跃等原始分类 | 低 / 5 s | Mach 公开、`sysctl` | 保留分类值；不宣称单一“已用”定义 |
| Swap 占用 | `vm.swapusage`；**是**，普通用户及 App Sandbox 读到 0 B；无非零样本 | 低 / 5 s | `sysctl` 键在系统头文件中，权限因沙箱而异 | 保留，另显示 swap-in/out 差分 |
| 当前内存压力 | `kern.memorystatus_vm_pressure_level`；**是**，普通用户及 App Sandbox 读到 1（normal）；未产生压力转换 | 低 / 启动读一次，随后按需复核 | 未公开保证的 sysctl 键 | 保留，附来源与失效状态 |
| 压力变化事件 | `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`；事件源**建立成功**，正常状态下没有事件；尚未验证状态转换 | 事件驱动 | 公开 | 保留作变化通知，不能充当初始状态 |
| macOS 热状态 | `ProcessInfo.thermalState`；**是**，负载测试期间均为 nominal；未触发级别变化 | 极低 / 变化通知 | 公开 | 保留 |
| 内存带宽 | IOReport `AMC Stats` / DCS 字节差分；**是**，GFX 流式负载约 215 GB/s；计数口径尚无外部校准 | 中 / 2–5 s | 私有 | 保留 GFX 与 DCS 总量，明确为全机硬件计数 |
| ANE 功率/使用率 | `ANE0` 可订阅但始终为零；**没有受控 ANE 负载**，有效性未验证 | 未定 | 私有 | 推迟 |

IOReport 使用的是 `/usr/lib/libIOReport.dylib` 私有用户态接口；Apple 的 IOReport 数据结构文档不使这些采样函数成为公开 API。[Apple Mach API](https://developer.apple.com/documentation/kernel/1502854-host_processor_info)、[Apple 内存压力事件](https://developer.apple.com/documentation/dispatch/dispatch_source_type_memorypressure)、[SiliconScope 的 M1 Max 通道记录](https://github.com/kennss/SiliconScope/blob/main/docs/ioreport-channels.md)。

## A. P/E 映射

IODeviceTree 中 `logical-cpu-id` **0–1 为 `cluster-type E`，2–9 为 `P`**；`hw.perflevel0` 为 8 个 Performance 核，`perflevel1` 为 2 个 Efficiency 核。10 线程 CPU 负载下，10 个 Mach 核使用率的代表样本均约 100%；总量满足 `total=(8×P+2×E)/10`（样本误差不超过浮点舍入）。单线程负载使 P 组平均从约 9.6% 升至 18.3%，尽管其他后台工作使 E 组基线较高。CPU 总量基线约 17.1%、单线程约 22.6%、10 线程 100%。因此这台机器的核索引映射有设备树与行为双重证据；不能推广到所有 Apple Silicon 芯片。

## B. IOReport 订阅

以下数字是**逐组、筛选后的实际订阅数**。普通用户宿主运行时每组均完成枚举、订阅、创建首样本、创建后续样本及差分；代表样本没有 `INT64_MIN` 或负值。带 App Sandbox 权限的临时签名 `.app` 在相同机器上仍可枚举，但五组订阅均返回 `nil`。

| 组 / 子组 | 枚举 / 订阅 | 单位 | 宿主空闲与负载结果 |
|---|---:|---|---|
| `GPU Stats / GPU Performance States` | 1 / 1 | `24Mticks` | `GPUPH` 的 OFF/P1–P6 驻留随负载变化 |
| `Energy Model` | 162 / 19 | mJ、nJ 混合 | 筛选的 19 个通道中仅 `GPU Energy` nJ 随负载变化；CPU/DRAM mJ 通道为固定零 |
| `CPU Stats / CPU Complex Performance States` | 6 / 3 | `24Mticks` | ECPU、PCPU、PCPU1 驻留变化；不用于替代 Mach 核使用率 |
| `AMC Stats / Perf Counters` | 127 / 63 | B，另有无量纲计数 | DCS RD/WR 字节差分有效，GFX 在流式 GPU 负载下明显上升 |
| `PMP / DCS BW` | 1 / 1 | `events` | `RD+WR` 为 16、32、48 GB/s 等驻留桶；本机已有 AMC 字节计数，故不采用此估算回退 |

诊断性地订阅**全部 162 个 Energy Model 通道**并施加 10 线程 CPU 满载，连续 4 个样本依然只有 `GPU Energy` 非零。这排除了“仅选错 CPU 通道”的简单解释。GPU/CPU/带宽各组的差分 API 本身成功，不代表每一个通道都有效。

## C. GPU 验证

无 ML 软件安装；使用临时 Metal 计算着色器。`gpu-moderate` 加短暂间歇，`gpu-heavy` 连续计算，`gpu-bandwidth` 连续流式读写两个 64 MiB 缓冲区。基线并非完全静止，机器仍有后台 GPU 活动。

| 工作负载 | GPU 活跃率均值 | `GPU Energy` 均值 | `GFX DCS` 均值 | `Tg05` 均值 |
|---|---:|---:|---:|---:|
| 系统基线 | 37.1% | 0.29 W | 1.43 GB/s | 51.0°C |
| 中等计算 | 76.9% | 3.30 W | 1.75 GB/s | 54.1°C |
| 重计算 | 100% | 20.14 W | 1.70 GB/s | 58.4°C（另一轮为 61.1°C） |
| 流式内存 | 99.99% | 6.71 W | 215.19 GB/s | 60.2°C |

本机 `voltage-states9` 表为 0、388.8、486、648、777.6、972、1296 MHz。负载样本中非零的 GPUPH 状态落在 P1–P6；重计算样本全部落在 P6，对应 1296 MHz。频率按活动状态驻留加权：重计算均值 1296 MHz，流式内存均值约 1242 MHz。它不是瞬时频率，也没有独立频率仪器校准。GPU 100% 同时出现于计算型与带宽型负载，所以不能据此断言训练吞吐已经最佳。

## D. 功率

按通道单位将能量差分除以实际采样秒数：`GPU Energy` 为 **nJ**，重计算约 20 W、中等计算约 3.3 W、系统基线约 0.29 W。`GPU0` 和 `GPU SRAM0` 的 **mJ** 通道在这些负载下为零；没有把它们与 `GPU Energy` 相加。`CPU Energy`、E/P 簇和核 mJ 通道在 CPU 满载时为零，`DRAM0` 在约 215 GB/s 的流式 GPU 负载下仍为零，均标为**无效功率来源**。无 root 的 `powermetrics` 返回 `powermetrics must be invoked as the superuser`，因此没有独立功率参照；Apple 也注明其 SoC 功率是估算值。[powermetrics 手册](https://keith.github.io/xcode-man-pages/powermetrics.1.html)。

## E. 温度

普通用户宿主环境可打开 AppleSMC。经一次性键发现后，常规采样只读 `Tp05`（选定 P 核）和 `Tg05`（选定 GPU 传感器），均为 `flt` 编码。`Tp05` 从基线约 51.3°C 升至 CPU 满载约 60.0°C；`Tg05` 从约 51.0°C 升至 GPU 重计算约 61.1°C。诊断性扩展读取的 `Tp01`、`Tp09`、`Tg0D` 有合理值；`Tg0P` 的 SMC 结果码为 132，无数据。温度相对使用率变化较慢，建议 5 秒读取。由于负载按顺序执行，后续测试存在余热；数值不能视为精确的相同环境对照。

## F. 内存、swap 与压力

`HOST_VM_INFO64`、`hw.memsize` 在普通用户、Codex 沙箱与临时 App Sandbox 测试中均可用。代表样本：页大小 16 KiB，物理内存 68,719,476,736 B，压缩约 0.81 GB，连线约 3.14 GB；保留原始 VM 分类，避免用 `total-free` 冒充“应用已用”。Page-in/out、swap-in/out 是累计计数，需要差分才有速率意义。

普通用户宿主与 App Sandbox 的 `vm.swapusage` 返回 `used=0,total=0`；在 Codex 沙箱返回 `EPERM`。`kern.memorystatus_vm_pressure_level` 在宿主与 App Sandbox 返回 **1（normal）**，在 Codex 沙箱也返回 `EPERM`。这明确区分了 Codex 沙箱限制与普通用户权限；App Sandbox 在本机可读取这两个 sysctl。压力 DispatchSource 创建后，在各次正常状态运行中事件数始终为零；它**没有自动给出可信的初始状态**，也未通过人为制造高内存压力去测试变化事件。系统 `ProcessInfo.thermalState` 始终为 nominal。用户态压力值 1/2/4 与 XNU 内部压力枚举值不同。[XNU 压力通知文档](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md)。

## G. 带宽

`AMC Stats` 在本机 macOS 27.0 **可订阅且返回 `B` 字节差分**，与其他芯片在 27.0 上的失败记录不同。流式 GPU 负载下 `GFX DCS RD+WR` 均值约 215.19 GB/s；计算负载约 1.7 GB/s。代表性流式样本中 DCS 总量为 220.74 GB/s，逐请求方合计（排除 DCS 总量行）为约 220.63 GB/s，差约 0.05%；这支持读数的内部一致性。`DCS`、`DCS RD/WR`、各请求方 RD/WR 互有汇总关系，绝不可直接全数相加。带宽是**全机硬件计数**，没有独立仪器校准，也不能归因给单个训练进程。`PMP / DCS BW` 是粗桶驻留估算，本机不需要采用。

## H. ANE

`ANE0` mJ 通道可订阅，但系统基线、CPU 与 GPU 负载中均为零。没有现成受控 ANE 工作负载；因此未确认该通道在 ANE 真正工作时是否有效，也未得到 ANE 利用率。它不进入 v0.1。

## I. 监控器开销

组合 A=`PUBLIC_BASE`；B=A+GPU；C=B+POWER；D=C+两个已验证温度键；E=D+63 个 AMC 带宽通道。每次为独立进程，记录首末样本间的自身 CPU 时间，CPU% 表示**一个核心的百分比**。A/B/C 与 D/E 使用同一最终探针；D/E 曾额外用 6 个温度候选键测过一轮，表中采用优化后的 2 键结果。所有组合的样本/差分无报错，无常驻子进程。RSS 为约 8.7 MB（A）或 11.6–12.0 MB（B–E）。

| 组合 | 间隔 | 首末 CPU 时间 | 单核 CPU% | 平均采样延迟 | 订阅通道 | 包空闲唤醒 / 中断唤醒增量 |
|---|---:|---:|---:|---:|---:|---:|
| A | 1 s | 0.0101 s / 4 s | 0.253% | 0.50 ms | 0 | 0 / 4 |
| A | 2 s | 0.0038 s / 6 s | 0.064% | 0.26 ms | 0 | 0 / 3 |
| A | 5 s | 0.0033 s / 10 s | 0.033% | 0.31 ms | 0 | 0 / 2 |
| B | 1 s | 0.0127 s / 4 s | 0.317% | 2.02 ms | 1 | 0 / 4 |
| B | 2 s | 0.0061 s / 6 s | 0.102% | 1.16 ms | 1 | 0 / 3 |
| B | 5 s | 0.0081 s / 10 s | 0.081% | 2.36 ms | 1 | 0 / 2 |
| C | 1 s | 0.0200 s / 4 s | 0.501% | 4.38 ms | 20 | 0 / 4 |
| C | 2 s | 0.0156 s / 6 s | 0.260% | 4.26 ms | 20 | 0 / 3 |
| C | 5 s | 0.0119 s / 10 s | 0.119% | 5.75 ms | 20 | 0 / 2 |
| D | 1 s | 0.0156 s / 4 s | 0.389% | 3.83 ms | 20 | 0 / 4 |
| D | 2 s | 0.0106 s / 6 s | 0.176% | 3.24 ms | 20 | 0 / 3 |
| D | 5 s | 0.0117 s / 10 s | 0.117% | 5.13 ms | 20 | 0 / 2 |
| E | 1 s | 0.0239 s / 4 s | 0.598% | 6.04 ms | 83 | 0 / 4 |
| E | 2 s | 0.0185 s / 6 s | 0.308% | 5.85 ms | 83 | 0 / 3 |
| E | 5 s | 0.0131 s / 10 s | 0.131% | 7.10 ms | 83 | 0 / 2 |

采样期间每个配置有按节拍触发的定时唤醒；`proc_pid_rusage` 的包空闲唤醒计数均为零，**不能解读成进程没有唤醒**。中断唤醒增量如表，`getrusage` 上下文切换增量在结果 JSON 中。没有可靠的独立能耗或 Energy Impact 测量。短测、后台活动、JSONL 序列化和 Foundation 开销限制了将这些百分比直接预测为最终应用开销的精度；特别是 C/D 的差异小于环境波动。

## J. 建议 v0.1 保留的精确指标

总/P/E CPU 使用率；`HOST_VM_INFO64` 原始内存分类和 64 GiB 总量；swap 已用与 swap-in/out 差分；当前内存压力级别及变化事件；`ProcessInfo.thermalState`；GPU 活跃率与状态加权频率；仅来自 `GPU Energy` 的估算 GPU 功率；`Tp05` 与 `Tg05` 具名温度；`AMC Stats` 的 `GFX DCS RD/WR` 与 `DCS RD/WR` 全机带宽。建议用一个约 2 秒的共同节拍读取 CPU/GPU/带宽/功率，将温度和内存读数降至约 5 秒，热/内存压力变化靠通知。产品是否能使用私有指标必须先确定非 App Sandbox 的分发前提。

## K. 删除或推迟

CPU 功率、DRAM 功率、ANE 功率/利用率、PMP 估算带宽回退、未校准的系统功率、按进程归因、任何“训练饱和度”或“余量”分数。不要把失效通道显示成零；不要把 GPU 100% 显示为“有用性能已满”。

## L. 文件变更

- `experiments/.gitignore`：忽略编译二进制与本地 JSONL。
- `experiments/build.sh`：构建一次性 Objective-C 探针。
- `experiments/telemetry_probe.m`：独立后端采样、JSONL、受控 CPU/Metal 负载、自身开销计数。
- `experiments/run_experiments.py`：批量负载与采样间隔实验，保存摘要及代表样本。
- `experiments/README.md`：复现命令、权限和数据解释。
- `experiments/results/step2-2026-09-23.json`：本机结构化实测结果。
- `experiments/STEP2_REPORT.md`：本报告。

`/tmp` 中的原始长输出及临时 App Sandbox 测试包不是仓库文件；最终会清理。仓库此前为空，无文件被覆盖。

## M. 执行的测试

构建无警告；逐组 IOReport 枚举/订阅/首样本/差分；Codex 沙箱、普通用户宿主、带 App Sandbox 权限的临时签名 `.app` 三种运行条件；设备树核 ID；系统基线、单线程 CPU、10 线程 CPU、GPU 中等/重计算、GPU 流式内存负载；SMC 有效及失效键；全部 162 个 Energy Model 通道的 CPU 满载复查；5 组配置 × 1/2/5 秒开销矩阵；无 root `powermetrics` 参考可用性检查；结果 JSON 解析与内部一致性检查。负载进程均正常退出。

## N. 剩余不确定性

没有受控 ANE 工作负载或独立功率仪器；没有诱发内存压力变化或真实 swap 写入；未校准 IOReport 能量/带宽的绝对误差；没有长时间、睡眠唤醒后或系统升级后的稳定性测量；GPU 频率仅为按已见状态映射的区间估算；温度只是选定传感器，不是全芯片峰值。App Sandbox 的阻断在本机实测，未来若要上 Mac App Store，私有 API 路线还涉及 Apple 的公开 API 审核要求。[Apple App Review 2.5.1](https://developer.apple.com/cn/app-store/review/guidelines/)。
