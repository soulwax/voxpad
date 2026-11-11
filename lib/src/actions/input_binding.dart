import '../devices/input_device_state.dart';
import '../processors/deadzone_processor.dart';

/// Base class for concrete input bindings mapped to an [InputAction].
abstract class InputBinding {
  const InputBinding();

  String get bindingType;
  String get displayLabel;

  /// All physical digital controls referenced by this binding.
  List<String> get referencedControls;

  /// Evaluates 1D scalar value / button strength in [-1.0, 1.0] (or [0.0, 1.0] for buttons).
  double evaluate1D(InputStateSnapshot state);

  /// Evaluates 2D vector value for composite directional bindings.
  PadVec2 evaluate2D(InputStateSnapshot state) => PadVec2(evaluate1D(state), 0.0);

  /// Serializes this binding to JSON-compatible map.
  Map<String, dynamic> toJson();

  factory InputBinding.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'key';
    switch (type) {
      case 'key':
        return KeyBinding(
          json['control'] as String,
          scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
        );
      case 'chord':
        return ChordBinding(
          (json['controls'] as List).cast<String>(),
        );
      case 'axis1d':
        return Axis1DBinding(
          negative: json['negative'] as String?,
          positive: json['positive'] as String?,
          analogAxis: json['analogAxis'] as String?,
          scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
        );
      case 'vector2':
        return Vector2Binding(
          up: json['up'] as String?,
          down: json['down'] as String?,
          left: json['left'] as String?,
          right: json['right'] as String?,
          analogX: json['analogX'] as String?,
          analogY: json['analogY'] as String?,
          normalize: (json['normalize'] as bool?) ?? true,
        );
      default:
        throw ArgumentError('Unknown InputBinding type: $type');
    }
  }
}

/// Binds a single keyboard key, mouse button, or gamepad button.
class KeyBinding extends InputBinding {
  final String control;
  final double scale;

  const KeyBinding(this.control, {this.scale = 1.0});

  @override
  String get bindingType => 'key';

  @override
  String get displayLabel => control;

  @override
  List<String> get referencedControls => [control];

  @override
  double evaluate1D(InputStateSnapshot state) {
    return state.isDown(control) ? scale : 0.0;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'key',
        'control': control,
        if (scale != 1.0) 'scale': scale,
      };
}

/// Requires multiple physical controls to be pressed simultaneously (e.g. Ctrl+Shift+S).
class ChordBinding extends InputBinding {
  final List<String> controls;

  const ChordBinding(this.controls);

  @override
  String get bindingType => 'chord';

  @override
  String get displayLabel => controls.join('+');

  @override
  List<String> get referencedControls => List.unmodifiable(controls);

  @override
  double evaluate1D(InputStateSnapshot state) {
    if (controls.isEmpty) return 0.0;
    for (final c in controls) {
      if (!state.isDown(c)) return 0.0;
    }
    return 1.0;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'chord',
        'controls': controls,
      };
}

/// Composite 1D axis mapping negative/positive digital keys and an optional analog axis.
class Axis1DBinding extends InputBinding {
  final String? negative;
  final String? positive;
  final String? analogAxis;
  final DeadzoneProcessor deadzone;
  final double scale;

  const Axis1DBinding({
    this.negative,
    this.positive,
    this.analogAxis,
    this.deadzone = const DeadzoneProcessor(mode: DeadzoneMode.axial, innerDeadzone: 0.1),
    this.scale = 1.0,
  });

  @override
  String get bindingType => 'axis1d';

  @override
  String get displayLabel {
    if (negative != null && positive != null) return '$negative/$positive';
    return analogAxis ?? 'Axis1D';
  }

  @override
  List<String> get referencedControls => [
        if (negative != null) negative!,
        if (positive != null) positive!,
      ];

  @override
  double evaluate1D(InputStateSnapshot state) {
    double digital = 0.0;
    if (negative != null && state.isDown(negative!)) digital -= 1.0;
    if (positive != null && state.isDown(positive!)) digital += 1.0;

    double analog = 0.0;
    if (analogAxis != null) {
      analog = deadzone.process1D(state.getAxis(analogAxis!));
    }

    // Return stronger input source between digital buttons and analog axis
    final raw = digital.abs() >= analog.abs() ? digital : analog;
    return (raw * scale).clamp(-1.0, 1.0);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'axis1d',
        if (negative != null) 'negative': negative,
        if (positive != null) 'positive': positive,
        if (analogAxis != null) 'analogAxis': analogAxis,
        if (scale != 1.0) 'scale': scale,
      };
}

/// Composite 2D vector mapping directional keys (e.g. WASD/Arrows) and optional 2D analog stick.
class Vector2Binding extends InputBinding {
  final String? up;
  final String? down;
  final String? left;
  final String? right;
  final String? analogX;
  final String? analogY;
  final DeadzoneProcessor deadzone;
  final bool normalize;

  const Vector2Binding({
    this.up,
    this.down,
    this.left,
    this.right,
    this.analogX,
    this.analogY,
    this.deadzone = const DeadzoneProcessor(mode: DeadzoneMode.radialScaled, innerDeadzone: 0.15),
    this.normalize = true,
  });

  /// Preset for classic WASD digital movement.
  static const Vector2Binding wasd = Vector2Binding(
    up: 'KeyW',
    down: 'KeyS',
    left: 'KeyA',
    right: 'KeyD',
  );

  /// Preset for arrow keys digital movement.
  static const Vector2Binding arrows = Vector2Binding(
    up: 'ArrowUp',
    down: 'ArrowDown',
    left: 'ArrowLeft',
    right: 'ArrowRight',
  );

  @override
  String get bindingType => 'vector2';

  @override
  String get displayLabel {
    if (up != null && left != null && down != null && right != null) {
      return '$up/$left/$down/$right';
    }
    return analogX != null ? '$analogX/$analogY' : 'Vector2';
  }

  @override
  List<String> get referencedControls => [
        if (up != null) up!,
        if (down != null) down!,
        if (left != null) left!,
        if (right != null) right!,
      ];

  @override
  double evaluate1D(InputStateSnapshot state) => evaluate2D(state).length;

  @override
  PadVec2 evaluate2D(InputStateSnapshot state) {
    double dx = 0.0;
    double dy = 0.0;
    if (left != null && state.isDown(left!)) dx -= 1.0;
    if (right != null && state.isDown(right!)) dx += 1.0;
    if (down != null && state.isDown(down!)) dy -= 1.0;
    if (up != null && state.isDown(up!)) dy += 1.0;

    var digitalVec = PadVec2(dx, dy);
    if (normalize && digitalVec.lengthSquared > 1.0) {
      digitalVec = digitalVec.normalized;
    }

    var analogVec = PadVec2.zero;
    if (analogX != null || analogY != null) {
      final rawX = analogX != null ? state.getAxis(analogX!) : 0.0;
      final rawY = analogY != null ? state.getAxis(analogY!) : 0.0;
      analogVec = deadzone.process2D(rawX, rawY);
    }

    return digitalVec.lengthSquared >= analogVec.lengthSquared ? digitalVec : analogVec;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'vector2',
        if (up != null) 'up': up,
        if (down != null) 'down': down,
        if (left != null) 'left': left,
        if (right != null) 'right': right,
        if (analogX != null) 'analogX': analogX,
        if (analogY != null) 'analogY': analogY,
        'normalize': normalize,
      };
}
