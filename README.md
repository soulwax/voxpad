# voxpad

Pure Dart contextual input action mapping, deadzone processing, chord combos, input buffering, interactive rebinding, JSON profiles, and virtual touch gamepads.

## Features

- **Action Maps & Priorities (`ActionMap`, `InputActionAsset`):** Context-aware mappings (`Gameplay`, `UI`, `Vehicle`) with priority ordering and automatic lower-map control consumption.
- **Composite Bindings:**
  - `KeyBinding` (keyboard, mouse, gamepad buttons)
  - `ChordBinding` (unordered or ordered simultaneous key chords e.g. `Ctrl+Shift+S`)
  - `Axis1DBinding` (digital +/- pairs + optional analog axis)
  - `Vector2Binding` (WASD/D-pad + analog sticks with deadzone pipeline)
- **Deadzone & Curve Processing (`DeadzoneProcessor`):** Axial, Radial, and Scaled Radial deadzones with response curves (`exponent`).
- **Input Buffering & Hold Timers:** Built-in `heldDuration` and `consumeBufferedPress(window)` for responsive platformer jumps and combat combos.
- **Interactive Rebinding (`InputRebinder`):** Live press listening, conflict detection/resolution (`swap`, `overwrite`, `reject`), and JSON profile save/load.
- **Virtual Touch Gamepad (`VirtualGamepad`):** Floating or fixed on-screen analog sticks and touch buttons that emit directly into the same physical control stream.
