import 'package:test/test.dart';
import 'package:voxpad/voxpad.dart';

void main() {
  group('DeadzoneProcessor', () {
    test('radialScaled zeros inside inner deadzone and rescales smoothly to outer', () {
      const dz = DeadzoneProcessor(
        mode: DeadzoneMode.radialScaled,
        innerDeadzone: 0.2,
        outerDeadzone: 0.9,
      );

      // Drift inside inner threshold -> exact zero
      expect(dz.process2D(0.1, 0.1), equals(PadVec2.zero));

      // Halfway between 0.2 and 0.9 (0.55) -> magnitude should be ~0.5
      final half = dz.process2D(0.55, 0.0);
      expect(half.x, closeTo(0.5, 1e-4));
      expect(half.y, closeTo(0.0, 1e-4));

      // At outer deadzone or beyond -> clamped to 1.0
      final maxOut = dz.process2D(0.95, 0.0);
      expect(maxOut.x, closeTo(1.0, 1e-4));
    });

    test('axial deadzone filters X and Y independently', () {
      const dz = DeadzoneProcessor(
        mode: DeadzoneMode.axial,
        innerDeadzone: 0.2,
        outerDeadzone: 1.0,
      );

      final result = dz.process2D(0.1, 0.6);
      expect(result.x, equals(0.0));
      expect(result.y, closeTo(0.5, 1e-4));
    });
  });

  group('Bindings & InputAction', () {
    test('ChordBinding only triggers when all simultaneous keys are pressed', () {
      final state = InputStateSnapshot();
      final asset = InputActionAsset();
      final editor = asset.addMap('Editor');
      final save = editor.addButton('Save', [
        const ChordBinding(['ControlLeft', 'ShiftLeft', 'KeyS']),
      ]);

      // Only ControlLeft + KeyS -> should NOT activate
      state
        ..press('ControlLeft')
        ..press('KeyS');
      asset.evaluate(state, 0.016);
      expect(save.isPressed, isFalse);

      // Add ShiftLeft -> full chord!
      state.press('ShiftLeft');
      asset.evaluate(state, 0.016);
      expect(save.isPressed, isTrue);
      expect(save.wasPressedThisFrame, isTrue);

      // Held next frame
      asset.evaluate(state, 0.016);
      expect(save.isPressed, isTrue);
      expect(save.wasPressedThisFrame, isFalse);
      expect(save.heldDuration, closeTo(0.016, 1e-4));
    });

    test('Vector2Binding normalizes diagonal digital movement', () {
      final state = InputStateSnapshot();
      final asset = InputActionAsset();
      final map = asset.addMap('Gameplay');
      final move = map.addVector2('Move', [Vector2Binding.wasd]);

      state
        ..press('KeyW')
        ..press('KeyD');
      asset.evaluate(state, 0.016);

      expect(move.vector2.length, closeTo(1.0, 1e-4));
      expect(move.vector2.x, closeTo(0.7071, 1e-3));
      expect(move.vector2.y, closeTo(0.7071, 1e-3));
    });

    test('Input buffering allows forgiving late jump consumption', () {
      final state = InputStateSnapshot();
      final asset = InputActionAsset();
      final map = asset.addMap('Gameplay');
      final jump = map.addButton('Jump', [const KeyBinding('Space')]);

      // Frame 1: player taps Space slightly early before landing
      state.press('Space');
      asset.evaluate(state, 0.016);
      state.release('Space');
      asset.evaluate(state, 0.016); // released on frame 2, elapsed 0.016s since press
      asset.evaluate(state, 0.05); // 0.066s elapsed since press

      expect(jump.isPressed, isFalse);
      expect(jump.wasPressedThisFrame, isFalse);

      // Player hits ground at 0.066s -> within 0.15s buffer window!
      expect(jump.consumeBufferedPress(0.15), isTrue);
      // Consuming again returns false so jump cannot double-fire
      expect(jump.consumeBufferedPress(0.15), isFalse);
    });
  });

  group('ActionMap Priorities & Switching', () {
    test('Higher priority map with blocksLowerMaps consumes shared keys', () {
      final state = InputStateSnapshot();
      final asset = InputActionAsset();

      final gameplay = asset.addMap('Gameplay', priority: 0);
      final jump = gameplay.addButton('Jump', [const KeyBinding('Space')]);

      final ui = asset.addMap('UI', priority: 10, blocksLowerMaps: true);
      final confirm = ui.addButton('Confirm', [const KeyBinding('Space')]);

      state.press('Space');
      asset.evaluate(state, 0.016);

      expect(confirm.isPressed, isTrue);
      expect(jump.isPressed, isFalse); // Consumed by UI map!

      // Disable UI map -> Space passes through to Gameplay
      ui.enabled = false;
      asset.evaluate(state, 0.016);
      expect(confirm.isPressed, isFalse);
      expect(jump.isPressed, isTrue);
    });

    test('Disabling active map fires onCanceled on held actions', () {
      final state = InputStateSnapshot();
      final asset = InputActionAsset();
      final gameplay = asset.addMap('Gameplay');
      final fire = gameplay.addButton('Fire', [const KeyBinding('MouseLeft')]);

      var canceledCount = 0;
      fire.onCanceled.add((_) => canceledCount++);

      state.press('MouseLeft');
      asset.evaluate(state, 0.016);
      expect(fire.isPressed, isTrue);

      asset.enableOnly('Pause');
      expect(fire.isPressed, isFalse);
      expect(canceledCount, 1);
    });
  });

  group('InputRebinder & Profile Serialization', () {
    test('interactive rebind swaps conflicting controls and round-trips JSON', () {
      final state = InputStateSnapshot();
      final asset = InputActionAsset();
      final gameplay = asset.addMap('Gameplay');
      final jump = gameplay.addButton('Jump', [const KeyBinding('Space')]);
      final crouch = gameplay.addButton('Crouch', [const KeyBinding('KeyC')]);

      final rebinder = InputRebinder();
      String? reboundTo;

      rebinder.startListening(
        map: gameplay,
        action: jump,
        bindingIndex: 0,
        conflictPolicy: RebindConflictPolicy.swap,
        onCompleted: (ctrl) => reboundTo = ctrl,
      );

      expect(rebinder.isListening, isTrue);

      // User presses 'KeyC' (currently bound to Crouch)
      state.press('KeyC');
      expect(rebinder.poll(state), isTrue);
      state.commitFrame();

      expect(rebinder.isListening, isFalse);
      expect(reboundTo, equals('KeyC'));
      expect((jump.bindings.first as KeyBinding).control, equals('KeyC'));
      expect((crouch.bindings.first as KeyBinding).control, equals('Space'));

      // Export JSON and restore into a brand new asset
      final json = InputProfileSerializer.exportJson(asset);

      final restoredAsset = InputActionAsset();
      final restoredMap = restoredAsset.addMap('Gameplay');
      final restoredJump = restoredMap.addButton('Jump', [const KeyBinding('Space')]);
      final restoredCrouch = restoredMap.addButton('Crouch', [const KeyBinding('KeyC')]);

      InputProfileSerializer.importJson(restoredAsset, json);

      expect((restoredJump.bindings.first as KeyBinding).control, equals('KeyC'));
      expect((restoredCrouch.bindings.first as KeyBinding).control, equals('Space'));
    });
  });

  group('VirtualGamepad', () {
    test('virtual dual sticks and buttons drive ActionMap inputs cleanly', () {
      final state = InputStateSnapshot();
      final pad = VirtualGamepad(
        sticks: [
          VirtualStick(
            centerX: 100.0,
            centerY: 300.0,
            radius: 50.0,
            axisXName: 'LeftX',
            axisYName: 'LeftY',
            invertY: true,
          ),
        ],
        buttons: [
          VirtualButton(
            centerX: 500.0,
            centerY: 300.0,
            radius: 30.0,
            controlName: 'GamepadA',
          ),
        ],
      );

      final asset = InputActionAsset();
      final map = asset.addMap('Mobile');
      final move = map.addVector2('Move', [
        const Vector2Binding(analogX: 'LeftX', analogY: 'LeftY'),
      ]);
      final attack = map.addButton('Attack', [const KeyBinding('GamepadA')]);

      // Pointer 1 drags virtual stick straight right (+50px) and up (-25px in screen coords -> +0.5 Y)
      // Pointer 2 taps Attack button at (505, 305)
      pad.update([
        const VirtualTouchPointer(id: 1, x: 100.0, y: 300.0, isDown: true),
        const VirtualTouchPointer(id: 2, x: 505.0, y: 305.0, isDown: true),
      ], state);
      asset.evaluate(state, 0.016);
      expect(attack.isPressed, isTrue);

      // Drag stick all the way to the right edge
      pad.update([
        const VirtualTouchPointer(id: 1, x: 150.0, y: 300.0, isDown: true),
      ], state);
      asset.evaluate(state, 0.016);
      expect(move.vector2.x, closeTo(1.0, 1e-4));
      expect(move.vector2.y, closeTo(0.0, 1e-4));
      expect(attack.isPressed, isFalse);
    });
  });
}
