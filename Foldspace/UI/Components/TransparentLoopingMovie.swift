import SwiftUI
import AVFoundation

/// A controls-free HEVC-alpha layer. The caller keeps a still visible until decoding is ready.
struct TransparentLoopingMovie: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let onReady: (Bool) -> Void

    func makeUIView(context: Context) -> MovieSurface {
        MovieSurface(url: url, onReady: onReady)
    }

    func updateUIView(_ view: MovieSurface, context: Context) {
        view.onReady = onReady
        if isPlaying { view.player.play() } else { view.player.pause() }
    }

    static func dismantleUIView(_ view: MovieSurface, coordinator: ()) {
        view.stop()
    }

    final class MovieSurface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        let player = AVQueuePlayer()
        var onReady: (Bool) -> Void
        private var looper: AVPlayerLooper?
        private var readiness: NSKeyValueObservation?

        init(url: URL, onReady: @escaping (Bool) -> Void) {
            self.onReady = onReady
            super.init(frame: .zero)
            isOpaque = false
            backgroundColor = .clear
            isUserInteractionEnabled = false
            let movieLayer = layer as! AVPlayerLayer
            movieLayer.isOpaque = false
            movieLayer.backgroundColor = UIColor.clear.cgColor
            movieLayer.videoGravity = .resizeAspect
            movieLayer.player = player
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            readiness = movieLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async { [weak self] in self?.onReady(ready) }
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func stop() {
            readiness?.invalidate()
            readiness = nil
            player.pause()
            looper?.disableLooping()
            looper = nil
            player.removeAllItems()
            (layer as? AVPlayerLayer)?.player = nil
        }
    }
}
