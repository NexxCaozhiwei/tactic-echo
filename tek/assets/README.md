# Tactic Echo Key Assets

Place the TEK desktop icon source here as:

```text
tek.png
tek.ico
TEK_BLUE.png
TEK_GREY.png
TEK_RED.png
TEK_YELLOW.png
```

`tek.ico` is used by `scripts/build-tek-exe.ps1` as the Windows executable icon when present. The tray app also prefers `tek.ico` or `tek.png` and overlays the current TEK state color.

The tray app uses the state PNGs directly when present:

- `TEK_GREY.png`: Stopped / worker not running.
- `TEK_BLUE.png`: Dry-run and Armed states. Armed uses blue until a dedicated green asset exists.
- `TEK_YELLOW.png`: Paused / AwaitingStartToggle.
- `TEK_RED.png`: Blocked / ErrorLocked / worker errors.
