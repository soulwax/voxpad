import 'dart:math' as math;

/// 2D axis vector for analog sticks and directional movement actions.
class PadVec2 {
  final double x;
  final double y;

  const PadVec2(this.x, this.y);

  static const PadVec2 zero = PadVec2(0.0, 0.0);

  double get lengthSquared => x * x + y * y;
  double get length => math.sqrt(lengthSquared);

  PadVec2 get normalized {
    final len = length;
    if (len < 1e-12) return PadVec2.zero;
    return PadVec2(x / len, y / len);
  }

  PadVec2 operator +(PadVec2 other) => PadVec2(x + other.x, y + other.y);
  PadVec2 operator -(PadVec2 other) => PadVec2(x - other.x, y - other.y);
  PadVec2 operator *(double scalar) => PadVec2(x * scalar, y * scalar);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PadVec2 && runtimeType == other.runtimeType && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PadVec2(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Strategy used to filter analog stick or trigger jitter.
enum DeadzoneMode {
  none,
  axial,
  radial,
  radialScaled,
}

/// Configurable analog deadzone & response curve filter.
class DeadzoneProcessor {
  final DeadzoneMode mode;
  final double innerDeadzone;
  final double outerDeadzone;
  final double exponent;

  const DeadzoneProcessor({
    this.mode = DeadzoneMode.radialScaled,
    this.innerDeadzone = 0.15,
    this.outerDeadzone = 0.95,
    this.exponent = 1.0,
  });

  /// Processes a single 1D axis in [-1.0, 1.0].
  double process1D(double raw) {
    if (mode == DeadzoneMode.none) {
      return raw.clamp(-1.0, 1.0);
    }

    final sign = raw < 0 ? -1.0 : 1.0;
    final mag = raw.abs();
    if (mag <= innerDeadzone) return 0.0;

    final span = math.max(1e-6, outerDeadzone - innerDeadzone);
    final normalized = ((mag - innerDeadzone) / span).clamp(0.0, 1.0);
    final curved = exponent == 1.0 ? normalized : math.pow(normalized, exponent).toDouble();
    return sign * curved;
  }

  /// Processes a 2D stick input with axial, radial, or scaled radial deadzone filtering.
  PadVec2 process2D(double rawX, double rawY) {
    switch (mode) {
      case DeadzoneMode.none:
        return PadVec2(rawX.clamp(-1.0, 1.0), rawY.clamp(-1.0, 1.0));

      case DeadzoneMode.axial:
        return PadVec2(process1D(rawX), process1D(rawY));

      case DeadzoneMode.radial:
        final mag = math.sqrt(rawX * rawX + rawY * rawY);
        if (mag <= innerDeadzone) return PadVec2.zero;
        if (mag > 1.0) {
          return PadVec2(rawX / mag, rawY / mag);
        }
        return PadVec2(rawX, rawY);

      case DeadzoneMode.radialScaled:
        final mag = math.sqrt(rawX * rawX + rawY * rawY);
        if (mag <= innerDeadzone) return PadVec2.zero;

        final nx = rawX / mag;
        final ny = rawY / mag;
        final span = math.max(1e-6, outerDeadzone - innerDeadzone);
        final normalizedMag = ((mag - innerDeadzone) / span).clamp(0.0, 1.0);
        final curvedMag =
            exponent == 1.0 ? normalizedMag : math.pow(normalizedMag, exponent).toDouble();
        return PadVec2(nx * curvedMag, ny * curvedMag);
    }
  }
}
