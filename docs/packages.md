# Twber Package Format

Twber environment packages are Godot PCK resource packs. A distributed package is one file named `<package-id>.pck`; the environment does not require or reference its source scenes or scripts.

## Discovery

At startup the environment scans:

- `res://packages` for packages bundled with the application.
- A `packages/` directory beside the exported executable for sidecar packages.
- `user://packages` for packages installed by the user.

The PCK filename is its package ID. Mounting `microphone.pck`, for example, must expose this manifest:

```text
res://twber_packages/microphone/package.json
```

The manifest API is versioned:

```json
{
  "api_version": 1,
  "id": "microphone",
  "name": "Microphone Input",
  "version": "1.0.0",
  "description": "Captures a microphone and publishes a smoothed level in decibels.",
  "entry_scene": "res://twber_packages/microphone/provider.tscn",
  "settings_scene": "res://twber_packages/microphone/settings_control.tscn"
}
```

`settings_scene` is optional. Every entry scene extends `TwberEnvironmentPackage`. Input packages extend its `TwberInputProvider` subtype, while stage extensions can use the base class directly. A settings scene must extend `TwberPackageSettingsControl`, and input descriptors may provide a `binding_scene` extending `TwberInputBindingControl`. This lets a package carry its behavior and scene-backed UI in the same PCK.

Stage packages receive a `TwberStageApi`. It exposes the current stage items, their visual bounds and source paths, item add/remove and drag lifecycle signals, and image-asset creation. The API deliberately stays narrower than the environment scene so package code remains modular. See `package_sources/attachment/` for a complete stage-extension example.

## Authoring Packages

Editable package projects live under `package_sources/`. Each immediate subfolder containing a `package.json` is a package the builder can discover:

```text
package_sources/
├── microphone/
│   ├── package.json
│   ├── provider.gd
│   ├── provider.tscn
│   ├── settings_control.gd
│   ├── settings_control.tscn
│   ├── binding_control.gd
│   └── binding_control.tscn
├── mouse/
│   └── ...
└── attachment/
    ├── attachment.gd
    ├── attachment.tscn
    ├── settings_control.gd
    └── settings_control.tscn
```

These folders are visible in Godot's FileSystem dock. Their scenes and scripts use normal editable paths such as `res://package_sources/mouse/provider.gd`, so they can be opened and changed directly.

To start another package, copy either existing folder, rename it to a valid lowercase package ID, and replace every old `res://package_sources/<old-id>` path with the new folder path. The `id` in `package.json` must match the folder name.

The four core base scripts are:

- `TwberEnvironmentPackage`: the common entry point for every package.
- `TwberInputProvider`: the package entry point and value producer.
- `TwberPackageSettingsControl`: optional package-wide settings UI.
- `TwberInputBindingControl`: optional per-parameter mapping and preview UI.

All UI should remain scene-backed, just like the included mouse and microphone examples.

An authoring manifest points to its editable source scene:

```json
{
  "api_version": 1,
  "id": "my_package",
  "name": "My Package",
  "version": "1.0.0",
  "description": "What this package provides.",
  "entry_scene": "res://package_sources/my_package/provider.tscn"
}
```

## Building Packages

Build every package folder found under `package_sources/` directly from Godot:

1. Open `tools/build_packages.gd` in the Script workspace.
2. Press the script editor's **Run** button.
3. Watch the Output panel for each package result.

The builder writes:

```text
packages/mouse.pck
packages/microphone.pck
packages/attachment.pck
packages/background.pck
```

The `.pck` files are generated build outputs; the editable folders remain unchanged. During packaging, the builder validates the manifest and stages a copy that rewrites `res://package_sources/<package-id>` references to the isolated `res://twber_packages/<package-id>` runtime namespace. Each generated PCK therefore contains only its own manifest, scripts, scenes, and assets, with no runtime dependency on the authoring folder.

## Security

PCK packages can contain executable GDScript and therefore have the same local permissions as the environment application. Only install packages from sources you trust. Manifest validation and API version checks prevent malformed or incompatible packages from loading, but they are not a security sandbox.
