# SiliconMeter v0.1.0

Draft release notes for the future GitHub Release. The artifact has not been published.

## English

### What's included

- Menu-bar CPU, GPU, temperature, estimated GPU power, and network upload/download monitoring, with a compact popover.
- Local SQLite v4 history and configurable 1-day, 7-day, 30-day, or Forever retention.
- English and Simplified Chinese interface, with saved language and primary-metric choices.

### Distribution and installation

- Apple Silicon arm64; macOS 13 or newer.
- **Unsigned, non-notarized open-source community build.** It has no Developer ID signature or Apple verification. The local ad-hoc code seal is a build detail only.
- Download `SiliconMeter-0.1.0-arm64.dmg`, open it, and drag SiliconMeter.app to Applications. If macOS blocks the first launch, try opening once, then use **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. See [Apple's instructions](https://support.apple.com/en-gb/102445).
- Launch at Login is not included in unsigned v0.1.

### Tested and limitations

- Tested on Apple M1 Max, macOS 27.0 build 26A428. Other Apple Silicon hardware is best effort.
- IOReport and AppleSMC are private interfaces and may change with macOS or hardware. GPU power is an estimate.
- Browser-downloaded copies may receive a Gatekeeper first-launch warning. Local build/copy testing does not reproduce every downloaded-app behavior.
- Source code is available for inspection and local builds; open source is not a safety certification.

## 简体中文

### 包含内容

- 菜单栏显示 CPU、GPU、温度、估算的 GPU 功耗，以及网络上传/下载速率；弹出窗口展示当前指标。
- 本地 SQLite v4 历史记录，可选择保留 1 天、7 天、30 天或永久。
- English 和简体中文界面，语言与主要指标选择保存在本机。

### 发布方式与安装

- 适用于 Apple Silicon arm64；需要 macOS 13 或更新版本。
- **未签名、未公证的开源社区构建。** 没有 Developer ID 签名，也未经 Apple 验证。本地 ad-hoc 代码封印仅是构建细节。
- 下载 `SiliconMeter-0.1.0-arm64.dmg`，打开后将 SiliconMeter.app 拖入“应用程序”。如果 macOS 阻止首次启动，先尝试打开一次，再到**系统设置 → 隐私与安全性 → 仍要打开**，并确认“打开”。参见 [Apple 说明](https://support.apple.com/zh-cn/102445)。
- 未签名的 v0.1 不包含“登录时启动”。

### 已测试环境与限制

- 已在 Apple M1 Max、macOS 27.0 build 26A428 上测试。其他 Apple Silicon 硬件仅尽力兼容。
- IOReport 和 AppleSMC 是私有接口，可能随 macOS 或硬件变化；GPU 功耗为估算值。
- 浏览器下载的副本在首次启动时可能出现 Gatekeeper 提示。本机构建和复制测试不能完全复现下载后的行为。
- 源代码可供检查和本地构建；开源不等于安全认证。
