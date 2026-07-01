from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
BOOTSTRAP = ADDON / "Core" / "Bootstrap.lua"


def lua_short_string_issues(text: str) -> list[tuple[int, str]]:
    """Detect literal newlines inside standard Lua short strings.

    Lua's ``\"...\"`` and ``'...'`` strings cannot span an unescaped physical
    line.  The project previously relied on a permissive parser that accepted
    such input, while the WoW client rejected it at load time.
    """
    issues: list[tuple[int, str]] = []
    i = 0
    line = 1
    n = len(text)
    state = "code"
    quote = ""
    string_start = 0

    while i < n:
        char = text[i]
        if state == "code":
            if char in {"'", '"'}:
                state = "short"
                quote = char
                string_start = line
                i += 1
                continue
            if char == "-" and i + 1 < n and text[i + 1] == "-":
                end = text.find("\n", i + 2)
                if end < 0:
                    break
                line += 1
                i = end + 1
                continue
            if char == "\n":
                line += 1
            i += 1
            continue

        if char == "\\":
            if i + 1 < n:
                if text[i + 1] == "\n":
                    line += 1
                i += 2
                continue
            issues.append((line, "dangling escape in short string"))
            break
        if char == quote:
            state = "code"
            quote = ""
            i += 1
            continue
        if char == "\n":
            issues.append((line, f"unescaped newline in {quote} string"))
            line += 1
        i += 1

    if state == "short":
        issues.append((string_start, f"unterminated {quote} string"))
    return issues


class WowLoadHotfixContractTests(unittest.TestCase):
    def test_all_addon_lua_files_have_no_physical_newline_in_short_strings(self) -> None:
        failures: list[str] = []
        for path in sorted(ADDON.rglob("*.lua")):
            for line, message in lua_short_string_issues(path.read_text(encoding="utf-8")):
                failures.append(f"{path.relative_to(ROOT)}:{line}: {message}")
        self.assertEqual([], failures, "\n".join(failures))

    def test_event_registration_gate_is_declared_in_bootstrap(self) -> None:
        text = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn("Event registration policy.", text)
        self.assertIn("function TE:RegisterEventSafe(frame, eventName)", text)
        self.assertIn("function TE:RegisterEventsSafe(frame, eventNames)", text)
        self.assertIn("if isCombatLocked() then", text)
        self.assertIn("load_once_no_retry", text)
        self.assertNotIn("eventRetryFrame:SetScript", text)

    def test_addon_modules_do_not_register_events_directly(self) -> None:
        raw_calls: list[str] = []
        direct = re.compile(r"\b\w+\s*:\s*RegisterEvent\s*\(")
        for path in sorted(ADDON.rglob("*.lua")):
            if path == BOOTSTRAP:
                continue
            if direct.search(path.read_text(encoding="utf-8")):
                raw_calls.append(str(path.relative_to(ROOT)))
        self.assertEqual([], raw_calls)

    def test_protocol_monitor_uses_polling_and_control_panel_uses_the_gate(self) -> None:
        monitor = (ADDON / "Tactics" / "ProtocolMonitor.lua").read_text(encoding="utf-8")
        panel = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.assertIn("polling-only", monitor)
        self.assertIn('SetScript("OnUpdate"', monitor)
        self.assertNotIn("RegisterEventSafe", monitor)
        self.assertIn('TE:RegisterEventsSafe(eventFrame, { "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED" })', panel)



if __name__ == "__main__":
    unittest.main()
