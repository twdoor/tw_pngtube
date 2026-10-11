# Twber Tools

Twber is a Godot desktop application for creating and performing with 2D characters,
from layered PNG puppets to mesh-deformed models. **Home** opens the **Editor** or
multi-model **Environment** in the same application.

The document, Undo/Redo, shared evaluation, recording, and PNG-export foundation is
implemented. Development continues toward richer deformation, guided rigging, live
tracking, and animation production; see the [roadmap](docs/roadmap.md).

## Editor

Panels can be rearranged around a persistent canvas. Drag their thin grips to split
docks on either side, above, or below; drop into the center to form tabs. Panel
actions are available by right-clicking a grip or tab: **Float**, **Hide**, tab
ordering, and **Return to dock**. Closing a floating window redocks its panel. **View** restores hidden panels; **Workspace**
provides saved layouts, locking, and reset. The arrangement restores on launch.
Standalone panels have no title bar or menu button. Tools reflows into a single horizontal row, a vertical strip, or multiple
rows as it is resized; Reset workspace starts with a slim vertical tool strip.
Fixed panels enforce their content minimums instead of showing scrollbars.
Scrolling is reserved for growing layer, animation, and parameter lists.

To edit the UI in Godot, open `editor/editor.tscn`. The default dock arrangement
is in `editor/workspace/workspace.tscn`, panel content is in `editor/panels/`,
and shared styling is in `editor/workspace/editor_theme.tres`.

Selection follows the layer between modes. Docking and hiding panels preserve
pose drafts, recording, playback, and document history. See the
[workspace implementation notes](docs/ui-redesign-progress.md) for remaining work.

- **Place**: arrange layers, groups, textures, animated sprites, pivots, visibility,
  opacity, and clipping. Duplicate, mirror, and reparent layers with their bindings.
- **Mesh**: create deformation meshes, move/remove vertices, cut/join edges, and
  generate grids.
- **Rig**: create Bool, Int, Float, and Vector2 controls; bind sparse poses and
  animation triggers; preview several controls together.
- **Animate**: key rig parameters or layer poses, preview clips, and export PNG frames.

Pixel art mode snaps transforms, pivots, mesh points, and deformations. Rotation
increments are configurable; the preview supports zooming up to 32×. Texture import
can trim transparent borders while preserving placement; animated frames share a
crop to avoid jitter. Animated-sprite poses include selection and frame rate.

### Editing and saving

Document Undo/Redo uses Ctrl+Z and Ctrl+Shift+Z or Ctrl+Y. Place drags and Mesh
strokes commit as one edit; Escape cancels an unfinished gesture. Save finishes
pending Place/Mesh edits. History retains 64 edits.

Rig and Animate pose edits are temporary drafts until **Bind** or **Add Point**.
Escape or Undo discards the draft first. Changing the editing context or leaving
the application also discards it; moving focus to an Editor panel window preserves it.
Drafts do not mark the document dirty and are omitted
from Save, Export Copy, and autosave. Committed data is independent of preview poses
and camera movement.

New, Open, Home, and close prompt for Save, Discard, or Cancel when needed. Autosave
writes a recovery copy after editing pauses and offers recovery on the next launch.
See [application data](docs/application-data.md) for library, settings, and recovery paths.

### Animation and recording

Select a clip and **Parameter track** in Animate. Scrub, then change its value or
use **Key parameter**. Float and Vector2 keys interpolate unless **Hold until next
key** is enabled; Bool and Int keys hold. Green circles mark parameter keys.
Layer-pose tracks override only their keyed properties. Active clips resolve conflicts
by priority, then stable clip ID. Duration changes cannot cut off existing keys.

In Rig, **Record parameters** captures control changes. **Finish take** creates a
clip as one Undo step and opens Animate. Values hold until the next observed change.
Cancel, Escape, changing authoring modes, leaving the application, or editing the document discards
an unfinished take; saves omit it.

In Environment, **Record performance** captures the selected model after input mapping,
smoothing, and triggered clip evaluation. Selection changes and detached controls
keep recording the original instance. **Finish and save take** writes a separate
`.twber` copy under `models/takes/`. Open it in Editor or use **Export last take PNGs…**.
Failed saves retain the take for Retry save or Save elsewhere; Home stays disabled
until it is saved. Cancel or removing/replacing the recorded model discards the take.

Performance takes contain parameter keys, held property keys for channels owned by
triggerable clips, and sprite timing markers. These preserve mid-animation starting
frames, pauses, switches, and speed changes. Sprite-only models can also record.
Stage movement is excluded; unsaved recordings have no crash recovery.

Captured tracks override later edits on their owned channels. **Use authored sprite
timing** in Animate removes sprite markers for the clip, with Undo support. Scrubbing
and export share deterministic timing: authored speed curves use 240 Hz sampling;
recorded markers preserve observed live phase directly.

**Export PNG frames…** writes a transparent sequence into a new folder using a
committed clip snapshot. Choose canvas size, frame rate, scale, and center. Frames
sample `index / fps` before the clip end; a JSON manifest records their times.
Cancellation removes partial output. Export requires a graphics backend.

## Environment and packages

Load multiple models onto a stage, drag to position, use the wheel to scale, and
configure each instance independently. The stage remembers model/image paths,
stacking, selection, position, and scale. Each instance has its own live input profile;
profiles persist by loaded model path.

Streaming software can capture the Environment window. Detach the Parameters/Packages
dock into its own native window for a stage without visible controls; closing the
detached window embeds it again.

Bundled PCK packages provide mouse tracking, microphone level (disabled by default),
model/image attachments, and saved backgrounds. Packs can install trusted third-party
packages and remove user-installed ones. Updates/removals of mounted packages require
a restart. See [package documentation](docs/packages.md) for building and extending them.

## Files and development

`.twber` is the primary editable archive format: versioned model data, checksummed
textures, atlases, lossless images, and desktop GPU variants. Current saves use
**model format 12**. Legacy `.tres`/`.res` and JSON/base64 `.twber` files remain readable.
Export Copy does not change the current document path. Archive I/O uses background
jobs; texture preparation still runs on the main thread and can pause large saves.

Models, settings, autosaves, and managed packages share the OS application-data
root. `TWBER_CONFIG_DIR` overrides it for portable installs or testing. File dialogs
start in `models/` and can access external files.

Use the Godot version pinned in `.godotrc`. Run the maintained suite with
`GODOT=/path/to/Godot ./scripts/test.sh`.

- [Architecture](docs/architecture.md): ownership, editing, evaluation, recording, and source map.
- [Performance](docs/performance.md): textures, archives, batching, and benchmarks.
- [Testing](testing/README.md): regression suites and graphics requirements.
- [Releasing](docs/releasing.md): desktop builds, checksums, and publication.
- [Roadmap](docs/roadmap.md): remaining work and first-major-release acceptance.

MIT License. See [LICENSE](LICENSE).
