# L

Small logging addon with **clickable source locations** in the Godot editor and
plain console output in exported builds.

```gdscript
L.debug("details")
L.info("player joined: %s" % name)
L.warn("region is missing")
L.error("could not load level")
L.fatal("unrecoverable state")
```

`L.fatal()` prints the message plus the complete GDScript call stack and then
calls `OS.crash()`. It intentionally kills the game (and can kill the editor if
called from a `@tool` script), so use it only for states that must never happen.

In the editor, a line looks like:

```text
player.gd:42 [INFO] player joined: Haikyo
```

`player.gd:42` is clickable and opens that script at the caller's line. In an
export the same call becomes:

```text
[INFO] player joined: Haikyo
```

`L.error()` writes to `stderr` in exports; the other levels use `stdout`.
`debug` is visible in the editor and suppressed by default in exports.

## API

```gdscript
L.debug(message, stack_depth = 1)
L.info(message, stack_depth = 1)
L.warn(message, stack_depth = 1)
L.error(message, stack_depth = 1)
L.fatal(message)
L.set_min_level(L.Level.INFO)
```

`stack_depth = 1` points at the direct caller. Use `2` from a reusable helper
that wraps the logger.

## Install

1. Copy `addons/l/`.
2. Enable **L** in Project Settings → Plugins. The plugin registers the
   `L` autoload and attaches the output-panel listener.
3. If your project already has an `L` autoload, the plugin leaves it alone.

The clickable behavior relies on the editor-only Output panel listener. The
logger itself has no scene dependencies and is safe in exported builds.

## Credit

The clickable editor-log approach is adapted from
[graydoubt/gg_print](https://github.com/graydoubt/gg_print) (MIT). See
`LICENSE`.
