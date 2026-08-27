import WebRTC

/// Isolates all flutter_webrtc internals to a single file.
///
/// If flutter_webrtc changes its registry API, only this file needs updating.
protocol NativeTrackResolver {
    func resolveVideoTrack(trackId: String) -> RTCVideoTrack?
}

/// Resolves RTCVideoTrack from flutter_webrtc's internal plugin registry.
///
/// FlutterWebRTCPlugin exposes:
///   + (FlutterWebRTCPlugin *)sharedSingleton  — class method (singleton)
///   - (RTCMediaStreamTrack *)remoteTrackForId: — searches all peer-connection
///     remoteTracks dictionaries and transceivers
///   @property localTracks: [String: id<LocalTrack>]  — local tracks; each
///     id<LocalTrack> responds to -track which returns RTCMediaStreamTrack
class FlutterWebRTCTrackResolver: NativeTrackResolver {

    func resolveVideoTrack(trackId: String) -> RTCVideoTrack? {
        // Get the singleton plugin instance via class-level KVC.
        // Equivalent to [FlutterWebRTCPlugin sharedSingleton] in ObjC.
        guard
            let cls = NSClassFromString("FlutterWebRTCPlugin") as? NSObject.Type,
            let plugin = cls.value(forKey: "sharedSingleton") as? NSObject
        else {
            print("[livekit_pip] NativeTrackResolver: FlutterWebRTCPlugin.sharedSingleton not found")
            return nil
        }

        // Remote participant tracks — the dominant speaker is always remote.
        // remoteTrackForId: searches all peer-connection remoteTracks + transceivers.
        let remoteSel = NSSelectorFromString("remoteTrackForId:")
        if plugin.responds(to: remoteSel),
           let track = plugin.perform(remoteSel, with: trackId)?
               .takeUnretainedValue() as? RTCVideoTrack {
            return track
        }

        // Local tracks — covers loopback / single-user testing.
        // localTracks is [String: id<LocalTrack>]; call -track on each entry.
        if let localTracks = plugin.value(forKey: "localTracks") as? [String: NSObject] {
            let trackSel = NSSelectorFromString("track")
            for (_, localTrack) in localTracks {
                guard localTrack.responds(to: trackSel),
                      let mediaTrack = localTrack.perform(trackSel)?
                          .takeUnretainedValue() as? RTCVideoTrack,
                      mediaTrack.trackId == trackId
                else { continue }
                return mediaTrack
            }
        }

        print("[livekit_pip] NativeTrackResolver: track \(trackId) not found")
        return nil
    }
}
