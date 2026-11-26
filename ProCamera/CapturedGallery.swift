import SwiftUI
import AVKit

/// 一项刚拍下的内容（照片数据或录像的沙盒副本），供 App 内画廊回看。
struct CapturedItem: Identifiable {
    enum Kind {
        case photo(Data)
        case video(URL)
    }

    let id = UUID()
    let kind: Kind
    let thumbnail: UIImage

    var isVideo: Bool {
        if case .video = kind { return true }
        return false
    }
}

/// 最近拍摄画廊：点左下角缩略图打开，网格列出最近 12 项。
struct GalleryView: View {
    let items: [CapturedItem]
    @State private var selected: CapturedItem?
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(items) { item in
                        Button {
                            selected = item
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 110)
                                    .clipped()
                                if item.isVideo {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .padding(5)
                                }
                            }
                        }
                    }
                }
                .padding(2)
            }
            .navigationTitle("最近拍摄")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $selected) { item in
                CapturedDetailView(item: item)
            }
        }
    }
}

/// 单项查看：照片可双指放大/双击放大，录像用系统播放器播放。
struct CapturedDetailView: View {
    let item: CapturedItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch item.kind {
            case .photo(let data):
                if let image = UIImage(data: data) {
                    ZoomableImage(image: image)
                }
            case .video(let url):
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
}

struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1, lastScale * value)
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
            .onTapGesture(count: 2) {
                scale = scale > 1 ? 1 : 2.5
                lastScale = scale
            }
    }
}
