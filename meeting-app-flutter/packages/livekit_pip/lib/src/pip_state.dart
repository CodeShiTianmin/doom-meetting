/// Current state of the PiP session.
enum PipState {
  /// Device or OS version does not support PiP.
  /// Terminal state — no transitions out.
  unsupported,

  /// PiP is supported and initialized but the window is not visible.
  inactive,

  /// PiP window is being created; OS has accepted the request.
  /// Transient — always followed by [active].
  entering,

  /// PiP window is visible and active.
  active,

  /// PiP window is being dismissed. Transient — always followed by [inactive].
  exiting,
}
