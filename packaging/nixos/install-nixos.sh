#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
app="$data/budka"
icons="$data/icons/hicolor/512x512/apps"
desktop="$data/applications"

command -v steam-run >/dev/null 2>&1 || {
	echo "steam-run not found. Install it (nix-shell -p steam-run) or run the game through Steam." >&2
	exit 1
}
test -x "$here/Budka.x86_64" || {
	echo "Budka.x86_64 not found next to this installer." >&2
	exit 1
}

mkdir -p "$app" "$icons" "$desktop"
cp "$here/Budka.x86_64" "$app/"
cp "$here"/*.so "$app/" 2>/dev/null || true
cp "$here/logo_badka.png" "$icons/budka.png"

sed -e "s|@APP@|$app|g" -e "s|@ICON@|$icons/budka.png|g" \
	"$here/Budka.desktop.in" > "$desktop/Budka.desktop" 2>/dev/null || \
	cat > "$desktop/Budka.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Будка
Name[en]=Budka
Comment=Голосовой чат и трансляция экрана через Steam
Comment[en]=Steam voice chat and screen sharing
Exec=steam-run $app/Budka.x86_64
Path=$app
Icon=$icons/budka.png
Terminal=false
Categories=Network;
Keywords=voice;chat;steam;screen;share;
StartupWMClass=Budka
DESKTOP

chmod +x "$app/Budka.x86_64"
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database "$desktop" || true
fi
echo "Installed to $app; desktop entry: $desktop/Budka.desktop"
