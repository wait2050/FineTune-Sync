# FineTune Sync 1.9.0-r5 — MonoSplit 联动 / MonoSplit output integration

## 中文

把 MonoSplit 当作 FineTune 中的一台输出设备：FineTune 负责应用路由、音量和静音，MonoSplit 保留独立调音窗口、音箱配置和三路分频 / EQ / 延迟。

- 新增 MonoSplit 逻辑输出、共享内存 PCM 桥接、断开回退和打开独立调音窗口的入口。
- 可单独给一个应用使用 MonoSplit，也可与其他独立音箱一起选择。
- 保留多设备延迟、总音量、设备 EQ、AutoEQ、应用 EQ 等原有功能。
- 新增中英文联动指南、英文提示及中文翻译、依赖许可声明。

下载 `FineTune-Delay-macOS.zip`，退出其他 FineTune 版本后打开 `FineTune Delay.app`。
需要 Apple Silicon Mac、macOS 15.4+，以及 [MonoSplit 0.5.0 或更新版本](https://github.com/wait2050/MonoSplit/releases/latest)。
在 MonoSplit 菜单栏中启用“FineTune 输入（作为独立设备）”并启动，再在 FineTune 选择 MonoSplit。

MonoSplit 将立体声混为单声道；桥接约增加 40 ms 预缓冲。完整应用保留上游 GPL-3.0；独立 PCM 传输文件另有 0BSD 许可。应用本地签名，未经过 Apple 公证。

## English

Use MonoSplit as one output inside FineTune. FineTune manages application routing, volume and mute; MonoSplit retains its independent tuning window, profiles and three-way crossover / EQ / delay processing.

- Adds a logical MonoSplit output, shared-memory PCM bridge, disconnect fallback and a tuning-window button.
- Route one app to MonoSplit or select it alongside other independent speakers.
- Retains multi-output delay, master volume, device EQ, AutoEQ and app EQ.
- Includes Chinese/English integration guides, localized prompts and third-party license notices.

Download `FineTune-Delay-macOS.zip`, quit other FineTune editions, then open `FineTune Delay.app`.
Requires Apple Silicon, macOS 15.4+, and [MonoSplit 0.5.0 or later](https://github.com/wait2050/MonoSplit/releases/latest).
Enable “FineTune 输入（作为独立设备）” and start processing in MonoSplit, then select MonoSplit in FineTune.

MonoSplit mixes stereo into mono. Its bridge adds about 40 ms of preroll buffering. The complete FineTune derivative retains GPL-3.0; the standalone PCM transport files also have an independent 0BSD grant. The app is locally signed and not Apple-notarized.

## Source / 对应源码

The exact source is available from this release tag's GitHub source archives. Build instructions are in `OUTPUT_DELAY.md` and `scripts/build-delay-edition.sh`; SPM dependency revisions are pinned in `Package.resolved`. The app bundle includes GPL-3.0 and dependency notices under `Contents/Resources/`.
