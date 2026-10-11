# Twber Tools

Twber Tools is a Godot-based toolset for building PNGTuber models, from simple layered sprite puppets to more complex mesh-deformed characters.

The application opens on **Twber Home**, where the **Twber Editor** can be used
to assemble models and the **Twber Environment** can load and puppeteer them
with modular input packages. Both modes ship in one application and can return
to the home screen without starting a second executable. Home stays focused on
choosing the Editor or the multi-model Environment.

## Status

This project is in active development. The editor is usable for core model authoring, and the environment now has its initial model-loading, parameter-control, input-registry, and mouse-input foundation.

## Current Editor

The editor is organized into four main tabs:

- **Place**: create and arrange layers, sprite layers, animated sprite layers, nested groups, visibility, opacity, clipping, duplication, deletion, and texture assignment.
- **Mesh**: convert texture layers into editable deformation meshes by placing vertices, editing/removing vertices, cutting mesh edges, and joining vertices.
- **Rig**: create bool, integer, float, and 2D vector parameters; bind complete layer states at parameter positions; compose and preview several parameters at once; and edit layers with transform, pivot, mesh-deformation, selection, and reset tools.
- **Animate**: create timeline clips, key rig parameters or layer poses, and preview playback through the same evaluator used by live models.

Pixel art mode is available in Settings. It snaps layer transforms, pivots, mesh points, deformations, parameter previews, scale, and rotation while keeping the rotation increment configurable. The preview supports zooming up to 32× for pixel-level editing. Animated-sprite parameter states include both the selected animation and its frame rate.

Texture imports can remove empty transparent borders before GPU compression. The crop keeps the artwork at its original pixel density and records its original canvas, crop rectangle, alpha bounds, and logical offset so placement and mesh tools remain accurate. Animated frames use a shared crop to prevent frame-to-frame movement.

The editor also repacks compatible preview textures into in-memory atlases. Meshes render indexed triangles directly through Godot's canvas rendering server—there is no `Polygon2D` child per mesh. Compatible unmasked layers sharing an atlas are flattened into one dynamic batch while their editable scene nodes remain available for tools and parameter binding.

## Environment

The environment can place multiple `.twber`, `.tres`, and `.res` model instances on one stage. Each model can be selected, dragged, scaled with the mouse wheel, removed, and configured independently; the parameter panel follows the selected model while package inputs continue updating every model with matching bindings. Its UI is composed from Godot scenes, including reusable model-instance and parameter-control scenes.

For now, streaming software should capture the main environment window directly. The compact Parameters/Packages dock can be detached into its own native controls window, leaving the captured stage free of visible interface elements; closing that window embeds the dock again.

The included packages are mouse tracking, microphone level, model attachments, and stage backgrounds. They are loaded at runtime from their files under `packages/`; the environment has no direct scene or script reference to their implementations. Mouse tracking publishes a global `mouse.position`; each bound vector parameter selects the display it should interpret, producing normalized model-space coordinates from `(-1, -1)` to `(1, 1)` with positive Y pointing up. The microphone package publishes RMS-smoothed `microphone.level_db` from `-80 dB` to `0 dB`; it is disabled by default and can be enabled from Packages. The attachment package lets an image asset or model dropped over another model follow that model until it is dragged away. The background package provides saved solid-color and custom-image stage backgrounds. Package settings and parameter-binding controls are scenes carried inside their respective PCK.

The Packs tab can install trusted third-party PCKs, open the managed package
folder, distinguish bundled packages from user-installed ones, and remove user
packages. Updates and removals of already mounted packages are applied after a
restart, matching Godot's resource-pack lifecycle.

The environment automatically saves each model's input profile locally, keyed by its loaded path. Every stage instance keeps its own live copy of that profile, so multiple loaded models can animate together while switching selection only changes which controls are shown.

The Environment also persists the current stage as a lightweight workspace.
Model and image references, stacking order, selection, position, and scale are
restored on the next Environment launch.

Application, editor, environment, and model-profile preferences share an atomic,
human-readable `settings.cfg` in Twber's operating-system application-data
directory. Models default to its `models/` library, while environment package
PCKs live in `packages/`, so documents, settings, and installed extensions can
be managed from one place. Bundled packages are synchronized there before
discovery. Sections remain namespaced by mode. `TWBER_CONFIG_DIR` can override
the complete directory for portable installs and automated tests.

The File menu includes a **Model Performance** report for estimated draw calls, texture memory, mesh complexity, clipping, animation frames, parameter positions, and saved transparent pixels.

## Model Formats

- `.twber`: the primary editable model format, stored as a versioned archive containing a binary model, checksummed texture files, atlases, lossless fallback images, and desktop GPU-compressed texture variants.
- `.tres` / `.res`: legacy editable Godot model resources retained for compatibility.

The editor can open, edit, and save current `.twber` archives in place, as well as legacy resources and JSON/base64 `.twber` packages. New models default to `.twber`; loading and archive saving run as background jobs with visible status so the interface remains responsive. Export Copy writes another `.twber` without changing the current document.

Editor save/open dialogs and the Environment model picker start in the shared
`<Twber data>/models/` library. They retain filesystem access so external models
can still be deliberately imported or exported.

The Editor tracks unsaved changes across Place, Mesh, Rig, and Animate. New,
Open, Home, and application-close actions require Save, Discard, or Cancel when
the document is dirty. After editing pauses, Twber writes a recovery copy under
`<Twber data>/autosaves/`; the next Editor session offers to recover it, and a
successful normal save removes it.

The Edit menu provides document Undo/Redo (Ctrl+Z, Ctrl+Shift+Z or Ctrl+Y).
Place transform drags commit once on release; Escape cancels an unfinished drag.
Layer creation, deletion, duplication, and reparenting are document commands.
Duplicating a group also copies its rig poses and timeline keys; hierarchy Undo
restores those dependencies together.
Save, Export Copy, and autosave use committed document snapshots, keeping camera
movement and live rig/animation previews out of authored rest poses. History is
currently limited to 64 edits; numeric inspector controls commit once per update.
Mesh vertex drags and continuous remove/cut strokes now commit as one Undo step.
Escape or Undo cancels an unfinished mesh gesture; Save commits it before writing.
Rig parameter creation, settings, deletion, pose binding, and animation triggers
also use document commands. Parameter-name typing commits as one Undo step on
Enter or focus loss; Save finishes pending name edits. Binding isolates the
selected parameter from other active parameters using document data. Range and
step changes cannot displace or merge existing poses or animation triggers.
Timeline creation, settings, key recording/removal, and clip deletion also use
document commands. Deleting a clip removes its parameter triggers in the same
Undo step. Animation names commit once per text edit; duration changes cannot
cut off existing keys, and FPS changes leave authored key times intact.
Pivot, mirror, Place inspector settings, texture replacement, and sprite-animation
management now use document commands as well. Pivot rebases rig samples and
timeline keys; Mirror copies both. Renaming/deleting a sprite animation updates
its pose references. The legacy scene-capture authoring adapter has been removed.

Rig and Animate pose edits now live in explicit temporary drafts. Releasing a
drag keeps the draft available; Bind or Add Point commits it as one Undo step.
Escape or Undo discards the draft first. Changing layer, parameter input, clip,
playhead, workspace, or window focus also discards it; starting playback restores
the recorded pose. Parameter and clip renames preserve the draft. Save, Export
Copy, and autosave include only committed poses, and drafts do not mark the
document dirty. The status bar and Edit menu indicate when a draft is active.

To animate a rig control, select a clip and a **Parameter track** in Animate.
Scrub to a time, then change its value to create or update a key; **Key parameter**
also records the displayed value. Green circles mark the selected parameter's
keys. Float and Vector2 tracks interpolate linearly unless **Hold until next key**
is enabled; Bool and Int tracks always hold. These controls commit immediately
and support document Undo/Redo. Layer-pose keys override only their keyed
properties after parameter evaluation. When live triggers activate several clips,
higher clip priority wins; equal priorities use stable clip IDs.

Parameter tracks and clip priority are saved in model format 10. Existing models
load with empty parameter tracks and default priority. New saves require a
format-10-capable Twber version.

In Rig, **Record parameters** captures changes to the parameter controls.
**Finish take** creates a new clip as one Undo step and opens Animate. Recorded
values hold until the next observed change, preserving their original timestamps.
Escape, Cancel take, changing workspaces, losing window focus, or editing the
document discards an unfinished take; saves exclude it.

In Environment, **Record performance** captures the selected model after input
mapping, smoothing, normalization, and triggered clip evaluation. Selecting another model, moving focus,
or detaching the controls keeps recording the original instance. **Finish and
save take** writes a separate `.twber` copy under `models/takes/` in the application
data folder. Open that copy in Editor to edit its take in Animate, or use
**Export last take PNGs…** directly. Previous takes stay in the library. Failed
saves keep the take in memory for Retry save or Save elsewhere; Home stays disabled
until it is saved. Cancel, removing the recorded instance, or replacing its model
discards an active recording. Triggered parameter output becomes parameter keys;
triggered layer motion becomes editable hold keys, including release to the rig pose.
Only channels owned by triggerable clips are baked into layer tracks, so those
tracks override parameter edits affecting the same channels until removed or edited.
Captured poses hold between observed frames. Animated sprites retain their starting
frame phase, animation switches, pauses, and speed changes; sprite clocks advance
between captured timing markers. Sprite-only models can also be recorded. Stage
movement remains outside model takes.

Captured sprite timing takes precedence over animation-selection and speed edits.
In Animate, **Use authored sprite timing** removes those markers for the selected
clip so the rig and timeline control sprite playback again; Undo restores them.
Scrubbing and PNG export share a deterministic clock. Authored speed curves use a
fixed 240 Hz integration grid plus explicit key boundaries; recorded timing markers
preserve the observed live phase directly.

In Animate, **Export PNG frames…** writes a transparent image sequence into a new
folder. Choose the parent folder, canvas size, frame rate, scale, and canvas center.
The export uses a snapshot of the committed clip and ignores the editor camera
and unfinished drafts. Frames sample `index / fps` before the clip's end; a JSON
manifest records those times. Cancellation removes partial output, and existing
export folders are preserved. Export requires a graphics backend; Godot's
headless renderer cannot produce PNG frames.

Parameter samples are compiled when a model changes: scalar positions are sorted once, 2D triangulations are cached, layer lookups are reused, and unchanged pose channels are stored sparsely. `TwberRuntimeModel` provides the environment-facing model node, batched parameter updates, immutable neutral poses, atlas preparation, direct canvas batching, and dirty-parameter evaluation that updates only affected layers and render-buffer slices.

## Project Layout

```text
editor/        Editor UI, tabs, preview, and authoring tools
environment/   Runtime environment UI, reusable controls, core input contracts, and packages
launcher/      Home screen, mode selection, settings access, and application updates
package_sources/ Editable package projects and included implementation examples
packages/       Distributable package PCK files loaded by the environment
shared/        Code and assets shared by the editor and environment app
shared/model/  Model resources, mesh data, runtime mesh node, and serialization/export codec
shared/assets/ Shared icons and UI assets
```

See [Performance Architecture](docs/performance.md) for the import, package, evaluation, and runtime design.
See [Twber Rework Plan](docs/rework-plan.md) for the proposed document architecture, authoring workflows, and first-major-release milestones.
See [Twber Package Format](docs/packages.md) for package manifests, discovery, building, installation, and security.
See [Twber Application Data](docs/application-data.md) for the shared settings, model-library, and package paths.
See [Releasing Twber](docs/releasing.md) for tests, exports, AppImage creation, checksums, and tagged releases.

## Roadmap

- Continue improving the editor workflow for layered and mesh-deformed models.
- Improve microphone calibration and input smoothing controls.
- Add package provenance/signature support before introducing a public package
  catalog.

## License

MIT License. See [LICENSE](LICENSE).
