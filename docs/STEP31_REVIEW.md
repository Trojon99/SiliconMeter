# Step 3.1 — 独立架构审查与生产 App 稳定性

完整证据：[长测轨迹](results/step31-2026-09-23.jsonl)、[可重算摘要](results/step31-2026-09-23-summary.json)、[辅助检查](results/step31-auxiliary.json)、[普通构建对照](results/step31-release-comparison.json)。

证据基线为 `phase3/menu-bar-v0.1` 的 `5058524`，此前冻结实验提交为 `3bd75eb`。审查从当前仓库恢复上下文。历史 `experiments/` 文件未改动；Step 2.6 JSONL 重算结果与已保存 summary 逐字节一致。

## A. 独立架构审查

| 项目 | 审查结果 |
|---|---|
| 实际窗口 | CPU busy/total tick 比例和 GPU active/total residency 为无量纲区间比例，不除 nominal interval。CPU/GPU 记录各自 CLOCK_MONOTONIC 窗口；GPU nJ→W、swap pages→pages/s 分别除本组实际窗口。 |
| 延迟/失败/恢复 | IOReport 失败丢弃 previous；下一成功样本只建立 baseline。delta nil/负数/sentinel/单位错误均拒绝，>30 s 标 stale 并重建。CPU/VM 失败重建，过长窗口不出速率。CPU 回退修复后拒绝异常大差分，同时保留小的 uint32 wrap。 |
| Mach | host right 在 init 获取一次并复用，shutdown/dealloc 释放。host_processor_info 的正常与异常路径均释放返回数组。VM 结构在栈上。测试自身 mach_port_names 的两块返回数组亦释放。 |
| autorelease | 初始化、每 tick、压力刷新均有池；采样结果仅短暂跨队列，到主线程转换成最新 typed snapshot；无数组保存历史。测试 JSON 输出也有池。 |
| IOReport | 初始化选唯一 GPUPH/GPU Energy；采样再检查唯一性、单位、完整 OFF/P1–P15、重复状态、负/sentinel 与频率表覆盖。只有 GPU Energy nJ 产生估算 W，非正常状态无数值。 |
| SMC | 单连接，唯一 Tp05/Tg05，首次成功元信息缓存；每次只 command 5，读失败不伪造 0，shutdown 关闭连接。测试确认 24 次温度读取只有两次 command 9。 |
| P/E | 启动同时验证 M1 Max、10 核、8P/2E sysctl 与设备树 logical-cpu-id/cluster-type；失败只关闭 P/E，Mach total 保留。 |
| snapshot | measured/estimated/unavailable/invalid/stale、unit/source/reason/window 保留；失效 value 缺失。修复 VM 失败覆盖不完整和使用 wall clock 判过期的问题。 |
| bridge/所有权 | 每组一次采样，小字典转 typed value；合并 tick 的快慢结果只发布一次。timer、observer、压力回调和 UI closures 均使用 weak self。压力回调跨队列读取改为 atomic copy。 |
| 调度 | 一个 utility 串行队列、一个 one-shot DispatchSourceTimer；完成后 +2 s，100 ms leeway，不 catch-up；每第三 tick 慢采样，启动额外一次 slow。一个 thermal observer 和一个压力事件源；UI 不读硬件。start 防重复。 |
| UI | title 未变不写 NSStatusItem；popover 关闭不格式化/更新生产弹窗。打开时只用当前 snapshot。正常生产没有测试 JSON、交互驱动或资源自测。 |

## B. 与 Step 2.6 probe 的开销差异

Step 2.6 的 2 s 三段为 0.324%–0.363% 单核、RSS 12.17→12.21 MB、host refs=2。它每 tick 同时读取包括 63 个带宽通道的完整实验组合。生产后端只保留两个 IOReport 通道，而且慢采样每三 tick 才做一次，因此不能把两者 CPU 差额直接认作 Swift bridge 成本。

当前 backend-only 16.048 s 对照消耗 0.015009 CPU s，即约 0.094% 单核，RSS 10.699 MB。此短测不含 AppKit，也不等同严格的逐项成本归因。Step 3.0 提供的约 0.5% 单核、47.6–50 MB 是先前短测参照，不能替代本轮证据。

本轮首次 UI 使用前约 52 MB，首次 AppKit 控件/弹窗使用后阶跃到约 85 MB。vmmap 在首次 UI 周期附近显示 IOSurface 约 12.7 MiB、图形 IOAccelerator 约 4.2 MiB、Malloc Small resident 约 15.8 MiB；这些是区域信息，不应与 RSS 简单相加，physical footprint 也不等于 RSS。3 s sample 的主线程绝大部分在 Mach event wait，偶见 AppKit layout；未发现忙循环。对 runtime、AppKit、bridging、allocator 的精确 CPU 百分比拆分不可得。证据支持 UI/框架的一次性加载与缓存解释主要 RSS 差异；是否泄漏以之后的平台/重复交互行为判断。

## C. 长测配置与证据边界

目标机器 Apple M1 Max，10 核、64 GiB、arm64、macOS 27.0 (26A428)，普通用户非 App Sandbox。测试版直接编译 production Swift/Objective-C，增加 STEP31_REVIEW 宏。一个 App PID 连续运行，30 s 预热，随后 Idle/GPU load/Recovery 各约 600 s。Metal 是已冻结 probe 的 `--load gpu-heavy --duration 598`，由外部 runner 启动为 App 的 sibling，不装 ML runtime。

观测钩子复用已有 tick，不加 timer/collector；它记录 raw readings、窗口/延迟、getrusage/proc_pid_rusage、host refs、port names、threads、children，再输出 stdout，由 Python 写审查证据。process CPU 包含此诊断工作；sampling latency 不含 self-observation/JSON/UI。统计只数 fresh readings，避免快照缓存重复计数。slow_count 含启动的 1 次慢采样，其 raw 字典未作为 tick 输出；启动阶段的预期 baseline unavailable 不算硬件失败。

每阶段两段约 60 s 反复开关并按真实 NSButton action 轮换四主指标，两段约 60 s 保持打开，其余关闭。Test variant 不保存 primary UserDefaults，以免改变用户设置。正式 App 的此设置写入仍保留。自动化通过同一 toggle selector/control action 执行，不是人工鼠标点按。

长测开始后发生两项修复：固定高度 470→500，使 Quit 按钮完整可见；IOReport 初始化后释放两个输入字典。长期二进制保留旧高度与这两个一次性遗留引用。最终版本另做真实 UI smoke/布局检查、普通构建短测、订阅所有权检查，以及带 AddressSanitizer 的 100 次 backend 初始化/采样/关闭循环；采样循环、调度和质量路径与长测二进制一致。精确差异保存在 `results/step31-post-start-fixes.patch`，已与长测 metadata 哈希核对。JSONL metadata 保存了实际受测源文件和二进制哈希，不能将其误称为最终无宏二进制的 30 分钟实测。

## D. Idle 阶段

同一 App PID **74741** 总运行 **1832.589 s**，输出 873 个连续 fast tick，slow 总数 292（含启动 1 次）。进程正常退出。下表 duration/CPU 采用该阶段第一、最后观测值相减，未把相邻阶段边界间约 2 s 重复归入两段；正式阶段合起来覆盖约 30 分钟。

| 阶段 | 观测跨度 s | fast / slow trace 样本 | CPU s / 单核 % | GPU Active 均值 | 估算 GPU W 均值 | Tg05 均值 / 最高 °C |
|---|---:|---:|---:|---:|---:|---:|
| Idle | 596.259 | 285 / 95 | 3.869825 / 0.649% | 39.76% | 0.260 | 49.57 / 52.66 |
| GPU load | 599.959 | 287 / 96 | 1.738004 / 0.290% | 99.61% | 20.420 | 76.49 / 82.66 |
| Recovery | 600.572 | 287 / 96 | 3.091079 / 0.515% | 39.80% | 0.280 | 50.89 / 69.29 |

Idle 指没有受控 GPU workload，仍有桌面/后台 GPU 活动。该阶段多数时间关闭 popover；两轮密集交互包含在整段 CPU 内。早期另运行了短时独立 smoke、vmmap 和 3 s sample，因此不是完全隔离的微基准；App CPU 数值只计自身进程。

## E. GPU load 阶段

Metal sibling PID 75206 于 elapsed=630.018 s 启动，结束于下一次检查 elapsed=1229.977 s，退出码 0，共 146,222 次 Metal dispatch。配置 598 s，实际观察边界约 600 s。GPU Active 中位数 100%，加权活动频率中位数 1296 MHz，估算功率中位数 20.618 W，最大 21.287 W；Tg05 最高 82.664°C。边界的首个混合窗口仍包含启动前读数，阶段均值据实保留，没有为了使结果更好而删除。系统 thermal 始终 Nominal。

## F. Recovery 阶段

无 App 重启。GPU Active 均值恢复到 39.80%，估算功率均值 0.280 W；温度逐渐回到约 49°C，体现热惯性。末段 RSS 85,671,936 B，与首轮 UI 后平台接近；CPU 在关闭弹窗的稳定区间为单核 0.214%，未出现永久抬升。


## G. RSS 随时间

单位 MB 为 10^6 B，表中分钟从 30 s 预热结束算起；RSS 不是 physical footprint。

| 正式测试分钟 | fast 样本 | 首→末 RSS MB | RSS 范围 MB | 平均单核 CPU |
|---|---:|---:|---:|---:|
| 0–5 | 143 | 52.314 → 84.787 | 52.314–84.967 | 0.747% |
| 5–10 | 142 | 84.787 → 85.361 | 84.787–85.492 | 0.553% |
| 10–15 | 143 | 85.361 → 85.541 | 85.361–85.918 | 0.265% |
| 15–20 | 144 | 85.541 → 85.803 | 85.541–86.049 | 0.316% |
| 20–25 | 142 | 85.836 → 85.656 | 85.574–85.967 | 0.523% |
| 25–30 | 143 | 85.656 → 85.672 | 85.623–85.983 | 0.512% |

首次打开 UI 导致 52→85 MB 一次性阶跃。之后峰值范围由 UI/allocator 波动解释，不与每次 sample 同步单向累积：elapsed 600–750 s 的关闭窗口为 85.361–85.393 MB；900–1050 s 为 85.541–85.574 MB；1500–1650 s 为 85.623–85.705 MB；最后 1800–1832.6 s 的 **16 次样本全部恰为 85,671,936 B**。最后两个 5 分钟 bin 末值仅相差 16,384 B。观测 RSS 最大 86,048,768 B，内核 `ru_maxrss` 高水位 **86,130,688 B**。没有观察到采样次数相关的持续 RSS 增长；有限运行无法排除极小或更长期泄漏。

## H. CPU 随时间和 UI 状态

全部首末观测之间消耗 **8.815420 CPU s / 1830.348 s = 0.482% 单核**，包括测试 JSON/资源观测与密集 UI 交互。各 5 分钟 CPU 如上表。以下排除开关过渡、只聚合同类相邻观测区间（具体时间窗见 analyzer），不是全阶段占比：

| 阶段 | 关闭稳定 % | 保持打开稳定 % | 连续切换 % |
|---|---:|---:|---:|
| Idle | 0.300 | 0.563 | 1.702 |
| GPU load | 0.106 | 0.161 | 0.984 |
| Recovery | 0.214 | 0.550 | 1.360 |

GPU 阶段读数/菜单栏字符串较稳定，而 idle/recovery 的系统读数更常变化，且 primary metric 随试验轮换。因此这些数字支持“关闭后没有永久升高”，不能单独归因于 popover 或 bridging。保持打开也没有引入硬件采样。

最终普通构建无 STEP31_REVIEW 钩子、popover 关闭，独立 PID 76292，预热 30 s 后外部 libproc 记录 **0.165432 CPU s / 60.123 s = 0.275% 单核**；RSS **51,855,360→51,888,128 B**，线程始终 4。这里没有首次弹窗缓存，故不应直接与打开过 UI 的 85.7 MB 比较。该短测支持最终常驻路径开销适合菜单栏应用，并说明长测诊断/主动 UI 操作的额外成本；不同环境和选中指标使它不能精确分离每项成本。


## I. Mach/resource lifecycle

873 次自测的 host send refs 全部为 **2**，App child count 全部为 **0**。port names 首次 UI 前约 191–198，AppKit UI 创建后通常 262–270，交互瞬时最高 286；最后 16 次均为 **263**，未逐轮或逐样本递增。线程 4–17，交互外可回到 4–5；临时 AppKit/dispatch worker 不等于 collector 实例。

三个阶段 interrupt wakeup 增量依次为 1861、1591、1290；package-idle wakeup 增量为 21、24、15。这些带 UI/诊断的 OS 类别计数不能与 CLI 的“每样本一个 interrupt wakeup”一一等同；完整 wakeups、Energy Impact、package power **unavailable**。未估算。

最终修复版另做真实 backend 的 10 次预热 + 100 次 init/sample/shutdown，host refs 2→2、port names 21→21。测试对象的 host/SMC/订阅生命周期没有随实例数累积。


## J. UI 交互生命周期

长测 **189 次 toggle、168 次四主指标切换**，覆盖 CPU/GPU/Temperature/GPU Power，含六段保持打开的区间。所有 873 次 title 与当前 snapshot 匹配，采样序号 1–873 无间断/重复，slow cadence 全部满足 `1+tick/3`。开关/切换动作不调用 service.start 或创建 backend；代码只有一个 thermal observer、一个 telemetry timer。独立测试重复 start 只发布一次初始状态、7.2 s 内恰有 tick 1/2/3；人工 thermal 通知仅回调一次，stop 后不再回调，service 弱引用归 nil。

文字变化检查和标题相等保护保留。最终 500 pt 弹窗真实 smoke：opened/switched/closed/accessory/cpu/gpu 全 true；Quit frame 从 y=-9 改为 y=21，完整落在 500 pt 容器内。


## K. Telemetry correctness

GPU 显示全机 Active，频率为 Weighted freq. 且值带 estimated，功率带 estimated。温度组明确为 sensors，CPU Tp05 / GPU Tg05 不是芯片最高结温。Memory 保留原始 VM 分类、独立 pressure/swap，不推导训练可用内存。合法 idle=0 与 unavailable/invalid/stale 区分；频率无活动驻留时 unavailable，不用 0 MHz 伪装实测。菜单栏紧凑数字需结合已选指标与 popover 解释，其无效值显示 —；不把菜单栏简写当独立、完整的质量元数据。

## L. 发现与修复

1. VM 读取失败只覆盖 physical/free：其余旧快照短期仍可呈现 measured。现在覆盖全部 VM 分类与 swap rate，并保留独立 hw.memsize；有失败/恢复测试。
2. freshness 使用 Date：时钟修改可提前/延后 stale。现在使用采集时的 systemUptime 并跨队列传递，保留 Date 作观测时间；有时钟/排队旧值测试。
3. CPU 计数回退按 uint32 自动解释为巨额正数：现在拒绝 >INT32_MAX 的短窗口增量，小的正常 wrap 仍有效；注入 rollback/wrap 验证。
4. fast/slow 重合时分别 deliver：慢 tick 重复发布/render。现在先合并再一次 deliver；快慢次数与 tick 序列验证。
5. start 无防重复：当前 App 只调用一次，但意外重复会留下 timer/observer。加一次性 guard；真实调度、通知投递、stop 后 observer 移除与弱引用释放测试。
6. pressureChanged 是跨队列 nonatomic ARC block 属性：shutdown 写 nil 与压力 handler 读取有竞争。改 atomic copy，仍采用 weak capture，queued 工作经过 stopped 检查。
7. UI 没有明确 weighted frequency / sensor 命名：只改文字保留测量语义。布局检查发现 Quit frame y=-9，固定高度增加 30 pt 后 y=21，全部控件在界内；同一实际 UI smoke 通过。

8. 静态分析提示 IOReport desired 可能泄漏，独立加保护引用并排空 autoreleasepool 后证实接口不消费输入：修复前 count=2，释放调用方引用后 count=1（只剩测试保护引用）。原注释相反且错误，已更正并加 CFRelease。正常订阅和沙箱拒绝两条路径均通过；100 次真实 backend 生命周期 host refs=2→2、port names=21→21，AddressSanitizer 无错误。这是每次 init 两个字典的一次性泄漏，不是随采样增长。冻结实验的相同假设未改动。

## M. 剩余风险

- 仅本机/本 OS 的约半小时证据，不是多日、跨系统版本或其他 SoC 保证。
- IOReport/SMC/设备树私有 ABI 与所有权契约仍有系统升级风险；本轮不更换后端、不加入 sandbox/签名发布流程。
- 故障注入证明软件恢复路径，不等于真实硬件断连、睡眠唤醒或严重系统压力的实测。没有制造非零 swap、内存压力/thermal transition；通知注入只测 observer 生命周期。
- Energy Impact、完整 wakeup 数量、package power 均 unavailable。记录的 interrupt/package-idle wakeup 是不同 OS 计数类别，不能相加当全部 wakeups，也不能由其推算功率。
- GPU power / frequency 未外部校准，GPU Active 不是算力饱和率。
- 主线程或同步私有采样 API 无限阻塞未做 watchdog；过期状态在下一次 render 求值，界面没有独立轮询定时器保证阻塞期间刷新。未来 history consumer 也应检查观测时间，不能只看静态 quality。
- 带诊断 App 的 CPU/RSS 包含外部审查钩子影响；普通无宏短测用于交叉检查，不能精确消除环境波动。

## N. 是否适合进入 history logging

满足本步骤的门槛：无可观测的采样次数相关 RSS 增长，host 引用稳定、UI 后 port 平台稳定，无重复 timer/collector/observer 证据；超过 30 分钟同进程采样稳定；GPU load/recovery 合理；失效/估算语义保留；常驻 CPU 较低。可作为 history logging 的基础，但下一阶段必须保留观测时间、窗口和质量，不能把缓存快照重复当新样本。

本轮没有实现或自动开始 Step 3.2。

## O. Files changed

- `app/ComputeMonitor.swift`、`app/TelemetryBackend.h`、`app/TelemetryBackend.m`：最小正确性/生命周期/UI 修复，编译期审查钩子。
- `README.md`、`docs/STEP3_ARCHITECTURE.md`、`docs/STEP31_REVIEW.md`：入口、架构修订、独立审查。
- `tests/`：两份测试钩子、build/runner/analyzer、故障/语义/生命周期/所有权检查、普通构建对照、UI 布局检查及复现说明。
- `docs/results/step31-2026-09-23.jsonl`、对应 `-summary.json` 与 `.stderr.txt`：完整 873-tick 轨迹、可重算摘要与 Metal 退出信息。
- `docs/results/step31-auxiliary.json`、`step31-post-start-fixes.patch`、`step31-release-comparison.json`：辅助验证、长测后精确差异、普通构建对照。
- `experiments/` 所有历史源码/结果保持原样。

## P. Tests executed

1. `sh app/build.sh`、`sh tests/build-review.sh`：生产/诊断版构建通过；最终普通二进制不含 Step31 review 符号。
2. `sh tests/run-checks.sh`：**92 backend + 25 Swift/service 断言通过**。
3. backend 故障测试、IOReport 所有权检查、100 次真实 backend 生命周期：AddressSanitizer 未报告内存访问错误。所有权在普通宿主及订阅被沙箱拒绝时均通过。
4. Clang static analyzer：发现并修复 desired 初始化泄漏后输出为空。
5. 真实 AppKit UI smoke/布局检查：修复前后均跑，最终全部通过；没有把离屏 hosted-control 位图当完整屏幕截图。
6. 同一 PID 873 tick / 1832.589 s 长测；原始轨迹验证 PID、时长、连续序号、快慢 cadence、失效无值、GPU estimated、host refs、children、四模式与 GPU load/recovery 全部通过。失败/invalid/stale/reset 各 **0**；仅 `pressureLastEvent:no_event` 291 个 unavailable，符合没有压力通知的语义。
7. 时间验证：正式 fast tick 最小 2.00284 s，无 catch-up；中位数约 2.100 s，最长 2.11632 s；首 tick 含初始化为 2.26036 s。GPU power 窗口 6.14310–6.32095 s，中位数 6.30083 s。采样延迟 idle/load/recovery 中位数 2.918/0.764/2.681 ms，最大 12.128/4.409/16.606 ms。
8. backend-only 普通宿主 8 样本 smoke；普通无宏构建外部对照；libproc Mach timebase **125/3** 已与内部 getrusage 校准（7.367190 s vs 相邻样本 7.365682 s），没有误把 Mach ticks 当 ns。
9. Step 2.6 全部 281 行解析并重算摘要，与历史 summary `cmp` 完全一致；历史 trace SHA-256 `301fb7193d40bab4644220ffe5c892b3a52808f4c26e812c86cb6b8ce4b0e452` 未改变。
10. Python 编译检查、shell 语法检查、`git diff --check`；提交前检查历史实验无 diff。


READY FOR STEP 3.2
