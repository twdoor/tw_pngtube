# Twber Tools

Twber Tools is a Godot-based toolset for building PNGTuber models, from simple layered sprite puppets to more complex mesh-deformed characters.

The current app is the **Twber Editor**. It is focused on assembling and preparing models. A separate **environment app** is planned next; that app will load exported models and puppeteer them.

## Status

This project is in active development. The editor is usable for core model authoring, but the runtime/environment side is not included yet.

## Current Editor

The editor is organized into three main tabs:

- **Place**: create and arrange layers, sprite layers, animated sprite layers, nested groups, visibility, opacity, clipping, duplication, deletion, and texture assignment.
- **Mesh**: convert texture layers into editable deformation meshes by placing vertices, editing/removing vertices, cutting mesh edges, and joining vertices.
- **Rig**: prepare model controls and deformation state with layer transform tools, pivot changes, mesh vertex deformation, rectangle/lasso vertex selection, reset tools, visibility, opacity, and animation settings.

## Model Formats

- `.tres` / `.res`: editable Godot model resources used while authoring.
- `.twber`: exported Twber model package intended for sharing/loading outside the editor.

The editor can open editable resources and exported `.twber` packages. Saving writes editable resources; exporting writes `.twber` packages.

## Project Layout

```text
editor/        Editor UI, tabs, preview, and authoring tools
shared/        Code and assets shared by the editor and future environment app
shared/model/  Model resources, mesh data, runtime mesh node, and serialization/export codec
shared/assets/ Shared icons and UI assets
```

## Roadmap

- Continue improving the editor workflow for layered and mesh-deformed models.
- Add parameter/rig mapping for both simple sprite models and complex mesh models.
- Build the environment app that loads Twber models and puppets them in a live scene.

## License

MIT License. See [LICENSE](LICENSE).
