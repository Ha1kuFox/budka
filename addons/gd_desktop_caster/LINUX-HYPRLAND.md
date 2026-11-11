# Linux/Hyprland build

`bin/libgd_desktop_caster.linux.release.x86_64.so` is not the upstream v0.6.0
binary. It is built from
[pescador-barquero/gd-desktop-caster](https://github.com/pescador-barquero/gd-desktop-caster)
branch `hyprland_dma-buf` plus the local pipewire lifecycle patch in
`linux-hyprland.patch`.

Why:

- Upstream drops DMA-BUF frames on Hyprland, so the texture stays black. The
  fork asks the portal for a CPU-readable raw format instead.
- Upstream crashes in `libpipewire` when capture stops, because
  `pipewire::deinit()` runs before the PipeWire handles are dropped. The patch
  drops the listener, receiver, stream, context and main loop first, and only
  then calls `pipewire::deinit()`, so every portal session can be started and
  stopped repeatedly.

Windows and macOS binaries are the upstream v0.6.0 files and are unchanged.

Rebuild (Linux):

```sh
git clone --depth 1 -b hyprland_dma-buf \
  https://github.com/pescador-barquero/gd-desktop-caster
cd gd-desktop-caster
git apply /path/to/linux-hyprland.patch
cd rust && cargo build --release
cp target/release/libgd_desktop_caster.so \
  <project>/addons/gd_desktop_caster/bin/libgd_desktop_caster.linux.release.x86_64.so
```
