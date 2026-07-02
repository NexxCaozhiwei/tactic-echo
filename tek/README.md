# TEK

Current version: `1.0.07`

TEK is the Windows companion for Tactic Echo. Normal users should launch:

```text
TEK.exe
```

The one-click Windows build entry is:

```powershell
.\TEKEXEBUILD.CMD
```

TEK does not choose skills. It reads TEAP v3 frames from the WoW client, validates foreground and protocol safety gates, decodes BindingToken values and sends input only when every gate passes.

## Runtime Contract

- v3 BindingToken dispatch is the current path.
- `waiting`, `paused`, `manual_hold`, `channeling` and `empowering` are non-dispatch states.
- WoW foreground, frame freshness, catalog fingerprint, BindingToken validity, physical input hook health, manual-input cooperation and rate limits remain required.
- Windows tray, hook, DPI/multi-monitor and real SendInput behavior require live-machine validation.

## Directories

```text
tek/src/      TEAP, core engine, input planning, screen sampling and foreground adapters
tek/runtime/  status snapshots, status mapping, status persistence and trace helpers
tek/app/      TEK.exe app layer, tray, status window, settings and worker lifecycle
tek/assets/   icons and packaging assets
tek/tests/    offline automated tests
```

## Development Checks

From the repository root:

```powershell
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m compileall -q tek/src tek/app tek/runtime
```

See `../README.md`, `../HANDOFF.md` and `../docs/TEK_EXE.md` for the current project contract and user-facing behavior.
