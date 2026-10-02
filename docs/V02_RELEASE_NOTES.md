# SiliconMeter v0.2.0

## English

Apple Silicon menu bar monitoring with broader hardware detection and signed in-app updates. Version **0.2.0**, build **3**. Requires an Apple Silicon Mac running macOS 13 or newer.

### Added

- Current version beside the popover title, with the build number in its tooltip.
- **Check for Updates…** and optional daily automatic checks using Sparkle. Downloads and installation require your choice; system profile submission is disabled.
- Ed25519 verification of both the update feed and archive before extraction. Future releases can be installed from inside the App.

### Improved

- CPU performance/efficiency activity uses validated logical CPU IDs, cluster types and macOS core counts. The fixed M1 Max 8P/2E restriction is removed; tests include M4 Air’s 4P/6E layout. Each group shows the average utilization of its actual cores.
- CPU/GPU temperature chooses a readable sensor from M1–M4 candidates at launch. General temperature labels replace the fixed Tp05/Tg05 labels. Each reading represents one selected sensor, not a die maximum or average.
- GPU activity supports validated variable state counts. Missing or inconsistent frequency tables affect frequency availability while preserving valid activity.
- SQLite schema v4, existing history location and preferences are retained. Startup events record actual sensor keys and verified core group sizes; see [history semantics](https://github.com/Trojon99/SiliconMeter/blob/main/docs/HISTORY_SCHEMA.md#v020-sensor-and-topology-provenance).

### Install and upgrade

1. Quit the older SiliconMeter App.
2. Download `SiliconMeter-0.2.0-arm64.dmg` and drag **SiliconMeter.app** to **Applications**.
3. If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway**, then confirm Open.

**v0.1.0 needs this one manual installation:** it has no updater. Starting with v0.2.0, use Check for Updates for later releases. This is an **unsigned, non-notarized community build** without an Apple Developer ID identity. Update signatures do not replace Apple signing or notarization.

### Verification and limitations

Real hardware tested: **M1 Max**. M4 Air core layouts and M1–M4 sensor responses are covered by deterministic tests; **M4 Air has not been verified on a real device**. Unknown or inaccessible metadata/sensors remain unavailable. GPU frequency and power are estimates. Private IOReport/AppleSMC behavior may change across hardware and macOS releases.

Signed update tests use real Sparkle against isolated temporary Apps, including damaged-feed/archive rejection, production-binary installation to a non-running temporary App, and quit/replacement/relaunch of a harmless running AppKit fixture. Standard dialogs, updating a live running App with restart, and browser-download Gatekeeper still require manual acceptance. See [verification details](https://github.com/Trojon99/SiliconMeter/blob/main/docs/V02_UPDATES.md).

## 简体中文

Apple Silicon 菜单栏监控工具，加入更广的硬件识别与签名应用内升级。版本 **0.2.0**，构建号 **3**；需要 Apple Silicon Mac 和 macOS 13 或更新系统。

### 新增

- 标题旁显示当前版本，鼠标提示显示构建号。
- 基于 Sparkle 的**检查更新…**和可选的每日自动检查；下载、安装需要用户选择，关闭系统信息上报。
- 版本清单及更新包均通过 Ed25519 签名验证后才使用，并在解压前验证安装包。后续版本可在 App 内安装。

### 改进

- 性能核/能效核占用按经过验证的逻辑核心编号、核心类型及 macOS 核心数量分组，移除固定的 M1 Max 8P/2E 限制；测试包含 M4 Air 的 4P/6E 布局。每组显示其实际核心的平均占用。
- 启动时从 M1–M4 候选中选择可读的 CPU/GPU 温度传感器，使用通用温度名称，替换固定 Tp05/Tg05 标签。每项是一个选中传感器的读数，不是全芯片最高温度或平均温度。
- GPU 活跃比例支持经过验证的可变状态数量；缺失或不一致的频率表只影响频率显示，保留有效的活跃比例。
- 继续使用 SQLite v4、原历史目录及偏好设置。启动事件记录实际传感器键和已验证的核心组大小，参见[历史字段含义](https://github.com/Trojon99/SiliconMeter/blob/main/docs/HISTORY_SCHEMA.md#v020-sensor-and-topology-provenance)。

### 安装与升级

1. 退出旧 SiliconMeter。
2. 下载 `SiliconMeter-0.2.0-arm64.dmg`，将 **SiliconMeter.app** 拖入**应用程序**。
3. 首次启动如被阻止，使用**系统设置 → 隐私与安全性 → 仍要打开**，再次确认打开。

**v0.1.0 需要先手动安装这一次**，因为旧版没有更新器；从 v0.2.0 开始，后续发行版可通过“检查更新”安装。本版是**没有 Developer ID 签名、未经 Apple 公证的社区构建**；更新签名不等同于 Apple 签名或公证。

### 验证与限制

已实测硬件：**M1 Max**。确定性测试覆盖 M4 Air 核心布局及 M1–M4 传感器响应；**尚未完成 M4 Air 实机验证**。未知或无法读取的核心信息和传感器继续显示不可用。GPU 频率、功耗为估算值；IOReport/AppleSMC 私有接口可能随硬件和系统更新而变化。

签名更新测试使用真实 Sparkle 和隔离临时 App，包含损坏清单/安装包的拒绝、未运行临时 App 的生产程序安装，以及无遥测 AppKit 测试 App 的退出、替换和重启。标准更新窗口、正在运行 App 的升级与重启、浏览器下载后的 Gatekeeper 仍需人工验收。参见[详细验证记录](https://github.com/Trojon99/SiliconMeter/blob/main/docs/V02_UPDATES.md)。

## SHA-256

`SiliconMeter-0.2.0-arm64.dmg`

```text
c4e91b28caaa636aca33adbf09199a6905cf622756cc2c6b3254bdf3af1bdb50
```

Temperature identifiers were cross-checked against the [Stats sensor definitions](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift). Availability depends on the actual device and macOS version.
