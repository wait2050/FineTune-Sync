# Third-party notices / 第三方声明

FineTune Sync is a modified version of [Ronit Singh's FineTune](https://github.com/ronitsingh10/FineTune).
The complete application remains subject to the upstream [GPL-3.0 license](LICENSE).
FineTune Sync 基于 FineTune，保留上游署名；应用整体继续使用 GPL-3.0。
Modified by wait2050 on 2026-11-10 to add the independent MonoSplit output bridge.

## MonoSplit PCM transport

`FineTune/Audio/MonoSplit/MonoSplitPCM.c` and `MonoSplitPCM.h` originate from
[MonoSplit](https://github.com/wait2050/MonoSplit), Copyright (c) 2026 wait2050,
and are independently offered under [0BSD](FineTune/Audio/MonoSplit/LICENSE-PCM).
This grant applies to those standalone files. The FineTune adapter, application,
and its combined distribution retain FineTune's GPL-3.0 terms.

独立 PCM 传输文件采用 0BSD；该许可不替换 FineTune 衍生应用整体的 GPL-3.0 条件。
MonoSplit runs as a separate application over a shared-memory protocol.

## Swift Package Manager dependencies

Versions and source revisions are pinned in
`FineTune.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
This list includes testing dependencies, which are not all shipped in the app.
Dependencies retain their own terms and copyright notices.

| Dependency source | License notices |
| --- | --- |
| [fluidmenubarextra 1.5.1](https://github.com/wadetregaskis/FluidMenuBarExtra/tree/3ce81bd0e5ab0ae5b027076482f4bd86be30162c) | [Notices](third-party-licenses/fluidmenubarextra-1.5.1/) |
| [keyboardshortcuts 2.4.0](https://github.com/sindresorhus/KeyboardShortcuts/tree/1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27) | [Notices](third-party-licenses/keyboardshortcuts-2.4.0/) |
| [sparkle 2.8.1](https://github.com/sparkle-project/Sparkle/tree/5581748cef2bae787496fe6d61139aebe0a451f6) | [Notices](third-party-licenses/sparkle-2.8.1/) |
| [swift-custom-dump 1.3.3](https://github.com/pointfreeco/swift-custom-dump/tree/82645ec760917961cfa08c9c0c7104a57a0fa4b1) | [Notices](third-party-licenses/swift-custom-dump-1.3.3/) |
| [swift-snapshot-testing 1.18.7](https://github.com/pointfreeco/swift-snapshot-testing/tree/a8b7c5e0ed33d8ab8887d1654d9b59f2cbad529b) | [Notices](third-party-licenses/swift-snapshot-testing-1.18.7/) |
| [swift-syntax 602.0.0](https://github.com/swiftlang/swift-syntax/tree/4799286537280063c85a32f09884cfbca301b1a1) | [Notices](third-party-licenses/swift-syntax-602.0.0/) |
| [xctest-dynamic-overlay 1.8.1](https://github.com/pointfreeco/xctest-dynamic-overlay/tree/34e463e98ab8541c604af706c99bed7160f5ec70) | [Notices](third-party-licenses/xctest-dynamic-overlay-1.8.1/) |

AutoEQ correction data is provided by [AutoEQ](https://github.com/jaakkopasanen/AutoEq); see its [license](https://github.com/jaakkopasanen/AutoEq/blob/master/LICENSE). macOS system frameworks are supplied by Apple and are not redistributed in this repository.
