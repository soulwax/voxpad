import 'dart:math' as math;
import '../devices/input_device_state.dart';
import '../processors/deadzone_processor.dart';

/// Platform-neutral pointer/touch sample fed to virtual on-screen controls.
class VirtualTouchPointer {
  final int id;
  final double x;
  final double y;
  final bool isDown;

  const VirtualTouchPointer({
    required this.id,
    required this.x,
    required this.y,
    required this.isDown,
  });
}

/// On-screen virtual analog stick (fixed or floating) emitting 2D axis outputs.
class VirtualStick {
  double centerX;
  double centerY;
  double radius;
  final String axisXName;
  final String axisYName;
  final DeadzoneProcessor deadzone;
  final bool floating;
  final bool invertY;

  int? _activePointerId;
  late double _originX;
  late double _originY;
  late double _knobX;
  late double _knobY;
  PadVec2 _value = PadVec2.zero;

  VirtualStick({
    required this.centerX,
    required this.centerY,
    this.radius = 60.0,
    this.axisXName = 'VirtualLeftX',
    this.axisYName = 'VirtualLeftY',
    this.deadzone = const DeadzoneProcessor(mode: DeadzoneMode.radialScaled, innerDeadzone: 0.1),
    this.floating = false,
    this.invertY = true,
  }) {
    _resetKnob();
  }

  bool get isActive => _activePointerId != null;
  double get originX => _originX;
  double get originY => _originY;
  double get knobX => _knobX;
  double get knobY => _knobY;
  PadVec2 get value => _value;

  void _resetKnob() {
    _originX = centerX;
    _originY = centerY;
    _knobX = centerX;
    _knobY = centerY;
    _value = PadVec2.zero;
    _activePointerId = null;
  }

  /// Updates this stick from current touch pointers and returns true if it captured a new pointer.
  void update(List<VirtualTouchPointer> pointers) {
    if (_activePointerId != null) {
      VirtualTouchPointer? match;
      for (final p in pointers) {
        if (p.id == _activePointerId && p.isDown) {
          match = p;
          break;
        }
      }
      if (match == null) {
        _resetKnob();
      } else {
        _applyPointerPosition(match.x, match.y);
      }
      return;
    }

    // Try capturing a newly downed pointer inside radius
    for (final p in pointers) {
      if (!p.isDown) continue;
      final dx = p.x - centerX;
      final dy = p.y - centerY;
      if (dx * dx + dy * dy <= radius * radius) {
        _activePointerId = p.id;
        if (floating) {
          _originX = p.x;
          _originY = p.y;
        } else {
          _originX = centerX;
          _originY = centerY;
        }
        _applyPointerPosition(p.x, p.y);
        return;
      }
    }
  }

  void _applyPointerPosition(double px, double py) {
    final dx = px - _originX;
    final dy = py - _originY;
    final dist = math.sqrt(dx * dx + dy * dy);
    final clampedDist = math.min(dist, radius);

    if (dist > 1e-6) {
      final nx = dx / dist;
      final ny = dy / dist;
      _knobX = _originX + nx * clampedDist;
      _knobY = _originY + ny * clampedDist;
      final rawX = (nx * clampedDist) / radius;
      final rawY = ((invertY ? -ny : ny) * clampedDist) / radius;
      _value = deadzone.process2D(rawX, rawY);
    } else {
      _knobX = _originX;
      _knobY = _originY;
      _value = PadVec2.zero;
    }
  }
}

/// On-screen virtual circular button driving a named physical control.
class VirtualButton {
  double centerX;
  double centerY;
  double radius;
  final String controlName;
  final String label;

  int? _activePointerId;
  bool _isPressed = false;

  VirtualButton({
    required this.centerX,
    required this.centerY,
    this.radius = 32.0,
    required this.controlName,
    String? label,
  }) : label = label ?? controlName;

  bool get isPressed => _isPressed;

  void update(List<VirtualTouchPointer> pointers) {
    if (_activePointerId != null) {
      VirtualTouchPointer? match;
      for (final p in pointers) {
        if (p.id == _activePointerId && p.isDown) {
          match = p;
          break;
        }
      }
      if (match == null) {
        _activePointerId = null;
        _isPressed = false;
      } else {
        final dx = match.x - centerX;
        final dy = match.y - centerY;
        _isPressed = (dx * dx + dy * dy) <= (radius * radius * 1.44); // slight slip hysteresis
      }
      return;
    }

    for (final p in pointers) {
      if (!p.isDown) continue;
      final dx = p.x - centerX;
      final dy = p.y - centerY;
      if (dx * dx + dy * dy <= radius * radius) {
        _activePointerId = p.id;
        _isPressed = true;
        return;
      }
    }
    _isPressed = false;
  }
}

/// Composite virtual touchscreen controller writing analog sticks & buttons directly into [InputStateSnapshot].
class VirtualGamepad {
  final List<VirtualStick> sticks;
  final List<VirtualButton> buttons;
  bool enabled;

  VirtualGamepad({
    List<VirtualStick>? sticks,
    List<VirtualButton>? buttons,
    this.enabled = true,
  })  : sticks = sticks ?? [],
        buttons = buttons ?? [];

  /// Creates a classic twin-stick mobile layout scaled to [viewportWidth] x [viewportHeight].
  factory VirtualGamepad.dualStick({
    required double viewportWidth,
    required double viewportHeight,
  }) {
    final padMargin = math.min(viewportWidth, viewportHeight) * 0.16;
    return VirtualGamepad(
      sticks: [
        VirtualStick(
          centerX: padMargin,
          centerY: viewportHeight - padMargin,
          radius: 56.0,
          axisXName: 'VirtualLeftX',
          axisYName: 'VirtualLeftY',
        ),
        VirtualStick(
          centerX: viewportWidth - padMargin,
          centerY: viewportHeight - padMargin,
          radius: 56.0,
          axisXName: 'VirtualRightX',
          axisYName: 'VirtualRightY',
        ),
      ],
      buttons: [
        VirtualButton(
          centerX: viewportWidth - padMargin - 90,
          centerY: viewportHeight - padMargin - 70,
          radius: 26.0,
          controlName: 'GamepadA',
          label: 'A',
        ),
        VirtualButton(
          centerX: viewportWidth - padMargin - 20,
          centerY: viewportHeight - padMargin - 100,
          radius: 26.0,
          controlName: 'GamepadB',
          label: 'B',
        ),
      ],
    );
  }

  /// Processes touch pointers and injects active axes & button states into [targetState].
  void update(List<VirtualTouchPointer> pointers, InputStateSnapshot targetState) {
    if (!enabled) return;

    for (final stick in sticks) {
      stick.update(pointers);
      if (stick.isActive) {
        targetState.setAxis(stick.axisXName, stick.value.x);
        targetState.setAxis(stick.axisYName, stick.value.y);
      } else {
        targetState.setAxis(stick.axisXName, 0.0);
        targetState.setAxis(stick.axisYName, 0.0);
      }
    }

    for (final btn in buttons) {
      btn.update(pointers);
      if (btn.isPressed) {
        targetState.press(btn.controlName);
      } else {
        // Release virtual button only when released; note keyboard physical controls won't clash if named GamepadA etc.
        targetState.release(btn.controlName);
      }
    }
  }
}
