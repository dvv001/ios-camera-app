import SwiftUI

/// 主界面 —— 对应 Android 版 ui 层（MainActivity + CameraViewModel）：
/// 只认 CameraManager 发布的接口与状态，不直接碰 AVCaptureSession 细节。
struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var showCapability = false
    @State private var pinchBase: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session) { point in
                camera.focusAndExpose(at: point)
            }
            .ignoresSafeArea()
            .gesture(pinchGesture)

            if camera.showGrid {
                GridOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
                lensRow
                evRow
                modePicker
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .alert("提示", isPresented: noticeBinding) {
            Button("好") { camera.notice = nil }
        } message: {
            Text(camera.notice ?? "")
        }
        .sheet(isPresented: $showCapability) {
            capabilitySheet
        }
    }

    // MARK: - 顶部栏：能力等级 / 闪光灯 / 网格

    private var topBar: some View {
        HStack {
            Button {
                showCapability = true
            } label: {
                Text(camera.capability?.tier.rawValue ?? "…")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }
            Spacer()
            if camera.hasFlash && camera.mode == .photo {
                Button {
                    camera.flash = camera.flash.next
                } label: {
                    Image(systemName: camera.flash.iconName)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
            }
            Button {
                camera.showGrid.toggle()
            } label: {
                Image(systemName: "grid")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .opacity(camera.showGrid ? 1 : 0.6)
            }
        }
        .foregroundColor(.white)
    }

    // MARK: - 镜头切换（只有硬件真的有多颗后置镜头时才出现）

    @ViewBuilder
    private var lensRow: some View {
        if !camera.isFront, let cap = camera.capability, cap.backLenses.count > 1 {
            HStack(spacing: 10) {
                ForEach(cap.backLenses) { lens in
                    Button {
                        camera.selectLens(lens)
                    } label: {
                        Text(lens.label)
                            .font(.caption.bold())
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(
                                    camera.currentLensID == lens.id
                                        ? Color.yellow
                                        : Color.white.opacity(0.25)
                                )
                            )
                            .foregroundColor(
                                camera.currentLensID == lens.id ? .black : .white
                            )
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: - 曝光补偿

    private var evRow: some View {
        HStack(spacing: 8) {
            Text("EV")
                .font(.caption.bold())
                .foregroundColor(.white)
            Slider(
                value: Binding(
                    get: { camera.exposureBias },
                    set: { camera.setExposureBias($0) }
                ),
                in: camera.biasRange,
                step: 0.1
            )
            .accentColor(.yellow)
            Text(String(format: "%+.1f", camera.exposureBias))
                .font(.caption)
                .foregroundColor(.white)
                .frame(width: 36)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - 模式切换

    private var modePicker: some View {
        Picker("模式", selection: Binding(
            get: { camera.mode },
            set: { camera.setMode($0) }
        )) {
            Text("照片").tag(CaptureMode.photo)
            Text("录像").tag(CaptureMode.video)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .padding(.bottom, 10)
    }

    // MARK: - 底部栏：缩略图 / 快门 / 前后切换

    private var bottomBar: some View {
        HStack {
            thumbnail
                .frame(width: 48, height: 48)
            Spacer()
            shutterButton
            Spacer()
            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let image = camera.lastThumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.15)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var shutterButton: some View {
        Button {
            if camera.mode == .photo {
                camera.capturePhoto()
            } else {
                camera.toggleRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                if camera.mode == .video {
                    RoundedRectangle(cornerRadius: camera.isRecording ? 6 : 28)
                        .fill(Color.red)
                        .frame(width: camera.isRecording ? 30 : 56,
                               height: camera.isRecording ? 30 : 56)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 62, height: 62)
                }
            }
        }
    }

    // MARK: - 手势与弹层

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                camera.setZoom(pinchBase * value)
            }
            .onEnded { _ in
                pinchBase = camera.zoomFactor
            }
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { camera.notice != nil },
            set: { if !$0 { camera.notice = nil } }
        )
    }

    private var capabilitySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设备能力画像")
                .font(.headline)
            if let cap = camera.capability {
                ForEach(cap.summaryLines, id: \.self) { line in
                    Text(line)
                        .font(.body)
                }
            } else {
                Text("正在探测…")
            }
            Spacer()
            Button("关闭") { showCapability = false }
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}
