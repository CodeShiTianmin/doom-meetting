import Foundation

protocol PipViewControlling: AnyObject {
    var preferredContentSize: CGSize { get set }
}

protocol PipWindowSizePolicy {
    var trackSize: CGSize { get set }
    var controller: PipViewControlling? { get set }
}

final class PipAdaptiveWindowSizePolicy: PipWindowSizePolicy {
    var trackSize: CGSize = .zero {
        didSet {
            guard trackSize != oldValue, trackSize != .zero else { return }
            // Normalize to 180pt on the short side; the system snaps to its allowed sizes.
            let shortSide: CGFloat = 180
            let aspect = trackSize.width / trackSize.height
            let size: CGSize = trackSize.width >= trackSize.height
                ? CGSize(width: (shortSide * aspect).rounded(), height: shortSide)  // landscape
                : CGSize(width: shortSide, height: (shortSide / aspect).rounded())  // portrait
            controller?.preferredContentSize = size
        }
    }
    weak var controller: PipViewControlling?
}

final class PipFixedWindowSizePolicy: PipWindowSizePolicy {
    var trackSize: CGSize = .zero
    weak var controller: PipViewControlling? {
        didSet { controller?.preferredContentSize = fixedSize }
    }
    private let fixedSize: CGSize
    init(_ fixedSize: CGSize = .init(width: 640, height: 480)) {
        self.fixedSize = fixedSize
    }
}
