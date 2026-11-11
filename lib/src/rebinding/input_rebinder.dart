import 'dart:convert';
import '../actions/action_map.dart';
import '../actions/input_action.dart';
import '../actions/input_binding.dart';
import '../devices/input_device_state.dart';

/// How [InputRebinder] handles pressing a physical control already bound in the same [ActionMap].
enum RebindConflictPolicy {
  /// Allows multiple actions to share the same physical key.
  allowDuplicate,

  /// Swaps the conflicting action's binding with the target action's previous control.
  swap,

  /// Refuses the rebind and fires [onRejected] if already bound.
  reject,
}

/// Interactive state machine that listens for the next physical key/button press to rebind an action.
class InputRebinder {
  ActionMap? _targetMap;
  InputAction? _targetAction;
  int _bindingIndex = 0;
  Set<String> _cancelControls = const {'Escape'};
  RebindConflictPolicy _conflictPolicy = RebindConflictPolicy.swap;

  void Function(String newControl)? _onCompleted;
  void Function()? _onCanceled;
  void Function(String conflictingActionName)? _onRejected;

  bool get isListening => _targetAction != null;
  InputAction? get targetAction => _targetAction;

  /// Begins listening for the next newly pressed physical control to rebind [action.bindings[bindingIndex]].
  void startListening({
    required ActionMap map,
    required InputAction action,
    int bindingIndex = 0,
    Set<String> cancelControls = const {'Escape'},
    RebindConflictPolicy conflictPolicy = RebindConflictPolicy.swap,
    void Function(String newControl)? onCompleted,
    void Function()? onCanceled,
    void Function(String conflictingActionName)? onRejected,
  }) {
    _targetMap = map;
    _targetAction = action;
    _bindingIndex = bindingIndex;
    _cancelControls = cancelControls;
    _conflictPolicy = conflictPolicy;
    _onCompleted = onCompleted;
    _onCanceled = onCanceled;
    _onRejected = onRejected;
  }

  /// Polls raw input state for the next pressed control. Call each frame while [isListening] is true.
  /// Returns true if a rebind completed on this frame.
  bool poll(InputStateSnapshot state) {
    final action = _targetAction;
    final map = _targetMap;
    if (action == null || map == null) return false;

    for (final pressed in state.newlyPressedControls) {
      if (_cancelControls.contains(pressed)) {
        cancel();
        return false;
      }

      // Check for conflicts in same ActionMap
      if (_conflictPolicy != RebindConflictPolicy.allowDuplicate) {
        for (final otherAction in map.actions) {
          if (identical(otherAction, action)) continue;
          for (int i = 0; i < otherAction.bindings.length; i++) {
            final b = otherAction.bindings[i];
            if (b is KeyBinding && b.control == pressed) {
              if (_conflictPolicy == RebindConflictPolicy.reject) {
                _onRejected?.call(otherAction.name);
                return false;
              } else if (_conflictPolicy == RebindConflictPolicy.swap) {
                final oldBinding = _bindingIndex < action.bindings.length
                    ? action.bindings[_bindingIndex]
                    : null;
                if (oldBinding is KeyBinding) {
                  otherAction.bindings[i] = KeyBinding(oldBinding.control, scale: b.scale);
                }
              }
            }
          }
        }
      }

      // Apply new binding
      while (action.bindings.length <= _bindingIndex) {
        action.bindings.add(KeyBinding(pressed));
      }
      action.bindings[_bindingIndex] = KeyBinding(pressed);

      final cb = _onCompleted;
      _reset();
      cb?.call(pressed);
      return true;
    }

    return false;
  }

  /// Aborts interactive listening without changing bindings.
  void cancel() {
    if (!isListening) return;
    final cb = _onCanceled;
    _reset();
    cb?.call();
  }

  void _reset() {
    _targetMap = null;
    _targetAction = null;
    _onCompleted = null;
    _onCanceled = null;
    _onRejected = null;
  }
}

/// Serializes and restores user-rebound bindings for an [InputActionAsset] to/from JSON.
class InputProfileSerializer {
  static Map<String, dynamic> exportBindings(InputActionAsset asset) {
    final mapsJson = <String, dynamic>{};
    for (final map in asset.maps) {
      final actionsJson = <String, dynamic>{};
      for (final action in map.actions) {
        actionsJson[action.name] = action.bindings.map((b) => b.toJson()).toList();
      }
      mapsJson[map.name] = actionsJson;
    }
    return {'version': 1, 'maps': mapsJson};
  }

  static String exportJson(InputActionAsset asset) => jsonEncode(exportBindings(asset));

  static void importBindings(InputActionAsset asset, Map<String, dynamic> data) {
    final mapsJson = data['maps'] as Map<String, dynamic>?;
    if (mapsJson == null) return;

    for (final entry in mapsJson.entries) {
      final map = asset.getMap(entry.key);
      if (map == null) continue;
      final actionsJson = entry.value as Map<String, dynamic>?;
      if (actionsJson == null) continue;

      for (final actionEntry in actionsJson.entries) {
        final action = map.getAction(actionEntry.key);
        if (action == null) continue;
        final rawList = actionEntry.value as List?;
        if (rawList == null) continue;

        action.bindings
          ..clear()
          ..addAll(rawList.map((e) => InputBinding.fromJson(e as Map<String, dynamic>)));
      }
    }
  }

  static void importJson(InputActionAsset asset, String jsonString) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    importBindings(asset, decoded);
  }
}
