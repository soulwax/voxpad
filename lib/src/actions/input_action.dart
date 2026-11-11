import '../devices/input_device_state.dart';
import '../processors/deadzone_processor.dart';
import 'input_binding.dart';

/// Value category produced by an [InputAction].
enum ActionValueType {
  button,
  value1D,
  value2D,
}

/// Lifecycle phase of an input action within the current frame.
enum ActionPhase {
  waiting,
  started,
  performed,
  canceled,
}

/// Logical named action bound to one or more physical [InputBinding]s.
class InputAction {
  final String name;
  final ActionValueType type;
  final List<InputBinding> bindings;
  final double pressThreshold;

  bool _isPressed = false;
  bool _wasPressed = false;
  bool _wasReleased = false;
  double _value = 0.0;
  PadVec2 _vector2 = PadVec2.zero;
  double _heldDuration = 0.0;
  ActionPhase _phase = ActionPhase.waiting;

  double _timeSincePress = double.infinity;
  bool _bufferConsumed = false;

  /// Optional callbacks invoked on phase transitions.
  final List<void Function(InputAction)> onStarted = [];
  final List<void Function(InputAction)> onPerformed = [];
  final List<void Function(InputAction)> onCanceled = [];

  InputAction({
    required this.name,
    this.type = ActionValueType.button,
    List<InputBinding>? bindings,
    this.pressThreshold = 0.5,
  }) : bindings = bindings != null ? List<InputBinding>.from(bindings) : [];

  /// True while any bound control activates this action past [pressThreshold].
  bool get isPressed => _isPressed;

  /// True only on the frame the action transitioned to active.
  bool get wasPressedThisFrame => _wasPressed;

  /// True only on the frame the action transitioned from active to inactive.
  bool get wasReleasedThisFrame => _wasReleased;

  /// Scalar 1D magnitude of the action (in [-1, 1] or [0, 1] depending on binding).
  double get value => _value;

  /// 2D axis vector for movement/aiming actions.
  PadVec2 get vector2 => _vector2;

  /// Seconds this action has been continuously held down.
  double get heldDuration => _heldDuration;

  /// Current interaction phase.
  ActionPhase get phase => _phase;

  /// Time in seconds elapsed since the most recent press trigger.
  double get timeSinceLastPress => _timeSincePress;

  /// Returns true if a press occurred within the last [windowSeconds] and has not yet
  /// been consumed (ideal for responsive coyote-time / jump-buffering mechanics).
  bool consumeBufferedPress(double windowSeconds) {
    if (!_bufferConsumed && _timeSincePress <= windowSeconds) {
      _bufferConsumed = true;
      _wasPressed = false;
      return true;
    }
    return false;
  }

  /// Consumes this frame's edge press trigger so downstream listeners see false.
  bool consumePress() {
    if (_wasPressed) {
      _wasPressed = false;
      _bufferConsumed = true;
      return true;
    }
    return false;
  }

  /// Evaluates bindings against [state] and advances timers & callbacks.
  void evaluate(InputStateSnapshot state, double dt, {bool consumeUsedControls = false}) {
    final prevPressed = _isPressed;

    double bestScalar = 0.0;
    PadVec2 bestVec = PadVec2.zero;
    InputBinding? winningBinding;

    for (final b in bindings) {
      if (type == ActionValueType.value2D) {
        final v = b.evaluate2D(state);
        if (v.lengthSquared > bestVec.lengthSquared) {
          bestVec = v;
          bestScalar = v.length;
          winningBinding = b;
        }
      } else {
        final s = b.evaluate1D(state);
        if (s.abs() > bestScalar.abs()) {
          bestScalar = s;
          bestVec = PadVec2(s, 0.0);
          winningBinding = b;
        }
      }
    }

    _value = bestScalar;
    _vector2 = bestVec;
    _isPressed = bestScalar.abs() >= pressThreshold;
    _wasPressed = _isPressed && !prevPressed;
    _wasReleased = !_isPressed && prevPressed;

    if (consumeUsedControls && _isPressed && winningBinding != null) {
      state.consumedControls.addAll(winningBinding.referencedControls);
    }

    if (_wasPressed) {
      _heldDuration = 0.0;
      _timeSincePress = 0.0;
      _bufferConsumed = false;
      _phase = ActionPhase.started;
      for (final cb in onStarted) {
        cb(this);
      }
      _phase = ActionPhase.performed;
      for (final cb in onPerformed) {
        cb(this);
      }
    } else if (_isPressed) {
      _heldDuration += dt;
      _timeSincePress += dt;
      _phase = ActionPhase.performed;
    } else if (_wasReleased) {
      _heldDuration = 0.0;
      _timeSincePress += dt;
      _phase = ActionPhase.canceled;
      for (final cb in onCanceled) {
        cb(this);
      }
    } else {
      _heldDuration = 0.0;
      if (_timeSincePress.isFinite) {
        _timeSincePress += dt;
      }
      _phase = ActionPhase.waiting;
    }
  }

  /// Resets all active state to neutral (used when disabling an action map).
  void reset() {
    final wasDown = _isPressed;
    _isPressed = false;
    _wasPressed = false;
    _wasReleased = wasDown;
    _value = 0.0;
    _vector2 = PadVec2.zero;
    _heldDuration = 0.0;
    _phase = wasDown ? ActionPhase.canceled : ActionPhase.waiting;
    if (wasDown) {
      for (final cb in onCanceled) {
        cb(this);
      }
    }
  }
}
