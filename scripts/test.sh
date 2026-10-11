#!/usr/bin/env bash
set -euo pipefail

twber_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
twber_godot="${GODOT:-}"

if [[ -z "$twber_godot" ]]; then
	if command -v godot >/dev/null 2>&1; then
		twber_godot="$(command -v godot)"
	else
		twber_version="$(awk 'NR == 1 { print $1 }' "$twber_root/.godotrc")"
		twber_candidate="$(find "$twber_root/../.versions/$twber_version" -maxdepth 1 -type f -perm -u+x -name 'Godot_*' -print -quit)"
		if [[ -n "$twber_candidate" ]]; then
			twber_godot="$twber_candidate"
		fi
	fi
fi

if [[ -z "$twber_godot" || ! -x "$twber_godot" ]]; then
	echo "Set GODOT to a compatible Godot editor executable." >&2
	exit 1
fi

twber_test_config="$(mktemp -d "${TMPDIR:-/tmp}/twber-tests.XXXXXX")"
export TWBER_CONFIG_DIR="$twber_test_config"
trap 'find "$twber_test_config" -depth -delete' EXIT

"$twber_godot" --headless --path "$twber_root" --editor --quit
"$twber_godot" --headless --path "$twber_root" --script tools/build_packages_cli.gd
"$twber_godot" --headless --path "$twber_root" --script testing/run_tests.gd
"$twber_godot" --headless --path "$twber_root" --script testing/test_model_rework.gd
"$twber_godot" --headless --path "$twber_root" --script testing/test_parameter_tracks.gd
"$twber_godot" --headless --path "$twber_root" --script testing/test_recording_export.gd
"$twber_godot" --headless --path "$twber_root" --script testing/test_environment_recording.gd
"$twber_godot" --headless --path "$twber_root" --script testing/test_sprite_clock.gd
"$twber_godot" --headless --path "$twber_root" --script testing/test_environment.gd
"$twber_godot" --headless --path "$twber_root" --script testing/test_delivery.gd

if command -v xvfb-run >/dev/null 2>&1; then
	xvfb-run -a "$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_renderer.gd
	xvfb-run -a "$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_recording_export.gd
	xvfb-run -a "$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_environment_recording.gd
	xvfb-run -a "$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_sprite_clock.gd
else
	"$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_renderer.gd
	"$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_recording_export.gd
	"$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_environment_recording.gd
	"$twber_godot" --path "$twber_root" --rendering-method gl_compatibility --script testing/test_sprite_clock.gd
fi
