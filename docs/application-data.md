# Twber Application Data

Twber keeps application-owned files under one operating-system data root. The
default layout is:

```text
<Twber data>/
├── settings.cfg
├── settings.cfg.bak
├── autosaves/
├── models/
└── packages/
```

- `settings.cfg` contains namespaced application, editor, environment, package,
  workspace, and per-model input preferences. Writes are atomic and retain one
  backup.
- `models/` is the default library used by the Editor's Open, Save As, and
  Export Copy dialogs and by the Environment's model picker.
- `models/takes/` contains separate `.twber` model copies saved when Environment
  recordings finish. Open a copy in Editor to edit its recorded parameter clip.
- `autosaves/` contains the Editor's current recovery model and its source
  metadata. It is not treated as a normal document or an automatic overwrite.
- `packages/` contains the PCK extensions mounted by the Environment. Bundled
  packages are synchronized here before discovery.

The model dialogs retain filesystem access. A model may still be deliberately
opened from or exported to another directory; Twber does not silently copy or
move external user documents.

The Environment workspace is stored in `environment.workspace`. It contains
only source paths, item kinds, stage transforms, stacking order, and selection;
the model and image files remain in their original locations. Missing sources
are skipped and removed from the next saved workspace.

## Editor recovery

An edit restarts the scene-backed autosave timer. After editing pauses, the
Editor captures a `.twber` recovery archive and records its original model path.
New, Open, Home, and application close remain guarded by a Save, Discard, or
Cancel choice while the document is dirty.

On the next Editor launch, an existing recovery archive is offered to the user.
Choosing Later preserves it for another session. Recovering it opens the model
as an unsaved document; saving that document or explicitly discarding its
changes removes the recovery files. Export Copy does not clear recovery because
it does not save the current document.

Platform defaults are:

- Linux and BSD: `$XDG_CONFIG_HOME/twber`, or `~/.config/twber`.
- Windows: `%APPDATA%/twber`, falling back to `%LOCALAPPDATA%/twber`.
- macOS: `~/Library/Application Support/twber`.

`TWBER_CONFIG_DIR` overrides the complete `<Twber data>` path. This supports
portable installations, isolated test runs, and development without changing
the directory layout used by application features.
