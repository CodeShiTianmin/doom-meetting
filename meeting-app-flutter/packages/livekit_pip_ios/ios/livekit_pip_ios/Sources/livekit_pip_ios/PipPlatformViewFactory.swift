import Flutter

/// Creates PipPlatformView instances for the Flutter engine.
class PipPlatformViewFactory: NSObject, FlutterPlatformViewFactory {

    private weak var plugin: LiveKitPipPlugin?

    init(plugin: LiveKitPipPlugin) {
        self.plugin = plugin
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
        -> FlutterPlatformView
    {
        let view = PipPlatformView(frame: frame, viewId: viewId, args: args)
        plugin?.didCreatePlatformView(view)
        return view
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
