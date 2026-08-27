/// Android's PiP window aspect ratio must lie within [minRatio, maxRatio].
/// Values outside this range cause PictureInPictureParams to throw.
const double _maxRatio = 2.39;
const double _minRatio = 1 / 2.39;

/// Clamps [width]/[height] to Android's allowed PiP aspect-ratio range.
///
/// Returns `(0, 0)` for non-positive input. The longer side is preserved and
/// the other side is scaled to bring the ratio into range.
({int width, int height}) clampPipAspectRatio(int width, int height) {
  if (width <= 0 || height <= 0) return (width: 0, height: 0);
  final ratio = width / height;
  if (ratio > _maxRatio) {
    return (width: (height * _maxRatio).round(), height: height);
  }
  if (ratio < _minRatio) {
    return (width: width, height: (width / _minRatio).round());
  }
  return (width: width, height: height);
}
