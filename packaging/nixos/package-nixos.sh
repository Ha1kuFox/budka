#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
build="$root/build/linux"
out="${1:-$root/build/nixos}"

test -x "$build/Budka.x86_64" || {
	echo "Linux export not found: $build/Budka.x86_64" >&2
	exit 1
}

rm -rf "$out"
mkdir -p "$out"
cp "$build/Budka.x86_64" "$out/"
cp "$build"/*.so "$out/" 2>/dev/null || true
cp "$root/assets/logo_badka.png" "$out/logo_badka.png"
cp "$root/packaging/nixos/budka-launcher.sh" "$out/"
cp "$root/packaging/nixos/install-nixos.sh" "$out/"
cp "$root/packaging/nixos/Budka.desktop.in" "$out/"
chmod +x "$out/Budka.x86_64" "$out/budka-launcher.sh" "$out/install-nixos.sh"

sed -e "s|@APP@|$out|g" -e "s|@ICON@|$out/logo_badka.png|g" \
	"$root/packaging/nixos/Budka.desktop.in" > "$out/Budka.desktop"
chmod +x "$out/Budka.desktop"

echo "NixOS package: $out"
