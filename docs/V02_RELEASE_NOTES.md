# SiliconMeter v0.2.0 — hardware compatibility candidate

## English

This is a local unsigned, non-notarized candidate. It has not been published to GitHub.

- CPU P/E activity uses the device's logical CPU IDs and cluster types, checked against the performance-level counts from macOS. The M1 Max model restriction and fixed 8P/2E layout have been removed. Each group shows the mean utilization of its actual cores; M4 Air's 4P/6E layout is included in the deterministic checks.
- CPU and GPU temperature choose a readable sensor from generation-specific M1–M4 candidates at launch. M4 GPU candidates include `Tg0G` and `Tg0H`; the UI uses general temperature labels instead of always claiming `Tp05`/`Tg05`. Each temperature is one selected sensor, not an average, per-core count, or die maximum.
- GPU activity accepts validated variable state counts. Missing or inconsistent frequency tables make frequency unavailable without suppressing valid activity. Multiple GPU frequency tables must agree.
- The latest local candidate is 0.2.0, build 3, with version display and Sparkle update controls; see [update setup and validation](V02_UPDATES.md). Hardware candidate build 2 is preserved separately. History retains schema v4 and the existing data location and preferences, with actual sensor keys and verified group sizes recorded in startup events. See the [legacy temperature-column semantics](HISTORY_SCHEMA.md#v020-sensor-and-topology-provenance).

Real hardware verification: M1 Max only. Simulated layouts and sensor responses do not prove M4 Air compatibility. M4 Air testing is required before public publication. Unknown or inaccessible metadata and sensors remain unavailable rather than reporting fabricated values. New chip generations may work for CPU grouping but need additional verified temperature sensor mappings.

Quit v0.1.0 before replacing it with the new App. Download candidates only from the maintainer; open the DMG and drag SiliconMeter.app to Applications. If macOS blocks launch, use System Settings → Privacy & Security → Open Anyway. No Developer ID signature or notarization is included.

## 简体中文

这是本地未签名、未公证的候选版本，尚未在 GitHub 发布。

- 性能核/能效核占用改为按设备实际逻辑核心编号和核心类型分组，并与 macOS 提供的核心数量交叉检查；移除了 M1 Max 型号限制和固定的 8P/2E 布局。每组显示实际核心的平均占用；确定性测试包含 M4 Air 的 4P/6E 布局。
- 启动时从 M1–M4 各代的候选温度传感器中选择可读的一项，新增 M4 GPU 的 `Tg0G`、`Tg0H` 等候选。界面改用“CPU 温度”“GPU 温度”。每项温度代表一个选中的传感器，不是核心数量、平均值或全芯片最高温度。
- GPU 活跃比例支持经过验证的可变状态数量。缺失或不一致的频率表只影响频率显示，不再导致有效的 GPU 活跃比例同时失效。多个 GPU 频率表必须一致。
- 最新本地候选为 0.2.0、构建号 3，加入版本显示及 Sparkle 升级控件，参见[升级配置与验证](V02_UPDATES.md)；硬件候选构建号 2 另行保留。沿用 SQLite v4、原数据位置和偏好设置；启动事件记录实际传感器键及已验证的核心组大小，旧温度列名的含义见[表结构说明](HISTORY_SCHEMA.md#v020-sensor-and-topology-provenance)。

目前仅在 M1 Max 上完成实机验证。模拟布局和传感器测试不能代替 M4 Air 实测；公开发布前仍需在 M4 Air 上确认。未知或无法读取的核心信息和传感器继续显示不可用，不填造数据。新一代芯片可能满足动态 CPU 分组条件，但温度仍需要经过核对的传感器映射。

升级前先退出 v0.1.0，再将 DMG 中的 SiliconMeter.app 拖入“应用程序”。如首次启动被阻止，使用“系统设置 → 隐私与安全性 → 仍要打开”。本版本没有 Developer ID 签名或 Apple 公证。

## Sensor mapping reference

Temperature identifiers were cross-checked against the [Stats project's sensor definitions](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift). SiliconMeter uses its own bounded selection and validation implementation; sensor availability still depends on the actual hardware and macOS version.
