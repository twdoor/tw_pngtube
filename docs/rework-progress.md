# Rework implementation progress

## First increment — 2026-10-11

This increment starts the [rework plan](rework-plan.md). It does not complete P0
or P1, and does not switch the whole application to the new document API.

### Fixed in the existing application

- Inactive Animate tabs no longer restore stale cached poses over Place edits
  during save capture or workspace changes. Only an active animation preview
  session may restore its captured base.
- Timeline samples preserve their authored channel masks at endpoints and
  between keys. A color-only timeline leaves parameter-driven position intact.
- Place rest-transform changes use a shared authored-data operation that rebases
  both parameter poses and timeline keys. Sparse channels remain sparse.

### New document boundary

`TwberModelDocument` owns a private copy of the existing `TwberModelResource`
schema. This is a compatibility foundation; the full new model/asset schema is
still a design task. Its operations require no scene nodes or scene tree.

- `replace_model(resource)` validates and copies an imported model. Invalid
  input leaves the current document intact; diagnostics are available through
  `get_diagnostics()`.
- `execute(command)` applies to an isolated candidate and publishes only after
  validation. Compound commands either commit together or leave no changes.
- `undo()` / `redo()` restore authored data, including dependent samples. Each
  committed operation emits a typed change set and increases the revision.
- Dirty state follows the saved history state, including Undo/Redo and branches.
- `snapshot()` captures an isolated revision. Consumers get disposable resource
  copies, so renderer or serializer mutations cannot modify the snapshot.
- `mark_saved(snapshot)` records the state actually written. Completing an old
  save leaves newer edits dirty; a snapshot from a previously opened document is
  rejected. Call it only after successful persistence. The caller must serialize
  writes to a destination; this class does not schedule I/O.

The initial command is `TwberSetRestTransform`; `TwberCompoundCommand` groups
operations. The legacy Place adapter shares the same rebasing rules, but still
uses its existing scene storage. It does not mirror a second editable document.

`TwberDocumentPreview` is a one-way Godot adapter. It rebuilds from snapshots and
keeps per-preview parameter values. Two previews can display different poses of
one document without mutating authored data. It is tested independently and is
not yet the main editor's preview node.

### Current limits and next integration work

- The main editor still uses legacy scene capture and has not acquired a global
  Undo/Redo interface. New document history is available to new command clients.
- History currently retains at most 64 complete model versions. Compact inverse
  patches and independent immutable asset storage are needed before large-model
  rollout. The preview also rebuilds on changes; incremental projection is pending.
- Validation covers identity, hierarchy, finite transforms, mesh index bounds,
  pose topology counts, and rig/timeline references. It is not the finished format
  validator or a migration/repair service.
- Persistence continues to use the existing codecs. A document snapshot can be
  passed directly to ResourceSaver without touching a preview; revision-aware
  archive jobs, migrations, and the new format are pending.
- Runtime evaluation is still the existing scene-based evaluator behind the
  adapter. The pure evaluator, compiled definition, and shared clock are pending.
- Pivot edits, topology edits, reparenting, rig authoring, and timeline editing
  still need their own shared commands and migration into the document owner.
- Deformer, mask, PSD, tracking, media-export, and topology-transfer investigations
  from P0 remain open; this increment does not freeze those schemas.

Next: build the asset/document schema and edit-session contracts, then migrate a
complete authoring workflow to the document owner and snapshot persistence.
Remove its legacy write paths as it moves; do not synchronize two authoritative
stores. Reuse the shared rest-transform command as the first tool operation.

### Validation

`testing/test_model_rework.gd` is part of `scripts/test.sh`. It covers the two
original regressions, save/reopen and tab transitions, input/snapshot isolation,
atomic command failure, dependent pose rebasing, Undo/Redo save identity, stale
save completion, structural validation, and independent document projections.

The first implementation passed the complete repository test script with the
pinned Godot 4.7.1 editor: model regressions, the new rework suite, environment,
delivery, package builds, and real OpenGL renderer pixel tests.

## Second increment — main editor document ownership

The main editor now owns a `TwberModelDocument`. Opening and creating a model
replace its state; Undo/Redo rebuild the editing projection from that state.
This supersedes the first increment's integration limitations above.

- The Edit menu exposes Undo/Redo, with Ctrl+Z, Ctrl+Shift+Z, and Ctrl+Y.
  Dirty state follows the saved document state when moving through history.
  Layer selection and viewport pan/zoom survive history projection.
- Place move/rotate/scale drags execute `TwberSetRestTransform` on release.
  Pointer motion changes only the temporary projection; Escape or Undo during
  the gesture cancels it without consuming an earlier history entry. Parameter
  poses and animation keys are rebased in the same transaction.
- The remaining tools enter through `TwberCommitLegacyEdit`. An explicit
  authoring signal queues a commit at the end of the current event; tab changes,
  history actions, and saves flush it. Rig and Animate supply their authored
  base values without restoring the displayed pose. Camera transforms are
  excluded. Invalid drafts block saving and workspace changes; Undo discards an
  invalid draft and restores the last committed document.
- Save, Export Copy, and autosave serialize isolated document snapshots.
  Saving no longer stops playback or restores scene nodes. Successful saves
  mark the exact captured history state clean. Normal background saves wait for
  an active autosave; a document replacement invalidates an old autosave's
  completion so it cannot publish stale recovery data.
- Opening an invalid model leaves the document and current path intact.
  Recovering an autosave explicitly invalidates the save checkpoint.
- Layer deletion prunes both parameter samples and timeline keys. Existing mesh
  topology maintenance now includes timeline mesh samples and preserves sparse
  channel masks. Undo restores their preceding data together.

### Remaining migration work

The legacy ingress is temporary: it still captures an entire authored candidate
from the tool workspace after an edit signal. Native commands must replace it
for hierarchy, pivot, mesh, rig, and timeline operations. This is not a continuous
bidirectional synchronization loop; the document owns committed state, history,
and persistence, while legacy tools retain a mutable draft until commit.

Legacy sliders and mesh gestures can currently produce one history entry per
update. They need edit-session grouping and cancellation. History still retains
64 complete versions, and Undo reconstructs the scene; compact patches,
independent asset storage, incremental projection, and preserving playback state
through Undo remain future work. Existing mesh insertion/reset rules are retained;
this does not implement the planned topology-transfer solver.

The existing archive codec and its normalization rules remain in use. This
increment does not introduce the new file format, pure evaluator, compiled-model
schema, deformers, or other remaining P0 investigations.

Next: introduce native hierarchy and mesh commands with gesture edit sessions,
then migrate rig and timeline authoring away from the legacy capture adapter.

### Validation

The complete `scripts/test.sh` suite passes with Godot 4.7.1, including package
builds, model, environment, delivery, and OpenGL renderer tests. Rework tests now
exercise the main editor's history/save checkpoints, gesture cancellation,
legacy inspector and rig commits, background saving during playback, camera
isolation, dependent layer deletion, topology edits, invalid open handling, and
stale autosave completion across document replacement.

## Third increment — native layer hierarchy commands

Place creation, deletion, duplication, and drag/drop now execute resource-only
commands (`TwberCreateLayer`, `TwberDeleteLayers`, `TwberDuplicateLayers`, and
`TwberReparentLayers`). Their old scene-mutating implementations have been
removed. A pending legacy edit is committed before a hierarchy action begins;
the action itself does not capture the scene or queue another legacy commit.

- Creation takes a detached layer and asset payload, allocates unique layer and
  texture IDs, and resolves sibling names. Sprite and animated-frame imports use
  this path. Redo restores the same IDs and assets.
- Duplication copies a selected subtree, remaps all descendant IDs, and copies
  its parameter samples and timeline keys. Channel masks remain sparse. A
  selection containing both a group and its child duplicates that subtree once.
- Deletion removes the subtree and dependent poses/keys in one transaction.
  Other layers, samples, and timeline clips remain available. Assets are retained
  in the document; unreferenced-asset collection is a separate future concern.
- Reordering/reparenting uses stable parent and sibling IDs. Rest transforms,
  parameter poses, and timeline transforms are converted into the new parent's
  neutral coordinate space. Cycles, missing references, singular destinations,
  and transformations requiring skew are rejected before publication. Dropping
  layers into their existing order creates no history entry.
- `TwberHierarchyProjection` updates the committed hierarchy while preserving
  surviving node instances and camera transforms. It creates only new nodes and
  removes only deleted ones; editor-local tree IDs survive structural reloads.
  Undo/Redo still use the existing complete document projection.

### Reparenting contract and limits

The command preserves rest artwork and authored samples with parents at their
neutral transforms. It does not bake animated ancestor motion: after reparenting,
children inherit motion from their new parents. The v9 format lacks a skew
channel, so a move involving rotated nonuniform scales may be refused with an
explanation instead of silently deforming the artwork. A new transform schema
and richer pose-transfer policy remain part of the broader rework.

Mirror and pivot tools, mesh authoring, parameter authoring, and timeline editing
still use the temporary legacy adapter. Mirror retains its own geometry/binding
semantics and has not been silently redirected through ordinary duplication.
History remains bounded to 64 full document versions.

Next: native mesh commands and gesture edit sessions, then the remaining rig and
timeline command migrations.

### Validation

Added tests for subtree ID remapping, sparse rig/key copying, dependent deletion,
Undo/Redo identity, world-space rest/sample preservation, cycle and shear
rejection, no-op moves, asset payload isolation, editor command routing, surviving
node identity, and archive round trips with imported sprites and animated frames.
The full repository suite passes with the pinned Godot 4.7.1 editor, including
package builds and OpenGL renderer tests.

## Fourth increment — native mesh editing and gesture drafts

Mesh authoring now executes `TwberEditMesh` commands for vertex insertion,
removal, movement, edge cut/join, and grid generation. Mesh no longer emits legacy
scene-capture events or directly modifies rig/timeline resources. The existing
triangulation, grid, and edge-constraint algorithms have moved out of the drawable
node into `TwberMeshGeometry`, shared by commands and the runtime node.

`TwberDocumentEditSession` owns an isolated baseline and draft. Pointer updates
execute native commands against that draft and publish no document revisions.
Move gestures recompute from their baseline, while remove/cut strokes accumulate
operations. Release commits the final validated draft as one history step.
A drag that returns to its starting position creates no step. A draft cannot
commit after its document revision changes, and cancellation cannot later commit.

- Escape or Undo during a gesture discards only the draft. Undo after release
  reverses the complete gesture, including dependent rig and timeline poses.
- A mouse release outside the mesh overlay still finishes the gesture. Selecting
  another layer or tab also finishes it; losing window focus cancels it.
- Save finishes the gesture before taking a snapshot. Autosave defers unfinished
  gestures. Document replacement discards any remaining draft.
- `TwberMeshProjection` updates the affected mesh without rebuilding unrelated
  nodes. Sprite/mesh conversion preserves children, placement, and prepared
  textures. Removing the final vertex can itself be previewed and cancelled.
- Moving vertices shifts existing mesh poses by the same rest delta. Insertion
  and removal maintain corresponding indices; sparse non-mesh channels and
  empty mesh overrides remain sparse.

### Remaining limits

Drafts currently copy the compatibility model and validate it on each update.
Their retained state is bounded to one baseline and one draft, rather than an
entry per pointer event, but this is not yet the compact patch/immutable asset
architecture needed for very large models. History still keeps up to 64 complete
versions. Grid regeneration keeps the existing policy of resetting authored mesh
poses to the generated geometry; a topology-transfer solver remains pending.

The current mesh renderer cannot preserve flipped sprite conversion in all
intermediate states. The command now refuses that conversion with an explanation
instead of silently dropping the flip. Mirror and pivot operations, rig authoring,
and timeline editing still use the temporary legacy adapter.

Next: native parameter and pose-binding commands, using the same edit-session
boundary for rig authoring; then timeline authoring and the remaining pivot/mirror
migrations.

### Validation

Tests cover resource-only mesh operations, dependent pose offsets, repeated/no-op
edits, atomic failure, draft isolation and stale commits, single-step gesture
Undo/Redo, cancellation, outside release, selection/tab changes, focus loss,
save/autosave boundaries, sprite/mesh conversion, grid generation, and document
replacement. The complete repository suite passes with Godot 4.7.1, including
model/environment/delivery tests, package builds, and OpenGL renderer tests.


## Fifth increment — native parameter and binding commands

`TwberEditParameter` now owns parameter creation, settings, deletion, pose
binding/removal, and animation trigger binding/removal. These operations use
stable IDs, operate on isolated document candidates, and no longer emit Rig's
legacy scene-capture signal. Deletion and Undo restore the parameter's settings,
poses, and triggers together; the referenced timeline clips remain independent.

`TwberRigSampling` reuses the existing compiled sampling/composition math against
resource data. Bind takes an explicit copy of the edited pose and current preview
inputs, subtracts the other parameters' contributions, and stores sparse channels.
It reproduces the existing pixel-snapping rules without temporarily restoring and
evaluating scene nodes to calculate the binding. After a successful Bind, the
projection restores that layer's document rest pose before evaluating the new
bindings, including when Rig is hidden. This prevents an edited mask opacity or
other pose channel from becoming the next tool's neutral state.

- Range and step validation rejects nonfinite settings, displaced coordinates,
  and newly merged bindings. Both pose samples and animation triggers constrain
  the range controls. Defaults are clamped to the resulting range.
- Repeated binds, repeated trigger operations, and unchanged settings create no
  history step. Failed commands publish no partial change.
- Surviving parameter projection objects retain their identity for focused UI
  callbacks. They remain detached from the document's resources.
- Parameter-name typing commits once on Enter or focus loss. Save, tab departure,
  and history actions finish pending text before proceeding. A rename preserves
  the user's unbound pose. Background saving takes its snapshot before disabling
  authoring controls, so a pending name can enter that snapshot.
- Undo/Redo retain the selected parameter and valid preview input values while
  rebuilding the scene. Save still excludes live previews and unbound edits.

### Remaining limits

Rig transform/deformation gestures still shape a transient scene pose until Bind;
these drafts have not yet moved into `TwberDocumentEditSession`. Range spinbox
updates commit individually. Rig pivot edits, Place inspector/pivot/mirror tools,
and Animate authoring still use the temporary legacy adapter. History and
command candidates still copy the compatibility resource schema; compact patches,
immutable assets, and the complete new evaluator/schema remain future work.

Next: native timeline commands and the remaining pivot/mirror migrations, plus
moving unbound rig gestures into explicit cancellable draft sessions. These are
still foundation increments, not completion of P0/P1 or the full authoring plan.

### Validation

Added resource-only and editor regressions for all parameter types, isolated
sparse mesh/transform binding, detached pose inputs, pixel snapping, no-op history,
invalid settings, binding displacement/merging, trigger-safe ranges, removal and
Undo, projection identity, retained preview inputs, grouped name edits, and
background-save boundaries. Existing clipping and mask-opacity integration tests
also exercise the migrated path.
The complete repository suite passes with the pinned Godot 4.7.1 editor,
including package builds, model/rework/environment/delivery tests, and the real
OpenGL renderer test. No script errors were reported.


## Sixth increment — native timeline authoring

`TwberEditTimeline` now owns clip creation/deletion, name/duration/loop/FPS
settings, and layer key insertion/replacement/removal. Animate sends explicit
pose inputs to these commands instead of mutating timeline resources and asking
the legacy adapter to capture the scene. Its remaining legacy authoring signal
is the pivot operation.

- Clip deletion removes its parameter animation triggers in the same validated
  transaction. Undo restores the clip, its keys, and its triggers together;
  unrelated clips and parameter poses remain intact.
- Key inputs are copied, validated against document layers and mesh topology,
  and stored with their channel masks. Invalid or out-of-range key times and
  nonfinite pose values cannot partially enter history. Identical keys and
  repeated removal create no additional Undo step.
- Key targeting uses the nearest key within half a frame on the selected layer.
  Equal-distance ties choose the earlier time, independent of storage order.
  The timeline's delete-button availability uses the same rule.
- Shortening a duration past an existing key is rejected with an explanation.
  This replaces the old silent clamping of multiple keys onto the endpoint.
  FPS changes affect snapping and targeting without retiming saved keys.
  Scrubbing clamps the rounded time to the actual clip duration.
- Incremental projection retains surviving clip resource identities and avoids
  rebuilding scene nodes. Metadata edits preserve playback and unrecorded poses;
  committed key edits evaluate the authored timeline again. Undo retains a valid
  selected clip and playhead, clamping time when necessary.
- Animation-name typing commits once on Enter/focus loss. Save, tab departure,
  selection changes, and history operations finish the pending name. Playback
  and scrubbing create no document revisions or dirty state. Archives contain
  committed keys and rest geometry, excluding unrecorded preview edits.

The shared layer-state resource now supplies pose equality for both parameter
and timeline commands. The editor's parameter projection can also synchronize
trigger removal after a clip deletion without an unrelated parameter command.

### Remaining limits

This migrates the existing layer-property timeline; it does not yet add the
plan's parameter tracks, key retiming tools, curve editor, or recording/export
pipeline. Animate and Rig transform/deformation gestures still edit transient
scene poses until explicitly recorded/bound, rather than using cancellable
`TwberDocumentEditSession` drafts. Numeric setting updates commit individually.
Pivot/mirror and Place inspector operations still use the legacy adapter, and
history still retains bounded copies of the compatibility resource model.

Next: native pivot/mirror and remaining Place inspector commands, followed by
explicit Rig/Animate draft sessions. The shared parameter-track evaluator and
recording/export slice remain subsequent milestones in the full rework plan.

### Validation

Resource-only tests cover unique clip IDs, detached sparse key inputs, atomic
validation failures, key replacement/removal and no-op history, duration/FPS
semantics, deterministic nearest-key targeting, and clip/trigger deletion Undo.
Editor tests cover native command routing, rest/preview separation, projection
identity, key Undo/Redo, grouped renames, save and tab-change boundaries, and
playback/scrubbing staying clean. An existing integration test now renames through
the editor authoring entry point instead of directly mutating scene metadata.

The complete repository suite passes with pinned Godot 4.7.1: package builds,
model/rework/environment/delivery tests, and the real OpenGL renderer test.
No script errors were reported.


## Seventh increment — native layer properties, pivots, and mirrors

`TwberSetPivot` replaces the three workspace-specific pivot implementations. It
changes the document's neutral coordinate system, shifts local sprite/mesh
content and direct children, and rebases both parameter samples and timeline
keys in one transaction. It uses each sparse state's materialized rotation and
scale. Rotation-only and scale-only samples gain a position channel when needed
to retain their authored artwork placement. Mesh UVs remain unchanged while
vertices, rest vertices, and texture origins shift together.

`TwberMirrorLayers` uses the existing subtree duplication command for persistent
IDs and hierarchy placement, then reflects layer geometry, sparse rig states,
and copied timeline keys. It retains the UI's independent geometry and binding
axis options and optional separate parameters. Separate mirrored parameters also
reverse their defaults and discrete animation-trigger coordinates. Undo removes
the new subtree and its copied authoring data together; Redo retains the same IDs.

`TwberEditLayer` now owns layer names, visibility, opacity, clipping, draw-behind
settings, texture/frame replacement, and sprite-animation creation, selection,
frame rate, rename, and deletion. Asset replacement preserves custom trim/pivot
offsets; mesh replacement recomputes UVs without changing rest or pose vertices.
Sprite-animation rename/deletion updates parameter and timeline state references,
using a remaining animation as the deletion fallback. Deleting the final sprite
animation is rejected. Identical settings do not create history entries, including
opacity values subject to Color's floating-point precision.

`TwberLayerProjection` updates surviving nodes and refreshes assets when needed.
The editor restores active previews before applying coordinate changes, refreshes
tool caches from the result, then restores Rig inputs. Layer selections and node
identities survive these edits. Place/Rig/Animate send local pivot coordinates;
the command itself reads no render nodes.

### Retired scene-capture path

All current editor authoring operations now enter through document commands.
The legacy scene-capture command, mutable scene edit flags/signals, rest-pose
rewrite helpers, and standalone Place transform fallback have been removed.
`_finish_pending_authoring()` only finishes pending parameter/clip names. Saves,
exports, and autosaves read committed snapshots. Live Place drag notifications
only refresh rendering; they cannot queue a deferred authored scene capture.

### Remaining limits

This retains the compatibility resource schema and bounded snapshot history.
Numeric inspector updates still commit individually; Rig/Animate gestures still
shape unbound/unrecorded scene previews until Bind/Record. Explicit cancellable
drafts for those workspaces are next.

Pivot rebasing preserves rest artwork and authored sample/key endpoints. It does
not replace the existing interpolation/composition model: trajectories between
rotated/scaled keys and combinations of several such parameters can still differ
after changing the pivot. Exact preservation throughout those blends needs the
planned evaluator/coordinate-space work. Asset replacement retains unused assets
in the document; asset garbage collection remains future work.

### Validation

New resource tests cover pivot preservation under nonuniform scale, sparse
rotation/scale channels, child placement, mesh UV/rest data, invalid/no-op edits,
mirrored nested geometry and timeline keys, separated parameter defaults/triggers,
and Undo/Redo identities. Layer-property tests cover atomic failure, opacity
no-ops, sprite-animation reference migration, frame imports, and mesh replacement.
Editor tests exercise all three pivot tools, projection identity, mirror history,
archive round trips, and saves after arbitrary render-node mutations. Existing
integration tests also pass through the migrated paths.

The full repository suite passes with pinned Godot 4.7.1: package builds,
model/rework/environment/delivery tests, and the real OpenGL renderer test.
The dirty-state/autosave integration fixture now makes an actual inspector edit
and verifies that a render-refresh signal alone stays clean. No script errors
were reported.


## Eighth increment — explicit Rig and Animate pose drafts

`TwberPoseEditSession` owns a detached evaluated layer pose and its baseline,
sampled from committed document resources. It captures the document revision
and the binding target or clip/playhead when editing starts. Transform, mesh,
reset, visibility, opacity, and sprite-animation edits update this pose buffer;
render nodes receive projections of it. Bind and Add Point build the existing
native parameter/timeline commands from the buffer instead of capturing a node.
Unrelated render-node changes therefore cannot become recorded pose data.

`TwberPoseDraftController` handles projection and cancellation for both tools.
It restores animation frame rates as well as pose channels, updates clipping
colors through the clipping controller, and refreshes mesh renderer geometry.
A document snapshot is taken when the session starts; pointer updates copy the
layer pose rather than the entire model or history.

### Draft lifecycle

Releasing the pointer, including outside the overlay, ends the gesture while
retaining a changed draft. A gesture that returns to its starting pose closes
without leaving a draft. Bind or Add Point commits the accumulated edits as one
document action. Escape and Undo discard a draft before touching document
history; Redo is unavailable while a draft is active.

Changing the selected layer, parameter input, clip, playhead, or workspace,
starting playback, losing window focus, and opening a new model discard drafts.
Document revisions also invalidate them, except for parameter/clip name-only
commands routed through the editor. Those names cannot change the pose or its
target, so the session can accept the new revision and remain editable.

Save, Export Copy, and autosave continue to read committed document snapshots.
Drafts are not dirty document edits and are not recovered from autosave. A save
does not itself commit or cancel a pose draft; normal focus-loss cancellation
still applies if the save workflow moves focus out of the window. The status
bar describes how to keep or discard the draft, and the Edit menu shows
"Discard pose draft" while one is active.

### Remaining limits

This establishes explicit transient pose ownership without replacing the current
resource schema, bounded snapshot history, or runtime/editor preview evaluators.
There is one draft for the selected layer and no separate Undo stack inside it.
Timeline keys still store layer poses. Parameter tracks, shared evaluation,
curve/retiming tools, and recording/export remain subsequent milestones.

Next: the shared parameter-track evaluation foundation, so animation and live
inputs can use the same composition rules.

### Validation

Resource tests cover document-derived baselines, detached inputs and target
contexts, atomic rejection of invalid poses, stale revisions, and explicit
Bind/Record commands. Editor regressions cover outside releases, Escape/Undo,
focus loss, mesh cancellation, save isolation, tab/input/playhead/selection
changes, playback, external document edits, and sprite frame-rate restoration.
Existing name-edit tests verify that drafts survive renames. Integration fixtures
now simulate authoring through the draft API instead of mutating render nodes.

The full repository suite passes with pinned Godot 4.7.1: package builds,
model/rework/environment/delivery tests, and the real OpenGL renderer test.
No script errors were reported.


## Ninth increment — shared evaluation and parameter tracks

`TwberModelEvaluator` is a scene-free compiled instance. It detaches parameter
definitions and clips, builds neutral states from document layers, compiles rig
samples, and groups/sorts property and parameter tracks once on configuration.
Each evaluation starts from neutral data; previous frames and render nodes
cannot become the next frame's input. Rig and result pose buffers are reused;
callers must copy returned poses if they want to retain a frame.

The existing mapper's optimized sampling/composition kernel now returns data.
Its scene adapter, Rig's binding sampler, and the new evaluator all use that
kernel. The allocating reference sampler/composer remains available for parity
tests. Runtime playback and Animate preview use the new evaluator for the full
parameter/property pipeline. Animate's neutral baseline now comes from the
document, and its cancellable layer drafts sample this same pipeline.

### Evaluation contract

Live/default parameter values are normalized first. Active clips override their
keyed parameters, then the rig evaluates the resolved values. Explicit layer
tracks apply afterward and replace only channels they own. Both clip stages use
ascending priority and stable clip-ID order, so higher priority wins and equal
priority never depends on dictionary insertion or trigger activation order.
Existing rig delta, scale, rotation, and discrete-channel composition remain the
compatibility behavior; this increment does not silently change their math.

Float and Vector2 parameter tracks support linear interpolation and outgoing
hold segments. Bool/Int always hold until the next key. Endpoints hold outside
the keyed interval; sampled values pass through the parameter's existing range
and step normalization. Hosts supply the playhead and handle looping; a direct
evaluation at the clip duration samples the final frame. Runtime triggers read
external parameter inputs, not resolved track output, preventing same-frame
feedback when a clip keys its own trigger parameter.

Runtime updates still restrict ordinary live-input changes to affected layers.
Active clips currently evaluate the union of rig and clip layers. Projection
updates clipping colors and dynamic renderer geometry from the result. Stopping
a trigger restores live input poses, including channels previously owned only
by a clip.

### Authoring and persistence

Animate now exposes a parameter selector, scalar/Vector2 value controls, hold
mode, Key parameter, Remove key, and clip priority. Value changes create/update
keys immediately at the playhead; Key parameter records the displayed value.
This works without a selected layer. Green circles show keys for the selected
parameter while the existing layer-pose workflow remains available.

`TwberEditTimeline` owns parameter-key set/remove and priority settings. Keys use
stable parameter IDs, captured coordinates, times, and interpolation modes.
Nearest-key replacement follows the same frame tolerance and earlier-key tie
rule as layer keys. Identical changes create no history. Duration changes cannot
truncate parameter keys, and parameter range/step changes cannot move their
authored values. Parameter deletion removes dependent keys in the same Undo
transaction. Creating a separate mirrored parameter also copies and transforms
its keys into the mirrored coordinate system.

Model format 10 persists parameter keys and priority. Older models receive empty
parameter tracks and priority zero. Validation rejects missing targets, invalid
coordinates/times/interpolation, and duplicate target/time pairs. Older Twber
versions reject new-format saves instead of silently dropping parameter tracks.

### Remaining limits and next step

This is the parameter-track foundation of P2, not completion of that acceptance
slice. Weighted/additive clip blending, expression mixing, curve editing,
retiming, physics, and deformer evaluation remain planned. Parameter controls
currently commit once per numeric update. Compiled instances retain private
resource copies, and property-track sampling still allocates intermediate states.
The legacy mapper entry points retain a scene-capture fallback for callers that
do not supply neutral states; the new runtime/Animate pipeline does not use it.

Next: recording timestamped parameter takes and deterministic frame export
through this shared evaluator.

### Validation

The new parameter-track suite compares live and clip-driven poses against the
independent reference composition, including a grid of combined scalar/2D mesh,
rotation, scale, and opacity samples. It checks source/instance isolation,
sparse property overrides, priority and activation order, typed interpolation,
hold boundaries, atomic command failures, no-op history, dependency Undo,
mirrored keys, archive round trips, and legacy loading. Editor/runtime tests
cover key creation without layer selection, Undo, scrubbing/playback parity,
draft cancellation, trigger release, looping/endpoints, and feedback isolation.

The full repository suite passes with pinned Godot 4.7.1, including package
builds, model/rework/parameter-track/environment/delivery tests, and the real
OpenGL renderer test. No script errors were reported.


## Tenth increment — parameter takes and transparent PNG sequences

`TwberParameterTake` records normalized parameter inputs without nodes or a
document. It owns copied parameter definitions, preserves monotonic timestamps,
coalesces changes at the same timestamp, and omits unchanged keys. Initial
missing values use defaults; later partial updates retain previous inputs.
Invalid timestamps/types/nonfinite values fail atomically. A 200,000-key limit
bounds recording memory. Takes use hold keys so playback does not invent motion
between observed input events. They can be edited as ordinary parameter tracks.

Rig exposes Record parameters, Finish take, and Cancel take. The editor samples
control changes against a monotonic clock. Finish submits
`TwberImportParameterTake`, creating a uniquely named clip and stable ID in one
document transaction, then opens Animate. Undo removes the whole take; Redo
restores it. Active recordings remain outside save/autosave and history. Escape,
Undo, tab/focus changes, and document revisions discard them. Recording currently
captures Rig parameter controls, not unbound layer gestures or Environment
provider streams.

### Fixed-time rendering

`TwberRuntimeModel.seek_animation()` evaluates a clip at an explicit time through
the shared evaluator, independently of live trigger clocks. Animate and explicit
runtime seeking use `TwberSpriteFrameSampler` to select animated-sprite frames
without reading wall-clock playheads. Frame durations and animation looping are
respected. This first clock defines absolute clip phase from the selected
animation and evaluated rate at the requested time; integrating changing rates
and resetting phase on keyed animation switches remain future work. Animate
restores sprites' previous playing state when leaving preview.

`TwberFrameExporter` owns an immutable model copy and an isolated SubViewport.
It renders transparent PNGs at `index / fps` in `[0, clip.duration)`, with explicit
canvas dimensions, center, and scale. The editor camera and transient poses are
never inputs. A sequence manifest stores the frame times and canvas settings.
PNG rendering requires a real graphics backend. The initial limits are 4096
pixels per canvas axis, 120 fps, and 100,000 frames per sequence.

Exports write to a uniquely allocated sibling staging directory. Only a complete
sequence is renamed into the requested output directory; existing destinations
are rejected. Cancellation, rendering/write errors, and owner closure remove
the job's files and staging directory. The Animate export dialog selects an
unused output name, reports frame progress, and allows cancellation. Abrupt
process termination can leave a staging directory; restart cleanup is not yet
implemented.

### Validation and remaining work

Headless tests cover timestamp ordering, coalescing, normalized and partial
inputs, rejected samples, live/playback pose parity, atomic take history,
save/load fidelity, editor recording/finish/cancellation, and frame scheduling.
GPU tests inspect transparent pixels, recorded motion, and animated frames;
repeated exports agree pixel-for-pixel. They also exercise overwrite protection,
cancellation cleanup, source mutation during export, and export-owner closure.

This supplies the manual Rig-input → take → playback → PNG path. It does not
complete Environment provider recording, input calibration/mapping extraction,
physics, audio/video encoding, curve editing, or cross-platform export acceptance.
Per-frame PNG encoding remains on the main thread, with cancellation checked
between frames. The next P2 step is routing mapped Environment inputs into the
same recording contract and completing live-input/playback/export parity tests.

The complete repository suite passes with pinned Godot 4.7.1, including package
builds, model/rework/parameter-track/recording/environment/delivery tests and both
GPU test scripts. Final recording and pixel-export regressions also pass after
the export-owner cleanup fix. No script errors were reported in those final tests.

## Eleventh increment — Environment input takes and mapping boundary

Environment can record a selected runtime instance's applied parameter inputs.
The runtime emits normalized input changes, after provider mapping and smoothing;
manual changes and resets use that same route. The adapter adds monotonic timestamps
and `TwberModelTake` owns a document snapshot plus `TwberParameterTake`. Finish
imports a native parameter clip into that detached model through
`TwberImportParameterTake`. Neither stage placement nor the loaded source is edited.

Recording remains attached to its original instance when selection or window focus
changes and when the control dock is detached/re-embedded. Cancel, target removal,
and model replacement discard the active trace. A finished take saves automatically
to a unique `.twber` copy under `models/takes/`; previous copies remain available.
Save errors retain the pending copy and expose Retry save and Save elsewhere.
Home and starting another recording are disabled until the pending copy is saved.
The latest saved take can use the existing transparent PNG export dialog directly;
any saved copy opens normally in Editor for parameter-track editing.

`TwberInputMapping` is an optional data-only package contract. Mouse and microphone
packages now declare `mapping_script`; their widgets delegate to the same mapper.
Environment supplies persisted configuration and display geometry as data. Mouse
mapping handles automatic/fixed displays, negative origins, disconnected displays,
and empty geometry. Microphone mapping handles scalar/integer ranges and boolean
thresholds; equal dB endpoints produce a finite threshold result. Continuous input
smoothing is shared pure code in `TwberInputSmoothing`. Existing third-party packages
without a mapper retain their widget mapping fallback under package API v1.

### Archive worker boundary

GPU testing exposed a native crash when texture compression ran during a background
model save. `prepare_twber_export()` now snapshots metadata, reads textures, and
prepares texture payloads on the main thread. `export_prepared_twber()` receives only
dictionaries and byte buffers for serialization, ZIP writing, and atomic publication
on the worker. Editor Save and autosave use this boundary too. Texture preparation
and compression can still stall the main thread for large models; splitting or
caching that work remains a performance follow-up.

### Scope and verification

The regression covers packaged provider dispatch, applied smoothing, instance
isolation, dock reparenting, manual inputs, normalized key timestamps, portable
save/load, source/stage isolation, failed-save retry, cancellation/removal/replacement,
and the shared evaluator's playback poses. A real GPU test checks transparent PNG
pixels from the saved Environment take. Prepared archive tests also mutate source
metadata and texture pixels after preparation to verify snapshot isolation.

This proves the simple parameter-driven live → take → playback → PNG acceptance
path. Triggered clips are still not baked into recorded takes, and stage gestures,
raw-source recalibration, tracker dropout policy, physics, audio/video encoding,
and cross-platform acceptance remain outside this increment. Active recordings and
failed-save copies are memory-only until successfully saved; there is no crash
recovery for those traces yet. Recordings are bounded by the existing key limit;
reaching it finishes and saves the valid captured prefix.

The full pinned Godot 4.7.1 suite passes, including package builds, delivery,
headless integration, renderer checks, and both recording/export GPU scripts.
The final expanded Environment regression also passes separately in headless and
Wayland/OpenGL modes, including prepared metadata/image isolation. No script
errors appeared in those final runs; the editor import retains its existing
nonfatal debugger-plugin diagnostic.

## Twelfth increment — triggered timeline results in performance takes

Environment's **Record performance** now observes the runtime's evaluated output,
rather than raw input-change notifications. Each live process publishes its final
input/playhead snapshot once, after trigger activation and clock advancement.
Explicit parameter evaluation also publishes a snapshot. Recording can begin in
an already-running clip and preserves that starting phase. Model replacement
cancels recording before any new-model evaluation can enter the old session.

`TwberModelTake` owns a compiled evaluator alongside its document snapshot. It
records resolved parameter values, including parameters driven by active clips.
It also captures sparse layer states for the union of channels owned by triggerable
clips. Those states include rig output when a trigger releases, so playback restores
the observed pose without rerunning bindings. Clip priority conflicts, loop wraps,
restarts, and held non-loop endpoints use the same evaluator as live performance.
The captured result is independent of subsequent edits to the source clips.

### Editable native tracks

Model format 11 adds linear/hold interpolation to layer keys. Legacy keys default
to linear. Recorded keys hold until the next observed timestamp, including at exact
key boundaries; no interpolated motion is invented between captured observations.
The codec preserves this setting, document validation rejects unsupported modes,
and replacing a key through normal timeline editing retains its interpolation.

`TwberImportParameterTake` accepts validated mixed parameter/property takes as one
native command. Undo/Redo, save/load, Animate playback, and PNG export use ordinary
tracks. Baked property tracks override parameter edits on their owned channels;
users can edit or remove those tracks to change that behavior. Other channels remain
available to the rig. Takes coalesce observations at the same timestamp and share
the 200,000-key budget between parameter and layer tracks. Rejected samples leave
the valid trace unchanged, including at the capacity limit.

### Verification and limits

Headless and GPU regression tests cover recording a running clip, release/restart,
loop wrap, priority overlap, non-loop endpoints, parameter output from clips,
all layer pose channels (including mesh, visibility, animation selection and rate),
exact key boundaries, held intermediate poses, invalid observations, bounded traces,
legacy linear migration, portable round trips, editing, and atomic import history.
GPU tests inspect transparent pixels from a saved triggered-performance take.
The full pinned Godot 4.7.1 repository suite passes with no application script errors;
editor import retains its existing nonfatal debugger-plugin diagnostic.

This captures timeline parameter/property results at observed evaluation timestamps.
It does not reconstruct motion between those frames or preserve raw input streams.
Stage movement remains outside model takes. Free-running animated-sprite frame phase
is still not captured: exports retain the existing absolute clip-time sprite sampler.
A shared sprite playback clock (including animation switches and rate changes) is
the next remaining live/playback/export fidelity task. Texture preparation latency,
recording crash recovery, physics, and audio/video encoding remain separate work.


## Thirteenth increment — shared sprite clocks and captured frame phase

Animated sprites now use an explicit `TwberSpriteClock` in live performance instead
of Godot's independent autoplay. Elapsed time advances the previous evaluated rate;
a rate change preserves phase, zero speed pauses, and selecting another animation
restarts it. `TwberSpriteFrameSampler` only projects supplied clock states into
frames, accounting for unequal relative durations, looping, and nonloop endpoints.
Runtime performance snapshots include those clock states after final evaluation.

### Native captured timing

Model format 12 adds per-layer sprite timing markers to native clips. Each marker
stores an animation name, unwrapped phase, and rate. Recording starts at the actual
live offset and emits further markers for animation/rate changes or phase jumps;
constant-rate runs need only their initial marker. Markers share the existing
200,000-key recording limit with parameter/property tracks and coalesce same-time
observations. Sprite-only models can record without parameters.

Archive loading validates references, finite nonnegative timing, unique layer/time
pairs, clip bounds, and a zero-time anchor for every captured sprite track. Older
clips default to authored timing. Duplication, deletion, animation rename/fallback,
clip duration validation, import, and Undo/Redo preserve or remap the new data.
**Use authored sprite timing** in Animate clears captured markers as one undoable
command, allowing later animation/rate edits to take effect. Until cleared,
captured timing overrides those channels.

### Seeking, playback, and export

`TwberSpriteTimeline` supplies the same states for Animate scrubbing and runtime
explicit seeking, which PNG export already uses. Captured tracks use binary search
and advance from their saved anchors. Unrecorded authored clips integrate on a
canonical 240 Hz grid plus key boundaries and discrete property-switch midpoints.
Only complete grid/event boundaries become checkpoints, so fractional seeks and
output frame rate cannot change the result. Constant-rate clips use a direct path.
Live triggers also replay captured markers using existing priority/stable-ID order,
restart offsets, and held nonloop endpoints.

The timeline reader depends on model data and evaluation, without calling editor
commands. Removing an initial command-layer lookup also eliminated a reproducible
Godot shutdown script/resource leak in the general test runner. Model removal now
releases the clock, timeline snapshot, and pose evaluator together.

### Verification and limits

`testing/test_sprite_clock.gd` covers mid-animation recording, unequal frame
lengths, zero-rate pauses, selection changes, rate integration, seek-order
independence, live take triggering/restarting, held endpoints, sprite-only takes,
portable archives, legacy loading, document commands, and real Animate scrubbing.
Its GPU variant checks the exported transparent PNG pixels against observed live
sprite frames. Both variants run in `scripts/test.sh` alongside the existing suite.
The full pinned Godot 4.7.1 suite passes, including package builds, delivery, all
headless regressions, and all four GPU test scripts. No application script errors
or resource leaks appeared; editor import retains its existing nonfatal debugger
plugin diagnostic. `git diff --check` also passes.

Authored curve integration is deterministic numerical sampling, not an analytic
solution; rapid parameter-driven switches can quantize to the 240 Hz grid. Live
playback advances on actual process intervals, and recorded anchors preserve those
observations directly. Seeking far backward through an unrecorded varying-speed
clip may require replaying its integration grid. Editing frame artwork/durations
can change the appearance of saved phases. Stage motion, physics, recording crash
recovery, texture preparation latency, and audio/video encoding remain separate work.
