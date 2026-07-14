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

`settings_scene` is optional. The entry scene must extend `TwberInputProvider`. A settings scene must extend `TwberPackageSettingsControl`, and input descriptors may provide a `binding_scene` extending `TwberInputBindingControl`. This lets a package carry its provider, package-wide settings UI, parameter-specific mapping UI, and preview behavior in the same PCK.

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
└── mouse/
    └── ...
```

These folders are visible in Godot's FileSystem dock. Their scenes and scripts use normal editable paths such as `res://package_sources/mouse/provider.gd`, so they can be opened and changed directly.

To start another package, copy either existing folder, rename it to a valid lowercase package ID, and replace every old `res://package_sources/<old-id>` path with the new folder path. The `id` in `package.json` must match the folder name.

The three core base scripts are:

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

Build every package folder found under `package_sources/` with:

```bash
godot --headless --path . --script tools/build_packages.gd
```

Build only one or more named packages with:

```bash
godot --headless --path . --script tools/build_packages.gd -- mouse
godot --headless --path . --script tools/build_packages.gd -- mouse microphone
```

The source and output roots can also be changed, provided the source remains inside `res://`:

```bash
godot --headless --path . --script tools/build_packages.gd -- \
  --source-root=res://my_package_projects \
  --output-root=res://my_package_builds
```

The builder writes:

```text
packages/mouse.pck
packages/microphone.pck
```

The `.pck` files are generated build outputs; the editable folders remain unchanged. During packaging, the builder validates the manifest and stages a copy that rewrites `res://package_sources/<package-id>` references to the isolated `res://twber_packages/<package-id>` runtime namespace. Each generated PCK therefore contains only its own manifest, scripts, scenes, and assets, with no runtime dependency on the authoring folder.

## Security

PCK packages can contain executable GDScript and therefore have the same local permissions as the environment application. Only install packages from sources you trust. Manifest validation and API version checks prevent malformed or incompatible packages from loading, but they are not a security sandbox.
