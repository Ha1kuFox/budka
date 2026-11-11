#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if command -v steam-run >/dev/null 2>&1; then
	exec steam-run "$here/Budka.x86_64" "$@"
fi
exec "$here/Budka.x86_64" "$@"
