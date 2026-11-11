/// Platform-neutral snapshot of raw physical keyboard, mouse, gamepad, and virtual inputs.
class InputStateSnapshot {
  final Set<String> _down = {};
  final Set<String> _prevDown = {};
  final Map<String, double> _axes = {};

  /// Controls consumed during this frame by a higher-priority action map.
  final Set<String> consumedControls = {};

  /// Tracks all controls currently physically held down.
  Set<String> get downControls => Set.unmodifiable(_down);

  /// Sets whether [control] is currently held down.
  void setDown(String control, bool isDown) {
    if (isDown) {
      _down.add(control);
    } else {
      _down.remove(control);
    }
  }

  /// Convenience helper to press a control down.
  void press(String control) => _down.add(control);

  /// Convenience helper to release a control.
  void release(String control) => _down.remove(control);

  /// Releases all digital controls and zeros all axes.
  void clearAll() {
    _down.clear();
    _axes.clear();
  }

  /// Sets raw analog value for [axisName].
  void setAxis(String axisName, double value) {
    _axes[axisName] = value;
  }

  /// Reads raw analog value for [axisName], defaulting to 0.0.
  double getAxis(String axisName) => _axes[axisName] ?? 0.0;

  /// Returns true if [control] is currently held and not consumed this frame.
  bool isDown(String control, {bool ignoreConsumed = false}) {
    if (!ignoreConsumed && consumedControls.contains(control)) return false;
    return _down.contains(control);
  }

  /// Returns true if [control] transitioned from up to down since the last frame.
  bool wasPressed(String control, {bool ignoreConsumed = false}) {
    if (!ignoreConsumed && consumedControls.contains(control)) return false;
    return _down.contains(control) && !_prevDown.contains(control);
  }

  /// Returns true if [control] transitioned from down to up since the last frame.
  bool wasReleased(String control) {
    return !_down.contains(control) && _prevDown.contains(control);
  }

  /// Returns all controls newly pressed this frame (useful for interactive rebinding).
  Iterable<String> get newlyPressedControls sync* {
    for (final c in _down) {
      if (!_prevDown.contains(c)) yield c;
    }
  }

  /// Clears per-frame consumption flags before evaluating action maps.
  void beginEvaluation() {
    consumedControls.clear();
  }

  /// Advances edge detection history at the end of a frame.
  void commitFrame() {
    _prevDown
      ..clear()
      ..addAll(_down);
  }
}
