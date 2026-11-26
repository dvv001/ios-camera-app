import AVFoundation
import UIKit

/// 拍摄模式
enum CaptureMode {
    case photo
    case video
}

/// 闪光灯选项（对应 AVCapturePhotoSettings.FlashMode）
enum FlashOption: CaseIterable {
    case off
    case auto
    case on

    var settingsMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    var iconName: String {
        switch self {
        case .off: return "bolt.slash"
        case .auto: return "bolt.badge.a"
        case .on: return "bolt.fill"
        }
    }

    var next: FlashOption {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }
}

/// 相机会话与拍摄 —— 对应 Android 版 capture 层（SessionController）+ domain 层用例的合并实现：
/// 负责会话配置、镜头切换、3A（点按对焦/测光、曝光补偿）、拍照与录像的编排。
/// 所有会话操作都在 sessionQueue 上串行执行，UI 状态通过 @Published 回主线程发布。
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.example.procamera.session")

    private var configured = false
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?

    @Published private(set) var capability: DeviceCapability?
    @Published private(set) var mode: CaptureMode = .photo
    @Published var flash: FlashOption = .off
    @Published var showGrid = false
    @Published private(set) var isFront = false
    @Published private(set) var currentLensID: String = ""
    @Published private(set) var hasFlash = false
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var biasRange: ClosedRange<Float> = -2...2
    @Published private(set) var isRecording = false
    @Published var lastThumbnail: UIImage?
    @Published var notice: String?

    // MARK: - 生命周期

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in
                self?.configureIfNeeded()
                self?.session.startRunning()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.sessionQueue.async {
                        self.configureIfNeeded()
                        self.session.startRunning()
                    }
                } else {
                    self.publish { self.notice = "相机权限未开启，请到系统设置里允许 ProCamera 使用相机。" }
                }
            }
        default:
            publish { self.notice = "相机权限未开启，请到系统设置里允许 ProCamera 使用相机。" }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: - 会话配置（对应 Android 版：探测 → 选策略 → 组装）

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        let cap = CapabilityProbe.probe(photoOutput: photoOutput)
        publish { self.capability = cap }

        session.beginConfiguration()
        session.sessionPreset = .photo

        // 默认用后置主摄；没有主摄就用第一颗后置；再没有就用系统默认设备
        let initial = cap.backLenses.first(where: { $0.label == "1x" })?.device
            ?? cap.backLenses.first?.device
            ?? AVCaptureDevice.default(for: .video)
        if let device = initial {
            attach(device: device)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            if cap.maxPhotoWidth > 0 {
                photoOutput.maxPhotoDimensions = CMVideoDimensions(
                    width: cap.maxPhotoWidth, height: cap.maxPhotoHeight
                )
            }
        }
        session.commitConfiguration()
    }

    /// 把当前输入换成指定设备（必须在 begin/commit 之间或独立调用时自带事务）
    private func attach(device: AVCaptureDevice) {
        if let old = videoInput {
            session.removeInput(old)
        }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoInput = input
        currentDevice = device
        publish {
            self.currentLensID = device.uniqueID
            self.hasFlash = device.hasFlash
            self.isFront = device.position == .front
            self.zoomFactor = 1
            self.biasRange = device.minExposureTargetBias...device.maxExposureTargetBias
            self.exposureBias = 0
        }
    }

    // MARK: - 镜头与前后切换

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, let cap = self.capability else { return }
            self.session.beginConfiguration()
            if self.isFront {
                let back = cap.backLenses.first(where: { $0.label == "1x" })?.device
                    ?? cap.backLenses.first?.device
                if let back = back { self.attach(device: back) }
            } else {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                    mediaType: .video, position: .front
                )
                if let front = discovery.devices.first { self.attach(device: front) }
            }
            self.session.commitConfiguration()
        }
    }

    func selectLens(_ lens: LensOption) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.attach(device: lens.device)
            self.session.commitConfiguration()
        }
    }

    // MARK: - 模式切换（拍照 preset 与录像 preset 不同，切换时重配会话）

    func setMode(_ newMode: CaptureMode) {
        publish { self.mode = newMode }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            if newMode == .video {
                self.session.sessionPreset = .high
                if !self.session.outputs.contains(where: { $0 === self.movieOutput }),
                   self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
            } else {
                if self.session.outputs.contains(where: { $0 === self.movieOutput }) {
                    self.session.removeOutput(self.movieOutput)
                }
                self.session.sessionPreset = .photo
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - 3A：点按对焦/测光、曝光补偿、变焦

    func focusAndExpose(at devicePoint: CGPoint) {
        guard let device = currentDevice else { return }
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
            }
            device.unlockForConfiguration()
        }
    }

    func setExposureBias(_ value: Float) {
        guard let device = currentDevice else { return }
        let clamped = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
        publish { self.exposureBias = clamped }
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10)
        let clamped = min(max(factor, 1), maxZoom)
        publish { self.zoomFactor = clamped }
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let settings = AVCapturePhotoSettings()
            if self.currentDevice?.hasFlash == true {
                settings.flashMode = self.flash.settingsMode
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - 录像

    func toggleRecording() {
        if isRecording {
            sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            guard let self = self else { return }
            self.sessionQueue.async {
                self.session.beginConfiguration()
                self.ensureAudioInput()
                self.session.commitConfiguration()
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                self.publish { self.isRecording = true }
            }
        }
    }

    private func ensureAudioInput() {
        guard audioInput == nil,
              let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else { return }
        session.addInput(input)
        audioInput = input
    }

    // MARK: - 工具

    private func publish(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - 拍照回调

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            publish { self.notice = "拍照失败：\(error.localizedDescription)" }
            return
        }
        guard let data = photo.fileDataRepresentation() else { return }
        if let image = UIImage(data: data) {
            publish { self.lastThumbnail = image }
        }
        PhotoSaver.savePhoto(data: data) { [weak self] ok in
            if !ok {
                self?.publish { self?.notice = "照片未能存入相册，请检查相册权限。" }
            }
        }
    }
}

// MARK: - 录像回调

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        publish { self.isRecording = false }
        // 某些 error（如达到最大时长）下文件仍然可用，以文件存在为准
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            if let error = error {
                publish { self.notice = "录像失败：\(error.localizedDescription)" }
            }
            return
        }
        if let thumb = thumbnail(forVideoAt: outputFileURL) {
            publish { self.lastThumbnail = thumb }
        }
        PhotoSaver.saveVideo(fileURL: outputFileURL) { ok in
            try? FileManager.default.removeItem(at: outputFileURL)
            if !ok {
                self.publish { self.notice = "录像未能存入相册，请检查相册权限。" }
            }
        }
    }

    private func thumbnail(forVideoAt url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
