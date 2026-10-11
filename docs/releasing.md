# Releasing Twber

Twber is delivered as one application containing both the model editor and the
puppeteering environment. Linux receives a self-contained AppImage. Windows
receives a ZIP containing the executable and its built-in package PCK files.

## Local release

Use the version pinned in `.godotrc`; see the [testing guide](../testing/README.md)
for running validation without building release artifacts.

The project version in `project.godot` is the source of truth and must be a
semantic version. Prepare a release with:

```bash
GODOT=/path/to/Godot ./scripts/build_release.sh
```

The command imports the project, rebuilds package PCKs, runs all automated
tests, exports both platforms, creates the AppImage and Windows ZIP, launches
both application modes from the finished AppImage, and writes `release.json`
plus `SHA256SUMS` under `dist/<version>/`.

Verify a local release from inside its version directory with
`sha256sum -c SHA256SUMS`.

The AppImage exporter discovers `appimagetool` on `PATH`, in `~/.local/bin`,
`~/Applications`, or `~/AppImages`. It bundles `res://packages` beside the
executable inside the AppImage. On first launch, Twber synchronizes those PCKs
to the `packages/` directory beside `settings.cfg` in Twber application data.

## Published release

1. Update `application/config/version` and `CHANGELOG.md` using Godot's
   **Project > Tools > Prepare Release** command.
2. Commit the version and changelog.
3. Tag that commit as `v<version>` and push the tag.
4. GitHub Actions validates, builds, checksums, and publishes the artifacts.

The in-app updater discovers the repository from metadata embedded during the
Godot export and only installs assets that pass SHA-256 verification.

Automated launchers can bypass the home screen with `-- --editor` or
`-- --environment` after Godot's own command-line arguments.
