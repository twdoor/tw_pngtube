# Tests

Use the Godot version pinned in `.godotrc`:

```bash
GODOT=/path/to/Godot ./scripts/test.sh
```

The runner imports the project, builds bundled PCKs, runs headless regressions,
then runs OpenGL renderer and recording/export checks. It uses `xvfb-run` when
available; otherwise a working desktop display is required. Headless rendering
cannot validate PNG output. The graphics runs intentionally repeat the recording
workflows to check their behavior with real textures and rendering.

| Suite | Coverage |
| --- | --- |
| `run_tests.gd` | Texture handling, parameter/runtime evaluation, sparse channels, atlas/batch lifecycle, archive compatibility, editor open/save/recovery |
| `test_document_editor.gd` | Document ownership, validation, atomic history, hierarchy, mesh gestures, rig/clip commands, assets, and pose drafts |
| `test_parameter_tracks.gd` | Parameter tracks, priorities, reference composition, serialization, shared editor/runtime playback |
| `test_recording_export.gd` | Rig parameter recording, editable takes, fixed-time PNG export and cancellation |
| `test_environment_recording.gd` | Mapped live input, triggered performance recording, instance isolation, save retry, prepared archive isolation, exported pixels |
| `test_sprite_clock.gd` | Live/recorded sprite phase, pauses and switches, seeking, commands, trigger playback, exported pixels |
| `test_environment.gd` | Stage, package lifecycle, profiles, workspace persistence, independent instances |
| `test_delivery.gd` | Launcher, data directories, settings persistence, release asset selection |
| `test_renderer.gd` | GPU triangles, atlas batching, transparency, dirty updates, sprite-frame UVs |

The runner isolates application settings with a temporary `TWBER_CONFIG_DIR`.
Some fixtures use Godot's `user://` directory, so do not run suites concurrently
against the same project/user-data directory. Individual scripts can be run with
`--path . --script testing/<suite>.gd`; add `--headless` only for non-pixel runs.
Check output for script errors as well as the process exit code.

`benchmark_runtime.gd` and `benchmark_renderer.gd` are optional diagnostics, not
pass/fail regressions. See [performance notes](../docs/performance.md). Local artwork,
manual scenes, and experiments under this directory are ignored and are not required
by the maintained suite. Tests are excluded from application exports.
