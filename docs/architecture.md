# Model architecture

Twber's document and playback foundation is implemented. This describes current
behavior; [the roadmap](roadmap.md) covers the remaining authoring and production
features. Texture preparation, archives, and batching are detailed in
[performance.md](performance.md).

## Ownership

| Component | Responsibility |
| --- | --- |
| `TwberModelDocument` | Owned model data, validation, revisions, atomic commands, Undo/Redo, saved-state checkpoints |
| `TwberDocumentSnapshot` | Detached committed data for persistence, evaluation, and export |
| Editor tools and edit sessions | Selection, camera, temporary gestures and pose drafts; authored changes go through commands |
| `TwberModelEvaluator` | Scene-free parameter and timeline evaluation from model data |
| `TwberRuntimeModel` | Per-instance inputs, trigger playheads, sprite clocks, and projection into render nodes |
| `TwberModelTake` | Owned recording snapshot and native parameter, property, and sprite timing tracks |
| `TwberFrameExporter` | Isolated fixed-time playback and transparent PNG rendering |

Render nodes are disposable projections, not the saved document. Runtime instances
have independent input values and clocks. Save, Export Copy, and autosave use
committed snapshots; a worker finishing an older save cannot mark newer edits clean.

## Editing

Commands validate before publishing one change set. Failed commands leave data and
history unchanged. Undo/Redo restores dependent rig samples, timeline keys, hierarchy,
and mesh topology together. History currently holds 64 edits.

Place drags and Mesh strokes accumulate in edit sessions and commit once. Escape
or Undo cancels an unfinished gesture. Save completes pending Place/Mesh edits.
Rig and Animate pose drafts instead require Bind/Add Point to commit; saving omits
them, and changing the editing context discards them. Parameter and clip names commit
on Enter or focus loss. Input edits and playback cannot overwrite rest poses.

Layer duplication/removal, pivot changes, and sprite-animation rename/removal update
references in rig samples and clips. Duration edits cannot truncate keys. FPS changes
do not move authored key times.

## Evaluation and timing

The shared evaluator normalizes external inputs, applies active parameter tracks,
evaluates the rig, then overlays sparse property tracks. Missing channels preserve
prior contributions. Higher clip priority wins; equal priorities use stable clip IDs.
Triggers read external input values, avoiding feedback from clip-driven parameters.
Float and Vector2 parameter tracks interpolate or hold; Bool and Int tracks hold.

Live sprites advance an explicit clock using the previous evaluated rate. Rate changes
preserve phase, zero pauses, and animation selection changes restart playback.
`TwberSpriteFrameSampler` projects clock states into frames using relative frame
lengths, loop wrapping, and nonloop clamping.

Animate scrubbing and PNG export use `TwberSpriteTimeline`. Authored speed curves
integrate on a fixed 240 Hz grid plus key/switch boundaries, independent of seek
order and export FPS. This is numerical sampling, not analytic integration; rapid
parameter-driven switches can quantize to that grid. Backward seeks through long,
varying-speed clips may require replaying the grid. Constant-rate clips use a direct path.

## Recording and persistence

Rig recordings store observed parameter changes. Environment recordings capture
resolved parameters and sparse property channels owned by triggerable clips,
including release back to the rig. Property values hold between observations.
Sprite markers preserve the initial live phase, rate/selection changes, and phase
jumps; they advance continuously between markers. Constant-rate runs compact to
one anchor. Parameter, property, and sprite tracks share a 200,000-key limit.

Captured property and sprite tracks override later edits on their owned channels.
Animate's **Use authored sprite timing** clears sprite markers in one undoable edit.
Live triggers can replay recorded takes. Stage movement is outside model takes.
Active recordings and failed-save copies remain in memory until saved; recording
crash recovery is not implemented.

Model format **12** stores parameter tracks, held property keys, and sprite markers.
Older archives default missing tracks to empty and legacy property interpolation to
linear. Validation checks references, timing bounds, finite values, and sprite-track
starting anchors. New saves require a format-12-capable Twber version.

Texture reads/compression and export preparation run on the main thread. Archive
workers receive prepared dictionaries and byte buffers for atomic ZIP writing.
Large texture preparation can still stall interaction. Ordinary model files contain
data; executable PCK extensions use a separate package contract.

## Source map

- `core/document/`, `core/commands/`: document, validation, history, editing sessions.
- `core/rig/`, `core/animation/`, `core/input/`: evaluation, recording, clocks, input mapping.
- `editor/`: tools, document projections, export UI.
- `environment/`: live stage, per-instance controls, packages, recording UI.
- `shared/model/`: model resources, codec, runtime integration, rendering adapters.
- `rendering/`: offline frame export.
- `testing/`: maintained regressions and optional benchmarks; see [testing guide](../testing/README.md).
