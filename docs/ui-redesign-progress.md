# Editor workspace implementation

## First working workspace — 2026-10-11

The Editor now runs Place, Mesh, Rig, and Animate inside a configurable workspace.
The implementation goes beyond the planned Place/Mesh demonstration: Parameters,
Clips, Timeline, recording controls, and native floating panels are integrated too.

- Drag the thin panel grips to split a dock on any side. Drop into its center to form a
  tab group; tabs can also be dragged and reordered. Drop previews show placement.
  Escape cancels a drag without changing the arrangement.
- Right-clicking a grip or tab provides docking positions, tab order, Float, Hide, and Return to
  dock. View reopens hidden panels. Closing a floating window redocks its panel.
- Workspace provides layout locking, reset, and named presets. The current layout
  restores through `editor.workspace` settings on the next Editor session.
  Validation rejects malformed split trees and duplicate panels; new panels get
  default placements, and native window geometry is constrained to available screens.
- One clipped canvas retains its model nodes and camera during layout changes.
  Pan/zoom input is restricted to that canvas. View → Center canvas recenters
  the view. The Inspector has an empty-selection hint, and the status strip
  identifies the editing context.
- Tool activation no longer depends on panel visibility. Layer IDs carry selection
  across the four modes. Moving or hiding panels leaves pose drafts, recording,
  playhead, document revision, dirty state, and Undo history intact.
- Transfers of focus between Editor-owned windows preserve temporary edits.
  Actual application departure retains the existing cancellation policy. Native
  panel windows forward unhandled Escape and document Undo/Redo shortcuts.
- The unsaved-changes window is explicitly hidden at startup; it previously
  opened as an exclusive window and could block Editor input.

The UI is authored as Godot scenes. `editor/editor.tscn` contains the menu bar,
mode selector, status bar, workspace instance, dialogs, and separate mode
controller nodes. `editor/workspace/workspace.tscn` contains the default split
arrangement, dock instances, and canvas with its model root and input overlays.
The runtime reads that scene's split tree and child stretch ratios for Reset;
there is no second hardcoded default layout.

`editor/workspace/dock_panel.tscn` defines the shared panel grip, body, and context
menu. The six `*_dock.tscn` scenes configure their panel minimums and instance
mode-specific content from `editor/panels/`. Buttons, shortcuts, inspectors,
parameter controls, clips, and timeline can be edited in those scenes. The tool
strip is a `@tool` Container, so it reflows in the Godot editor as well as at
runtime. Colors and shared styling live in `editor/workspace/editor_theme.tres`.

`TwberEditorTool` is a Node controller with exported references to its panel
instances, model root, and canvas overlay. Panel-owned unique names survive
docking; recursive control caches and extraction from hidden scenes are gone.
The four old full-screen mode scenes and their hidden TabContainer have been
removed. `TwberWorkspaceBinding` only connects menus and controller signals.
The existing scripts still implement authoring behavior and dispatch document
commands. Further consolidation of their layer-tree projections is independent
of the scene migration.

`twber_workspace.gd` rebuilds the user-defined split/tab arrangement and creates
native floating windows. Those dynamic containers are runtime behavior. It moves
whole dock instances and keeps the canvas alive, without rebuilding panel
contents, copying a model, or entering document history.

### Validation and remaining work

`testing/test_workspace.gd` adds headless and graphical coverage for actual grip
input and GUI drops in an isolated viewport, cancelled drags, split/tab persistence,
invalid layouts, named presets, restart restoration, selection, drafts, recording,
and playback through layout changes. Its graphical checks exercise native panel
focus/redocking and canvas clipping pixels and zoom anchoring. Existing fixtures
use controller references and panel-owned names, retaining their behavioral
assertions. Scene-structure checks verify that panel variants exist before ready
and mode controllers are Nodes rather than hidden UI containers. They also check
that Reset reads the scene layout and docking preserves scene ownership.
Focus-cancellation fixtures call the explicit application-departure handler;
native window tests cover the focus coordinator itself.

The maintained runner includes this suite alongside document/editor, runtime,
parameter-track, recording/export, sprite-clock, Environment, delivery, package,
and GPU renderer checks. Development validation uses the pinned Godot 4.7.1 on
Linux with graphical checks under X11; Windows, mixed-DPI, and physical
monitor-disconnection acceptance
still need validation on those configurations.

Native floating panels are opened and returned through the panel menu or window
close button. Dragging a native floating window directly across windows into a
dock is not implemented. Panel-grip docking works within the main editor.
Other follow-ups include broader keyboard layout management and user testing
of panel density and small-window layouts. Existing numeric edit grouping, history
memory, and model-format work remain separate backend tasks.


## Compact panel refinement

Standalone panels no longer show a title or permanent menu button. A small grip
retains drag docking and opens the panel context menu on right-click; tab groups
keep their names for navigation. Standalone docks mount directly in their split; only groups with multiple
panels create a tab container. Minimum sizes are specific to the panel, including native windows.

Tools now uses one responsive button strip instead of stacked flow containers.
It can shrink to a single button row or column, plus the dock grip and padding,
and reflows as it is resized. Docking Tools gives it a compact initial share of space;
users can still resize it. A reset layout puts it in a slim left-hand strip.
Existing saved arrangements remain intact. Workspace tests check both strip
orientations in all four modes, button reachability without scrolling, and the
replacement context-menu interaction.

Native focus assertions have passed under X11, but desktop window activation
is not reliable in this session. The latest run failed to acquire main-window
focus and preserve a take while redocking; the graphical sizing, clipping, and
toolbar checks passed. Manual focus acceptance remains outstanding. Application
focus-cancellation behavior is unchanged by these refinements.


## Content minimums and simpler panel scenes

Tools now instances the responsive strip directly. Inspector, Clips, and Timeline
use plain box layouts with no outer ScrollContainer. Redundant content boxes,
inner panel frames, and extra margins have been removed from those scenes and
Parameters. The dock supplies the panel frame and padding once.

Each fixed panel's minimum propagates from its actual controls, through the split
layout to the main window. Floating window minimums also update when content or
mode changes. Tool strips keep their row/column behavior and enough height for
all buttons. Timeline content expands with its dock. Only the growing parameter
list retains an explicit ScrollContainer; Layers and the animation list keep
their built-in list scrolling. List areas have a usable minimum height.

Workspace coverage checks fixed-control minimums in all four modes, native
Inspector minimums, toolbar reachability, and the removal of redundant wrappers.

The tool grid now distributes leftover column width across its buttons instead
of leaving a right-hand gutter. Single-column buttons fill the strip, with square
cells apart from one-pixel rounding at multi-column boundaries. The Tools dock's
minimum width is one button plus panel padding. Headless workspace checks cover
the absence of the gutter in all four modes.

Validation: all maintained headless suites, GPU renderer, and GPU recording,
Environment recording, and sprite-clock suites passed. Native workspace focus
assertions remain affected by the desktop activation issue described above.
