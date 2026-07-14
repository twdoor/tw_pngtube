# Performance Architecture

Twber keeps authoring accuracy separate from runtime representation. Source pixels and logical canvas metadata remain available to editor tools, while preview and exported models use trimmed, atlased, and GPU-ready textures.

## Texture import

The import order is:

1. Decode the original image.
2. Find visible alpha bounds using the configured threshold.
3. Add the configured safety padding.
4. Crop only the empty outer canvas.
5. Record original size, trim rectangle, visible rectangle, source path, and alpha threshold.
6. Compress the cropped image for editor rendering when it meets the configured size threshold.

Cropping does not rescale the image. `TwberTextureUtils.get_logical_texture_origin()` maps the cropped texture back into its original canvas, keeping sprites, pivots, and mesh vertices aligned. Animation imports compute one union crop for equal-sized frames. Mixed-size animations stay untrimmed because `AnimatedSprite2D` has one shared offset.

When exact pixels are needed later, `TwberTextureUtils.get_authoring_image()` decodes the original image file and applies the recorded crop. Project files are read directly before Godot's imported `Texture2D` fallback is considered, so VRAM import compression cannot change alpha-edge decisions. If the source is unavailable, the utility safely decompresses the runtime image on demand.

After import, compatible editor textures are repacked into in-memory atlas pages. Sprite, animated-sprite, and mesh references become metadata-preserving `AtlasTexture` regions, so authoring previews exercise the same texture-mapping behavior as exported models.

## Twber archive

Current `.twber` files are ZIP archives with this logical layout:

```text
manifest.json
data/model.bin
textures/atlas_000.png
textures/atlas_000.s3tc
textures/<standalone texture>.png
textures/<standalone texture>.s3tc
```

The manifest identifies the package and model versions, lists file sizes and SHA-256 checksums, and contains a performance summary. Model arrays use Godot's binary Variant encoding instead of base64 JSON. Textures are separate files, so image data no longer expands by base64's roughly one-third overhead.

Compatible textures are shelf-packed into atlas pages up to 4096×4096 with two pixels of edge extrusion. A page is used only when at least two textures share it; oversized or isolated textures remain standalone. Mesh UVs are explicitly mapped into their atlas region. Desktop loads prefer S3TC data while PNG remains the lossless and non-desktop fallback. A loaded compressed texture retains a checked locator for its packaged PNG; alpha-sensitive editor tools decode that page lazily through a bounded cache instead of keeping a second full-resolution GPU texture resident.

Archive writes use a temporary file and replace the destination only after every entry closes successfully. Current loads verify checksums. Legacy JSON/base64 packages remain readable.

## Runtime evaluation

`TwberParameterEvaluator` compiles authored parameters after loading or editing:

- affected layer IDs are resolved once;
- scalar samples are sorted once;
- vector sample Delaunay triangles are generated once;
- neutral samples are represented explicitly in compiled data;
- the scene layer lookup is cached.

Pose states have a channel mask. Binding a position stores only changed transform, visibility, color, mesh, or animation channels. Unchanged mesh arrays are not repeated in the package. Sparse states are materialized against the neutral layer state only while evaluating.

`TwberRuntimeModel` is the shared integration point for the environment app. It loads either editable or exported models, captures an immutable neutral pose, batches multiple parameter input changes into one evaluation, ignores unchanged values, and emits the affected layer IDs. When only some inputs change, it recomposes only layers bound to those parameters; other pose results remain untouched.

`TwberMeshSprite2D` owns its canvas draw command and submits indexed triangles directly with `RenderingServer.canvas_item_add_triangle_array`. It no longer creates an internal `Polygon2D`. UVs remain in author-friendly pixel coordinates in model data and are normalized and atlas-offset only in the renderer.

`TwberModelBatchRenderer2D` keeps editable layer nodes as the source of truth but combines consecutive compatible atlas geometry into packed vertex, color, UV, and index buffers. Transform, color, mesh deformation, and animation-frame changes use a dynamic update path that reuses topology and updates only buffer slices mapped to dirty layers and their descendants. A 65,535-vertex ceiling splits oversized batches safely. Multiple runtime models in one viewport share source-layer suppression safely and restore the viewport state when the last batch is removed.

Flat batching deliberately falls back to standalone rendering when a model uses child clipping, custom materials, non-default draw ordering, custom visibility/light masks, or texture sampling overrides. This preserves model correctness; those features create explicit batching boundaries for a future masked-render-pass backend.

Packaged textures use a weak content-hash cache. Identical texture content loaded by multiple models shares one GPU texture while referenced and can still be released when all models are gone.

## Editor rendering

Mesh and rig overlays redraw only after input, selection, camera, animation-frame, or model changes. Editor edit events invalidate dynamic batches explicitly, without scanning the scene every frame. Mesh deformation reuses topology and cached normalized atlas UVs; retriangulation is reserved for topology edits. Texture preview caching is bounded.

The included renderer benchmark currently demonstrates 200 layers with 64 vertices each in one draw call and 202 scene nodes, compared with 200 draw calls and 401 nodes for the former `Polygon2D` child path. On the development GTX 1650 system, a complete dynamic buffer update for that stress case takes roughly 3.2 ms, while updating one dirty layer takes roughly 0.02 ms; exact numbers vary by CPU and renderer.

The runtime benchmark uses 40 mesh layers, eight parameters, six samples per parameter, and ten bound layers per parameter. A full evaluation plus combined-buffer refresh is roughly 4–5 ms on the development system. A frame with one changed parameter and only its dirty buffer slices is roughly 1.5–2 ms. This workload intentionally includes 64-vertex mesh deformation in every binding.

## Validation

Run parsing and regression tests with:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --script testing/run_tests.gd
godot --path . --rendering-method gl_compatibility --script testing/test_renderer.gd
godot --headless --path . --script testing/benchmark_runtime.gd
godot --path . --rendering-method gl_compatibility --script testing/benchmark_renderer.gd
```

The regression runner covers trim bounds and placement, lossless source-pixel recovery, compiled and selective parameter interpolation, non-accumulating runtime evaluation, sparse pose channels, mesh atlas UVs, batch fallbacks and viewport lifecycle, archive checksums and atlases, GPU variants, cross-model texture sharing, legacy packages, and editable resource round trips. The GPU pixel runner verifies standalone direct triangles, atlas batching, transparency, partial transform updates, and animated-frame UV changes.

## Remaining platform work

S3TC is currently the desktop GPU variant. Mobile and web exports should add ASTC/ETC2 or Basis Universal/KTX2 variants and choose them by renderer capability. The runtime interfaces and per-file variant metadata are structured so those formats can be added without changing authored models.
