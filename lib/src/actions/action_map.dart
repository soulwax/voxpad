import '../devices/input_device_state.dart';
import 'input_action.dart';
import 'input_binding.dart';

/// Contextual grouping of related [InputAction]s (e.g. "Gameplay", "UI", "Vehicle").
class ActionMap {
  final String name;
  int priority;
  bool blocksLowerMaps;
  bool _enabled;

  final Map<String, InputAction> _actions = {};

  ActionMap({
    required this.name,
    this.priority = 0,
    bool enabled = true,
    this.blocksLowerMaps = false,
  }) : _enabled = enabled;

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!_enabled) {
      for (final action in _actions.values) {
        action.reset();
      }
    }
  }

  /// Registers a digital button action.
  InputAction addButton(
    String actionName,
    List<InputBinding> bindings, {
    double pressThreshold = 0.5,
  }) {
    final action = InputAction(
      name: actionName,
      type: ActionValueType.button,
      bindings: bindings,
      pressThreshold: pressThreshold,
    );
    _actions[actionName] = action;
    return action;
  }

  /// Registers a 1D scalar axis action.
  InputAction addAxis1D(String actionName, List<InputBinding> bindings) {
    final action = InputAction(
      name: actionName,
      type: ActionValueType.value1D,
      bindings: bindings,
      pressThreshold: 0.1,
    );
    _actions[actionName] = action;
    return action;
  }

  /// Registers a 2D directional vector action (e.g. Move, Look).
  InputAction addVector2(String actionName, List<InputBinding> bindings) {
    final action = InputAction(
      name: actionName,
      type: ActionValueType.value2D,
      bindings: bindings,
      pressThreshold: 0.1,
    );
    _actions[actionName] = action;
    return action;
  }

  InputAction? getAction(String actionName) => _actions[actionName];
  InputAction? operator [](String actionName) => _actions[actionName];

  Iterable<InputAction> get actions => _actions.values;

  /// Evaluates all actions inside this map if enabled.
  void evaluate(InputStateSnapshot state, double dt) {
    if (!_enabled) return;
    for (final action in _actions.values) {
      action.evaluate(state, dt, consumeUsedControls: blocksLowerMaps);
    }
  }
}

/// Top-level container organizing prioritized contextual [ActionMap]s.
class InputActionAsset {
  final Map<String, ActionMap> _maps = {};

  ActionMap addMap(
    String name, {
    int priority = 0,
    bool enabled = true,
    bool blocksLowerMaps = false,
  }) {
    final map = ActionMap(
      name: name,
      priority: priority,
      enabled: enabled,
      blocksLowerMaps: blocksLowerMaps,
    );
    _maps[name] = map;
    return map;
  }

  ActionMap? getMap(String name) => _maps[name];
  ActionMap? operator [](String name) => _maps[name];

  Iterable<ActionMap> get maps => _maps.values;

  /// Enables [targetMapName] and disables all other maps.
  void enableOnly(String targetMapName) {
    for (final map in _maps.values) {
      map.enabled = (map.name == targetMapName);
    }
  }

  /// Looks up an action either by `"MapName/ActionName"` or searches enabled maps by `"ActionName"`.
  InputAction? findAction(String query) {
    final slash = query.indexOf('/');
    if (slash > 0) {
      final mapName = query.substring(0, slash);
      final actionName = query.substring(slash + 1);
      return _maps[mapName]?.getAction(actionName);
    }
    for (final map in _sortedMaps()) {
      if (!map.enabled) continue;
      final found = map.getAction(query);
      if (found != null) return found;
    }
    for (final map in _sortedMaps()) {
      final found = map.getAction(query);
      if (found != null) return found;
    }
    return null;
  }

  List<ActionMap> _sortedMaps() {
    final list = _maps.values.toList();
    list.sort((a, b) => b.priority.compareTo(a.priority));
    return list;
  }

  /// Evaluates all enabled maps in descending priority order against [state].
  void evaluate(InputStateSnapshot state, double dt, {bool commitFrame = true}) {
    state.beginEvaluation();
    for (final map in _sortedMaps()) {
      if (map.enabled) {
        map.evaluate(state, dt);
      }
    }
    if (commitFrame) {
      state.commitFrame();
    }
  }
}
