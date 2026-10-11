# Product roadmap

The document/command foundation and the shared live → record → edit → PNG workflow
are implemented. Their contracts are in [architecture.md](architecture.md). This is
an architectural milestone, not completion of the planned first major release.

## Agreed direction

Live avatars and animation production have equal priority in the first major release.
Twber owns its format and runtime; Live2D project import and runtime compatibility
are outside the agreed scope. The goal is comparable creative usefulness with an
easier learning curve, retaining simple PNG, animated-sprite, and pixel-art workflows.
Linux and Windows are the initial desktop targets.

## Remaining work

| Area | Deliverable and acceptance |
| --- | --- |
| Artwork and deformation | Layered PSD import/reimport with stable identities, automatic/manual meshes, nested rotation/warp deformers, masks and animated order. Artwork replacement and topology edits preserve supported rig data or explain unsupported transfers before committing. |
| Expressive rigging | Paired controls with corner corrections, asymmetric poses, sparse combined-parameter corrections, expressions, and reusable rig parts. An illustrated bust supports combined head turn, gaze, blinking, mouth shapes, and expressions. |
| Guided setup | Editable blink, mouth, gaze, head-turn, hair-motion, and expression helpers. Each setup previews its result and undoes in one step; advanced users can edit the generated rig directly. |
| Secondary motion | Shared fixed-step physics, repeatable seeking/preroll, and baking into editable tracks. Input dropout and reconnect do not destabilize motion. |
| Animation production | Curve editing, clip arrangement, scene tracks, audio, and video export, alongside transparent sequences. Recorded performance can become a finished short scene. |
| Live performance | Tracking integration, calibration, routing, expression controls, explicit trigger/fade policies, and validated clean capture on both desktop platforms. |
| Release readiness | Sample projects, contextual guidance, motion-source diagnostics, migration diagnostics, recording recovery, profiling, and packaged acceptance tests on Linux and Windows. |

Resolve feasibility before freezing affected interfaces: warp math and inverse
editing, nested/inverted masks, PSD decoding, a concrete face-tracking integration,
encoder packaging, and geometry transfer across topology changes. Separate authored
projects from any future compiled runtime artifacts without creating competing data owners.
Package provenance/signatures remain a prerequisite for a public package catalog.

## Acceptance targets

Validate the learning curve with at least five people unfamiliar with Twber:

- At least four create a blink and talking mouth from prepared artwork and run a live
  preview within 30 minutes using in-app guidance.
- At least four animate a provided rig into a 10-second clip with audio and export it
  within 30 minutes.
- At least four distinguish rest editing, rig samples, and playback after onboarding.
- Every tester recovers a mistaken edit with Undo and identifies a conflicting motion's source.

These are targets, not measured results. Guided tools must remain fully editable;
they do not promise to infer unseen anatomy from arbitrary art.

Before the major release, demonstrate both complete workflows on Linux and Windows:
import → rig → perform/record, and record → edit with audio → bake → export. Include
artwork replacement, Undo/Redo, save/reopen, input reconnect, multi-model stages,
legacy migration, and packaged builds. Neither workflow may be dropped to meet a date.

Use representative minimum/reference machines and record CPU/GPU/backend details.
Provisional budgets are 60 fps, p95 evaluation plus CPU render preparation below
8 ms, and p95 total frame time below 16.7 ms for a 200-drawable, roughly 20,000-vertex
character with 60 controls, 30 deformers, eight physics chains, and four active clips.
Also measure four smaller instances, interactive feedback, loading, memory release,
and texture-preparation stalls. These budgets are not claims about current performance.
