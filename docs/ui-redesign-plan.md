# Editor workspace redesign plan

Planning baseline: 2026-10-11, commit `065b9dc`. This document proposes work;
it does not describe an implemented docking system. See [implementation progress](ui-redesign-progress.md) for the working workspace and remaining steps.

## Intent

Make the Editor a configurable creative workspace: a central canvas surrounded
by panels that can move, resize, share tabs, hide, and detach into native windows.
Keep the existing editing tools and their document semantics familiar.

This is the Editor UI slice of [the roadmap](roadmap.md), informed by
the implemented [model architecture](architecture.md). The broader Artwork → Rig → Animate → Perform direction can
follow; initially retain Place, Mesh, Rig, and Animate to avoid mixing layout
migration with a terminology and workflow migration. Environment remains a
separate mode with its existing Home entry and recording lifecycle.

## What the backend now makes possible

| Reviewed foundation | Consequence for the redesign |
| --- | --- |
| `core/document/twber_model_document.gd` owns committed data, revisions, dirty state, validated commands, snapshots, and Undo/Redo. | Panels send commands through the editor session. Moving or closing a panel must never change a document revision or become a document Undo step. |
| Native hierarchy, mesh, parameter, timeline, layer, pivot, and mirror commands have replaced legacy scene-capture authoring. | Extract the controls and tool adapters around these commands; do not introduce a second editable model or restore scene capture. |
| `TwberDocumentEditSession`, `TwberPoseEditSession`, and `editor/twber_pose_draft_controller.gd` define temporary editing state. | Panel layout and tab selection must be separate from authoring mode and draft lifecycle. Show the current editing target and commit/discard actions clearly. |
| `core/rig/twber_model_evaluator.gd` evaluates parameter tracks before sparse layer overrides; runtime and Animate share that pipeline. | The timeline must distinguish parameter keys and layer-pose keys. Rearranging the timeline must not restart playback or rebuild evaluation. |
| Rig parameter recording, Environment performance takes, deterministic sprite seeking, and transparent PNG export exist. | Include recording status, clip selection, captured sprite timing, and export in the panel inventory from the start. Reuse existing services. |
| Model format 12 carries captured sprite timing, superseding the earlier format-10 parameter-track milestone. | Preserve these tracks and the existing “Use authored sprite timing” action. Docking itself requires no model-format change. |
| `shared/twber_app_settings.gd` provides shared namespaced settings. | Store versioned workspace layouts in `editor.workspace` settings, separately from models, model history, and autosaves. |
| Environment reparents its controls into a native `Window`. | Reuse the proven ownership pattern, but implement an Editor-specific focus policy before enabling floating editing panels. This is not yet a general docking manager. |

The backend is ready for a UI migration without waiting for the full rework.
Remaining full-model command copies, 64-version history, some complete history
projections, and individually committed numeric updates remain real limits.
Docking must not add model copies, command traffic, or recompilation during drag
and resize. Compact history, numeric gesture grouping, curves, physics, PSD
import, and audio/video export are separate work.

## Proposed workspace

The initial default layout is:

| Region | Contents |
| --- | --- |
| Top | File, Edit, View, Workspace; document name and save state; Place / Mesh / Rig / Animate selector |
| Below menus | Compact options for the active tool |
| Narrow left strip | Active mode's tools, initially reusing existing icons and tooltips |
| Left dock | Layers |
| Center | One persistent canvas and its active tool overlay |
| Right docks | Inspector, Parameters, Clips; stack or combine into tabs |
| Bottom dock | Timeline and playback controls, initially shown in Animate |
| Status bar | Editing target, pose draft or recording state, operation progress, zoom |

Layers and the canvas keep their identity across modes. Common panels retain
their chosen positions; mode-specific panels return to their last locations.
Panel tab changes only choose a visible panel. The mode selector changes the
authoring context. Selecting a saved layout changes arrangement only.

The Inspector must identify what its controls affect: rest artwork in Place,
a rig pose draft in Rig, or a clip pose draft at a displayed time in Animate.
Bind and Add Point remain explicit. Parameter-track value changes currently
write keys immediately; label that state clearly instead of implying those
controls share the layer-pose draft behavior.

Move recording controls into an identifiable Parameters section, retaining
Record parameters / Finish take / Cancel take. A recording indicator remains
visible even when the panel is hidden. Keep clip duration, FPS, looping,
priority, and captured sprite timing in clip properties. Put Export PNG frames
within reach of the timeline. Do not add nonfunctional controls for future
curves, audio, physics, or video features.

Visual treatment: neutral dark surfaces, consistent compact headers, restrained
borders, readable labels, one selection accent, and visible resize handles.
Reuse the icon system. Reserve monospace primarily for numeric/time information;
evaluate a readable UI font for menus and labels with its redistribution license.
Use one spacing/type scale and scalable hit targets rather than hardcoding each
panel independently. Isolate the Editor theme so this work does not accidentally
restyle Home or Environment through `shared/default_theme.tres`.

## Docking behavior

- Drag a panel header or tab to dock left, right, top, or bottom of a group;
  drop in its center to join its tabs. Show the exact destination preview.
- Support split resizing, tab reordering, hiding, and reopening through View.
  Keep one instance of each panel; reopening focuses or restores that instance.
- Escape cancels a layout drag and restores the preceding layout. Layout drag
  data must be distinct from the existing layer-tree drag/drop payload.
- Provide panel-menu equivalents for Move, Float, and Dock so rearrangement does
  not depend solely on precise dragging. Include Lock Layout and Reset Workspace.
- Save the current layout automatically after completed layout changes; offer
  named presets through Workspace. Never write settings on every pointer move.
- Constrain sizes, scroll panel contents, and protect a usable canvas. Validate
  both 1280×720 and 1920×1080 plus high-DPI configurations; determine minimum
  sizes from working controls, not arbitrary fixed sidebar widths.
- Floating windows host the same panel instances. Closing one redocks its panels
  into their remembered groups. Restore window geometry within available screens
  after monitor removal or DPI changes. The central canvas stays in the main
  window for this scope.

## Architecture and migration constraints

`editor/editor.gd` currently wires document commands, persistence, drafts, and
mode transitions while also relying on fixed paths through the root TabContainer.
The mode scripts own their own tree/overlay controls; `EditorModelTree` inherits
`HSplitContainer`. Several tools use `visible` as their activation flag.
Simply reparenting these scenes would retain the old coupling.

Introduce three small boundaries, extracted incrementally:

| Proposed component | Owns |
| --- | --- |
| Editor session/context | Document access, centralized command dispatch, stable selected layer/parameter/clip IDs, active authoring mode, tool activation, preview inputs, playhead, and draft/recording lifecycle coordination |
| Workspace host and layout model | Registered panel IDs, split/tab structure, visibility, floating windows, layout serialization and restoration; no authored model operations |
| Canvas host | One preview, coordinate conversion, canvas bounds, picking/input routing, and the active tool overlay |

Panel scenes subscribe to context changes and issue explicit actions. Resolve
stable document IDs to current projection nodes as needed; do not persist node
instance IDs or node paths as selection. Preserve selection and expansion state
through Undo/Redo, which can rebuild the projection. Inject dependencies rather
than looking through a panel's parents or repeatedly reconnecting on reparent.

Build the initial docking host with the project's Godot controls and a small
serialized split/tab tree. Prove nested resizing and tab movement in an isolated
prototype before committing the live editor to that implementation. Add native
windows only after the in-window behavior works. No external docking dependency
is selected by this plan.

Keep the rendering backend initially. The current `ModelPreview` is a full-window
CanvasLayer with global unhandled pan/zoom input; it needs canvas-bound input and
consistent conversions once dock geometry can change. Scope pointer actions to
the canvas and keep model-space camera state independent of layout. Verify zoom
anchoring, handles, trimmed texture offsets, clipping, and pixel snapping after
resize. Prototype a clipped canvas boundary; if this requires a SubViewport,
complete a focused renderer/input parity check before migrating the tools.

Layout persistence stores a schema version, stable panel/group IDs, split ratios,
tab order and selected tabs, panel visibility, last dock destinations, and native
window geometry. Validate duplicate/missing panels and malformed sizes. Unknown
panels are ignored; new required panels receive default placements. Invalid or
unsupported layouts fall back to a usable default with a short notification.
Persist layout data only, never model resources or temporary authored poses.

## Preserve the editing lifecycle

| Event | Intended behavior |
| --- | --- |
| Move/resize/hide a panel, select a panel tab, or apply a layout preset | Preserve document, authoring mode, selection, camera, playhead, preview inputs, pose draft, and active recording. |
| Move focus between Editor-owned windows | Preserve draft and recording state. Dispatch shortcuts once to the active editor context; text fields retain their local editing shortcuts. |
| Leave the application | Preserve the existing Editor cancellation policy for unfinished gestures, pose drafts, and parameter recording. Environment's different recording policy remains separate. |
| Switch authoring mode | Preserve existing semantics: finish Place/mesh gestures and pending names as appropriate, cancel pose drafts and Rig recording, restore the outgoing preview, activate the next tool context. Handle failed commits before changing mode. |
| Change layer, parameter input, clip, or playhead; start playback | Retain the current draft invalidation rules. Make discarded-draft feedback visible. |
| Save / Export Copy / autosave | Continue the existing committed-snapshot path and its gesture/name-edit boundaries. A panel arrangement never enters model data. |
| Undo / Redo | Preserve draft-first cancellation, command history semantics, and selection restoration. A layout move never consumes document history. |

The root currently cancels on `NOTIFICATION_WM_WINDOW_FOCUS_OUT`. Replace this
with an Editor-owned window focus coordinator before enabling native floating
panels. Account for transient dialogs and focus-event ordering; switching to a
floating Inspector must not look like leaving the application. Test file-dialog
focus paths explicitly rather than blanket-disabling cancellation.

## Delivery sequence and exit criteria

1. **Capture the baseline and separate activation.** Exercise the current
   import/edit/Undo/save/reopen, rig binding, parameter take, animation, and PNG
   export journeys. Add focused regressions around mode switching and draft
   cancellation. Introduce explicit active-mode/tool state and stable selection
   while retaining the current visible layout. Exit: behavior is unchanged and
   hiding a panel is no longer the mechanism for deactivating tools.
2. **Prove the workspace host and canvas boundary.** Build the docking prototype
   with representative panels, nested splits, tabs, drop previews, cancellation,
   and resizing. Integrate the persistent canvas with verified coordinate
   conversion. Exit: docking/resizing leaves document revision and artwork
   placement unchanged, and input remains correct at all dock positions.
3. **Migrate Place and Mesh as a complete working slice.** Extract the shared
   Layers panel, contextual Inspector, tool strip, and options. Replace hardcoded
   ancestry dependencies in those modes. Exit: import, transforms, hierarchy,
   pivot/mirror, mesh edits, cancellation, Undo, and save/reopen all work in a
   rearranged layout. This is the first usable dockable-editor milestone.
4. **Migrate Rig and Animate.** Extract Parameters, Clips, Timeline, and recording
   controls; preserve context IDs and explicit draft actions. Remove remaining
   whole-workspace tab ownership after both modes pass. Exit: binding, layer and
   parameter keys, Rig takes, imported Environment takes, captured sprite timing,
   scrubbing, playback, and PNG export survive panel rearrangement.
5. **Finish persistence and recovery.** Ship automatic restore, named presets,
   View toggles, lock/reset, layout versioning, invalid-state recovery, and small
   window behavior. Exit: restart, hidden panels, malformed settings, and added
   panels always restore a usable workspace without altering the model.
6. **Add native floating windows.** Implement the focus coordinator and shortcut
   routing, then detach/redock and screen-aware geometry restore. Exit: clicking
   floating panels preserves drafts and recordings; genuine application focus
   loss still cancels as intended; closing a panel window never closes the app.
   Validate Linux and Windows, including multiple displays and DPI changes.
7. **Apply the visual system and run acceptance.** Tune spacing, typography,
   headers, separators, tool feedback, empty states, keyboard access, and busy
   states using the real migrated panels. Exit: all existing tools are reachable,
   resize does not cause model rebuilds, and the complete regression and manual
   workflow matrix passes.

The complete redesign includes native floating panels. They are sequenced after
in-window docking because their focus and input behavior has additional risk.
Do not ship a partially migrated mode with competing tree/selection authorities.

## Verification

Use the existing `scripts/test.sh` with the pinned Godot 4.7.1 and isolated
`TWBER_CONFIG_DIR`. Retain model-rework, parameter-track, recording/export,
Environment recording, sprite-clock, delivery, and GPU renderer coverage.
Update brittle scene-path fixtures to exercise stable panel/session interfaces;
do not remove behavioral assertions merely because node paths changed.

Add focused workspace tests for layout round trips and recovery, unique panel
ownership, cancelled drops, no document/history change on rearrangement, shared
selection after history projection, draft/take retention during layout changes,
and correct mode transitions. Use real graphical checks for native focus,
cross-window shortcuts, high-DPI hit testing, monitor removal, canvas clipping,
and export pixels; headless tests cannot establish those results.

Acceptance demonstrations: arrange Layers on the opposite side; tab Inspector
with Parameters; enlarge and detach Timeline; bind from a floating panel; record
and finish a Rig take; reopen an Environment take with captured sprite timing;
export matching PNG frames; restart and recover the layout; reset it; then Undo
an authored edit without touching layout history. Also remove a selected layer
and Undo, verifying that surviving panels follow restored stable IDs.

This planning pass reviewed source, scene structure, history, progress notes,
and test coverage. It did not run the application or rerun the test suite.
