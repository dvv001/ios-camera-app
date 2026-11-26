import AVFoundation

/// 硬件能力等级 —— 对应 Android 版 DeviceCapability.hardwareLevel 的分层思路：
/// 同一份代码按设备能力自动分级，功能随等级增减，永远保证能出图。
enum CapabilityTier: String {
    case pro = "PRO"            // 支持 ProRAW（iPhone Pro 系列）
    case full = "FULL"          // 多镜头后置
    case standard = "STANDARD"  // 单后置主摄
    case basic = "BASIC"        // 兜底
}

/// 一颗可选的物理镜头（后置）
struct LensOption: Identifiable, Equatable {
    var id: String { device.uniqueID }
    let device: AVCaptureDevice
    let label: String      // "0.5x" / "1x" / "Tele"
    let sortOrder: Double

    static func == (lhs: LensOption, rhs: LensOption) -> Bool {
        lhs.device.uniqueID == rhs.device.uniqueID
    }
}

/// 设备能力画像：把 AVCaptureDevice 的原始信息翻译成结构化数据。
/// 对应 Android 版 hal 层的 DeviceCapability —— 上层只读画像，不直接碰硬件细节。
struct DeviceCapability {
    var tier: CapabilityTier
    var backLenses: [LensOption]
    var hasFrontCamera: Bool
    var proRAWSupported: Bool
    var maxPhotoWidth: Int32
    var maxPhotoHeight: Int32

    var summaryLines: [String] {
        var lines: [String] = []
        lines.append("能力等级：\(tier.rawValue)")
        let names = backLenses.map(\.label).joined(separator: " / ")
        lines.append("后置镜头：\(names.isEmpty ? "无" : names)")
        lines.append("前置镜头：\(hasFrontCamera ? "有" : "无")")
        lines.append("最大照片：\(maxPhotoWidth) × \(maxPhotoHeight)")
        lines.append("ProRAW：\(proRAWSupported ? "支持" : "不支持")")
        return lines
    }
}

/// 传感器探测器 —— 对应 Android 版 hal 层的 SensorProber。
enum CapabilityProbe {
    static func probe(photoOutput: AVCapturePhotoOutput) -> DeviceCapability {
        let backTypes: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera
        ]
        let backDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: backTypes, mediaType: .video, position: .back
        ).devices

        var lenses: [LensOption] = []
        for device in backDevices {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                lenses.append(LensOption(device: device, label: "0.5x", sortOrder: 0))
            case .builtInWideAngleCamera:
                lenses.append(LensOption(device: device, label: "1x", sortOrder: 1))
            case .builtInTelephotoCamera:
                lenses.append(LensOption(device: device, label: "Tele", sortOrder: 2))
            default:
                break
            }
        }
        lenses.sort { $0.sortOrder < $1.sortOrder }

        let frontDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
            mediaType: .video, position: .front
        ).devices

        // 最大照片尺寸：取主摄各格式里像素数最大的高分辨率尺寸
        var maxW: Int32 = 0
        var maxH: Int32 = 0
        if let wide = backDevices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
            for format in wide.formats {
                for dims in format.supportedMaxPhotoDimensions {
                    if Int64(dims.width) * Int64(dims.height) > Int64(maxW) * Int64(maxH) {
                        maxW = dims.width
                        maxH = dims.height
                    }
                }
            }
        }

        let proRAW = photoOutput.isAppleProRAWSupported

        let tier: CapabilityTier
        if proRAW {
            tier = .pro
        } else if lenses.count >= 2 {
            tier = .full
        } else if lenses.count == 1 {
            tier = .standard
        } else {
            tier = .basic
        }

        return DeviceCapability(
            tier: tier,
            backLenses: lenses,
            hasFrontCamera: !frontDevices.isEmpty,
            proRAWSupported: proRAW,
            maxPhotoWidth: maxW,
            maxPhotoHeight: maxH
        )
    }
}
