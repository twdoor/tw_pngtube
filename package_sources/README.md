# Package Sources

This folder contains the editable source for Twber Environment packages. Godot can open every included script and scene directly.

- `mouse/` demonstrates a vector input, per-parameter display settings, platform-specific tracking, and a binding UI.
- `microphone/` demonstrates package-wide settings, bool/float/int mappings, thresholds, and live meters.

Every immediate child folder with a `package.json` is discovered by `tools/build_packages.gd`. Build all packages from the Godot editor:

1. Open `tools/build_packages.gd` in the Script workspace.
2. Press the script editor's **Run** button.
3. Find the generated package files under `res://packages/`.

See `docs/packages.md` for the manifest, base classes, folder-copy workflow, path rewriting, and runtime package format.
