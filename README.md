# ProCamera for iOS

由 Android 版 ProCamera（Kotlin + Camera2 分层骨架）移植而来的 iOS 版本：
Swift + SwiftUI + AVFoundation，无第三方依赖。

## 架构对应关系

| Android 版 | iOS 版 | 职责 |
|---|---|---|
| hal / SensorProber + DeviceCapability | `DeviceCapability.swift`（CapabilityProbe） | 开机探测镜头/ProRAW/最大尺寸，生成能力画像并分级（PRO / FULL / STANDARD / BASIC） |
| capture / SessionController | `CameraManager.swift` | 会话配置、镜头切换、3A（点按对焦测光、EV 补偿、变焦）、拍照/录像编排 |
| domain / PhotoSaver | `PhotoSaver.swift` | 照片/录像存入系统相册并归档到「ProCamera」相簿 |
| ui / MainActivity + ViewModel | `ContentView.swift` + `CameraPreview.swift` | 预览、网格、镜头按钮（按硬件能力出现）、快门、能力画像弹层 |

自适应思路与 Android 版一致：同一份代码，界面功能随设备能力增减——
没有超广角就不显示 0.5x 按钮，没有闪光灯就不显示闪光灯开关，永远保证能出图。

## 功能（v1）

- 实时预览、点按对焦/测光、双指缩放
- 后置多镜头切换（0.5x / 1x / Tele，按实际硬件显示）、前后摄像头切换
- 闪光灯（关/自动/开）、EV 曝光补偿滑杆、三分法网格
- 拍照：最高分辨率输出，存入相册并归档到 ProCamera 相簿
- 录像：带声音，存入同一相簿
- 左上角徽章显示能力等级，点按查看完整能力画像

## 构建（GitHub Actions，无需本地 Mac）

1. 本仓库的 `.github/workflows/build.yml` 在 macOS 构建机上运行：
   XcodeGen 生成工程 → xcodebuild 关闭签名编译 → 打包未签名 `ProCamera.ipa`。
2. 构建产物在 Actions 运行页的 Artifacts 里下载。
3. 未签名 IPA 用 LiveContainer / SideStore 以个人证书签名后安装。

本地构建（有 Mac 时）：`brew install xcodegen && xcodegen generate` 后用 Xcode 打开。

## 已知 TODO（诚实标注）

- 夜景多帧融合（与 Android 版同一未竟项，管线位置已预留思路，未实现）
- ProRAW 拍摄：能力画像已能探测支持与否，拍摄开关未做（目标机 iPhone 12 不支持 ProRAW）
- 录像方向/防抖精细控制未做（v1 用系统默认）
- App 图标未做（侧载自用，暂用系统默认图标）
