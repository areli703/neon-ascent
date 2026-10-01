#!/usr/bin/env bash
# Rebuild build/NeonAscent.rbxl from source.
#
# Requires the Rojo toolchain. On Windows/macOS/Linux the easiest way to get
# a pinned, reproducible set of versions is Rokit:
#
#     https://github.com/rojo-rbx/rokit
#     rokit install          # reads rokit.toml, installs every pinned tool
#
# Then just run this script.

set -euo pipefail

cd "$(dirname "$0")"

if ! command -v rojo >/dev/null 2>&1; then
	echo "error: rojo not found on PATH." >&2
	echo "       install it with rokit (see the comment at the top of this script)" >&2
	exit 1
fi

mkdir -p build
rojo build default.project.json -o build/NeonAscent.rbxl

echo "built build/NeonAscent.rbxl"
