# Twber Tools

Twber Tools is a Godot-based toolset for building PNGTuber models, from simple layered sprite puppets to more complex mesh-deformed characters.

The project contains the **Twber Editor** for assembling models and the new **Twber Environment** for loading exported models and puppeteering them with modular input packages. The environment is now the project's default run scene; the editor remains available at `editor/editor.tscn`.

## Status

This project is in active development. The editor is usable for core model authoring, and the environment now has its initial model-loading, parameter-control, input-registry, and mouse-input foundation.

## Current Editor

The editor is organized into three main tabs:

- **Place**: create and arrange layers, sprite layers, animated sprite layers, nested groups, visibility, opacity, clipping, duplication, deletion, and texture assignment.
- **Mesh**: convert texture layers into editable deformation meshes by placing vertices, editing/removing vertices, cutting mesh edges, and joining vertices.
- **Rig**: create bool, integer, float, and 2D vector parameters; bind complete layer states at parameter positions; compose and preview several parameters at once; and edit layers with transform, pivot, mesh-deformation, selection, and reset tools.

Pixel art mode is available in Settings. It snaps layer transforms, pivots, mesh points, deformations, parameter previews, scale, and rotation while keeping the rotation increment configurable. The preview supports zooming up to 32× for pixel-level editing. Animated-sprite parameter states include both the selected animation and its frame rate.

Texture imports can remove empty transparent borders before GPU compression. The crop keeps the artwork at its original pixel density and records its original canvas, crop rectangle, alpha bounds, and logical offset so placement and mesh tools remain accurate. Animated frames use a shared crop to prevent frame-to-frame movement.

The editor also repacks compatible preview textures into in-memory atlases. Meshes render indexed triangles directly through Godot's canvas rendering server—there is no `Polygon2D` child per mesh. Compatible unmasked layers sharing an atlas are flattened into one dynamic batch while their editable scene nodes remain available for tools and parameter binding.

## Environment

The environment can place multiple `.twber`, `.tres`, and `.res` model instances on one stage. Each model can be selected, dragged, scaled with the mouse wheel, removed, and configured independently; the parameter panel follows the selected model while package inputs continue updating every model with matching bindings. Its UI is composed from Godot scenes, including reusable model-instance and parameter-control scenes.

For now, streaming software should capture the main environment window directly. The compact Parameters/Packages dock can be detached into its own native controls window, leaving the captured stage free of visible interface elements; closing that window embeds the dock again.

The included packages are mouse tracking, microphone level, model attachments, and stage backgrounds. They are loaded at runtime from their files under `packages/`; the environment has no direct scene or script reference to their implementations. Mouse tracking publishes a global `mouse.position`; each bound vector parameter selects the display it should interpret, producing normalized model-space coordinates from `(-1, -1)` to `(1, 1)` with positive Y pointing up. The microphone package publishes RMS-smoothed `microphone.level_db` from `-80 dB` to `0 dB`; it is disabled by default and can be enabled from Packages. The attachment package lets an image asset or model dropped over another model follow that model until it is dragged away. The background package provides saved solid-color and custom-image stage backgrounds. Package settings and parameter-binding controls are scenes carried inside their respective PCK.

The environment automatically saves each model's input profile locally, keyed by its loaded path. Every stage instance keeps its own live copy of that profile, so multiple loaded models can animate together while switching selection only changes which controls are shown.

Environment-wide settings are kept separately in `user://twber_environment_settings.cfg`. They remember which installed packages are enabled, along with global package settings such as the selected microphone device and audio-feedback preference. The editor continues to use its own independent editor-settings file.

The File menu includes a **Model Performance** report for estimated draw calls, texture memory, mesh complexity, clipping, animation frames, parameter positions, and saved transparent pixels.

## Model Formats

- `.twber`: the primary editable model format, stored as a versioned archive containing a binary model, checksummed texture files, atlases, lossless fallback images, and desktop GPU-compressed texture variants.
- `.tres` / `.res`: legacy editable Godot model resources retained for compatibility.

The editor can open, edit, and save current `.twber` archives in place, as well as legacy resources and JSON/base64 `.twber` packages. New models default to `.twber`; loading and archive saving run as background jobs with visible status so the interface remains responsive. Export Copy writes another `.twber` without changing the current document.

Parameter samples are compiled when a model changes: scalar positions are sorted once, 2D triangulations are cached, layer lookups are reused, and unchanged pose channels are stored sparsely. `TwberRuntimeModel` provides the environment-facing model node, batched parameter updates, immutable neutral poses, atlas preparation, direct canvas batching, and dirty-parameter evaluation that updates only affected layers and render-buffer slices.

## Project Layout

```text
editor/        Editor UI, tabs, preview, and authoring tools
environment/   Runtime environment UI, reusable controls, core input contracts, and packages
package_sources/ Editable package projects and included implementation examples
packages/       Distributable package PCK files loaded by the environment
shared/        Code and assets shared by the editor and environment app
shared/model/  Model resources, mesh data, runtime mesh node, and serialization/export codec
shared/assets/ Shared icons and UI assets
```

See [Performance Architecture](docs/performance.md) for the import, package, evaluation, and runtime design.
See [Twber Package Format](docs/packages.md) for package manifests, discovery, building, installation, and security.

## Roadmap

- Continue improving the editor workflow for layered and mesh-deformed models.
- Add microphone input, calibration, smoothing, and saved parameter bindings.
- Expand package discovery and lifecycle management beyond bundled packages.

## License

MIT License. See [LICENSE](LICENSE).
