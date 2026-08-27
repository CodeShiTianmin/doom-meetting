import Combine
import Foundation
import WebRTC

final class TrackStateAdapter {

    var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            enableObserver(isEnabled)
        }
    }

    var activeTrack: RTCVideoTrack? {
        didSet {
            guard isEnabled, oldValue?.trackId != activeTrack?.trackId else { return }
            oldValue?.isEnabled = false
        }
    }

    private var observerCancellable: AnyCancellable?

    private func enableObserver(_ active: Bool) {
        if active {
            observerCancellable = Timer
                .publish(every: 0.1, on: .main, in: .default)
                .autoconnect()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.checkTracksState() }
        } else {
            observerCancellable?.cancel()
            observerCancellable = nil
        }
    }

    private func checkTracksState() {
        guard let track = activeTrack, !track.isEnabled else { return }
        activeTrack?.isEnabled = true
    }
}
