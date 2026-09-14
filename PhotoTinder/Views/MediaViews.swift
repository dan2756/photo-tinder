import SwiftUI
import AVKit
import PhotosUI

struct ThumbnailView: View {
    let item: MediaItem
    @State private var loader: MediaLoader
    init(item: MediaItem, library: PhotoLibrary) {
        self.item = item
        _loader = State(initialValue: library.makeLoader())
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.tertiarySystemFill)
                if let image = loader.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else { Image(systemName: item.kind.symbol).foregroundStyle(.secondary) }
            }
        }
        .contentShape(Rectangle())
        .task(id: item.id) { loader.load(item: item, targetSize: CGSize(width: 300, height: 300), kind: .thumbnail) }
        .onDisappear { loader.cancel() }
    }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerSurface { PlayerSurface() }
    func updateUIView(_ view: PlayerSurface, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: PlayerSurface, coordinator: Void) { view.playerLayer.player = nil }
}
final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct LivePhotoSurface: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let play: Bool
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }
    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
        if play { view.startPlayback(with: .full) } else { view.stopPlayback() }
    }
    static func dismantleUIView(_ view: PHLivePhotoView, coordinator: Void) { view.stopPlayback(); view.livePhoto = nil }
}

struct ZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .black
        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Photo. Pinch to zoom and drag to inspect."
        scroll.addSubview(imageView)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let imageView = context.coordinator.imageView
        if imageView.image !== image { scroll.setZoomScale(1, animated: false); imageView.image = image }
        if scroll.zoomScale == 1 { imageView.frame = scroll.bounds; imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight] }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}

struct InspectionView: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var loader: MediaLoader
    @State private var livePlaying = false
    init(item: MediaItem, library: PhotoLibrary) {
        self.item = item
        _loader = State(initialValue: library.makeLoader())
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player = loader.player { VideoPlayer(player: player) }
                else if let live = loader.livePhoto { LivePhotoSurface(livePhoto: live, play: livePlaying) }
                else if let image = loader.image { ZoomImage(image: image) }
                if loader.isLoading { ProgressView("Loading media…").tint(.white).foregroundStyle(.white).padding().background(.black.opacity(0.65), in: .capsule) }
                if let error = loader.errorMessage { MediaErrorView(message: error, retry: loader.retry) }
            }
            .navigationTitle(item.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("closeInspection")
                }
                if item.kind == .video {
                    ToolbarItem(placement: .bottomBar) {
                        Button(loader.isMuted ? "Unmute" : "Mute", systemImage: loader.isMuted ? "speaker.slash" : "speaker.wave.2") { loader.setMuted(!loader.isMuted) }
                    }
                }
                if item.kind == .livePhoto {
                    ToolbarItem(placement: .bottomBar) {
                        Button(livePlaying ? "Stop Live Photo" : "Play Live Photo", systemImage: livePlaying ? "stop.fill" : "livephoto") { livePlaying.toggle() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { loader.load(item: item, targetSize: CGSize(width: 2400, height: 3000), kind: .inspection) }
        .onDisappear { livePlaying = false; loader.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { livePlaying = false; loader.pause() } }
    }
}

struct MediaErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash").font(.title)
            Text(message).font(.subheadline).multilineTextAlignment(.center)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }.padding(20).background(.regularMaterial, in: .rect(cornerRadius: 20)).padding()
    }
}
