#!/usr/bin/env bash
set -euo pipefail

twber_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
twber_version="${1:-}"
twber_godot="${GODOT:-}"

if [[ -z "$twber_version" ]]; then
	twber_version="$(sed -n 's/^config\/version="\([^"]*\)"/\1/p' "$twber_root/project.godot")"
fi
if [[ ! "$twber_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
	echo "Release version must use semantic versioning: $twber_version" >&2
	exit 1
fi
twber_project_version="$(sed -n 's/^config\/version="\([^"]*\)"/\1/p' "$twber_root/project.godot")"
if [[ "$twber_project_version" != "$twber_version" ]]; then
	echo "Tag/release version $twber_version does not match project version $twber_project_version." >&2
	exit 1
fi

if [[ -z "$twber_godot" ]]; then
	twber_editor_version="$(awk 'NR == 1 { print $1 }' "$twber_root/.godotrc")"
	twber_godot="$(find "$twber_root/../.versions/$twber_editor_version" -maxdepth 1 -type f -perm -u+x -name 'Godot_*' -print -quit 2>/dev/null || true)"
	if [[ -z "$twber_godot" ]] && command -v godot >/dev/null 2>&1; then
		twber_godot="$(command -v godot)"
	fi
fi
if [[ -z "$twber_godot" || ! -x "$twber_godot" ]]; then
	echo "Set GODOT to a compatible Godot editor executable." >&2
	exit 1
fi

twber_release_dir="$twber_root/dist/$twber_version"
if [[ -e "$twber_release_dir" ]]; then
	echo "Release directory already exists: $twber_release_dir" >&2
	exit 1
fi

if [[ "${TWBER_SKIP_TESTS:-0}" != "1" ]]; then
	GODOT="$twber_godot" "$twber_root/scripts/test.sh"
fi

mkdir -p "$twber_release_dir/linux" "$twber_release_dir/windows/packages"
"$twber_godot" --headless --path "$twber_root" --export-release Linux "$twber_release_dir/linux/Twber.x86_64"
"$twber_godot" --headless --path "$twber_root" --export-release "Windows Desktop" "$twber_release_dir/windows/Twber.exe"
cp "$twber_root"/packages/*.pck "$twber_release_dir/windows/packages/"

(
	cd "$twber_release_dir/windows"
	zip -9 -r "$twber_release_dir/Twber-windows-x86_64.zip" Twber.exe packages
)

twber_smoke_config="$(mktemp -d "${TMPDIR:-/tmp}/twber-release-smoke.XXXXXX")"
cleanup_smoke_config() {
	find "$twber_smoke_config" -depth -delete
}
trap cleanup_smoke_config EXIT
for twber_mode in environment editor; do
	TWBER_CONFIG_DIR="$twber_smoke_config/$twber_mode" \
		APPIMAGE_EXTRACT_AND_RUN=1 \
		"$twber_release_dir/linux/Twber.AppImage" \
		--headless --quit-after 8 -- --"$twber_mode"
done
cleanup_smoke_config
trap - EXIT

twber_created_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
{
	printf '{\n'
	printf '  "version": "%s",\n' "$twber_version"
	printf '  "created_at": "%s",\n' "$twber_created_at"
	printf '  "artifacts": ["linux/Twber.AppImage", "Twber-windows-x86_64.zip"]\n'
	printf '}\n'
} > "$twber_release_dir/release.json"

(
	cd "$twber_release_dir"
	find . -type f ! -name SHA256SUMS -print0 \
		| sort -z \
		| xargs -0 sha256sum > SHA256SUMS
)

echo "Release $twber_version is ready at $twber_release_dir"
