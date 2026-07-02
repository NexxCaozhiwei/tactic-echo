from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
VERSION = ROOT / "VERSION"


class AuditHardeningContractTests(unittest.TestCase):
    def test_version_is_single_source_consistent(self) -> None:
        root_version = VERSION.read_text(encoding="utf-8").strip()
        bootstrap = (ADDON / "Core" / "Bootstrap.lua").read_text(encoding="utf-8")
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        addon_match = re.search(r'TE\.version\s*=\s*"([^"\n]+)"', bootstrap)
        toc_match = re.search(r'^## Version:\s*(.+)$', toc, re.MULTILINE)
        self.assertRegex(root_version, r"^\d+\.\d+\.\d+$")
        self.assertIsNotNone(addon_match)
        self.assertIsNotNone(toc_match)
        self.assertEqual(root_version, addon_match.group(1))
        self.assertEqual(root_version, toc_match.group(1).strip())

    def test_live_cast_status_has_one_signalframe_source_without_tactical_event_hooks(self) -> None:
        monitor = (ADDON / "Tactics" / "ProtocolMonitor.lua").read_text(encoding="utf-8")
        icon = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        for text in (monitor, icon, advisors):
            self.assertNotIn("RegisterEventSafe", text)
        self.assertIn("polling-only", monitor)
        self.assertIn("pcall(UnitCastingInfo", monitor)
        self.assertIn("GetCastDisplayInfo", icon)
        self.assertNotIn("UnitCastingInfo", icon)
        self.assertNotIn("UnitChannelInfo", icon)
        self.assertIn("CreateRefreshContext(primary)", icon)
        self.assertIn("CreateRefreshContext(primary)", advisors)

    def test_retired_macro_registry_is_not_loaded(self) -> None:
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        self.assertNotIn("Actions/MacroRegistry.lua", toc)
        self.assertFalse((ADDON / "Actions" / "MacroRegistry.lua").exists())

    def test_environment_and_queue_fail_closed(self) -> None:
        environment = (ADDON / "Tactics" / "EnvironmentCompatibility.lua").read_text(encoding="utf-8")
        queue = (ADDON / "Tactics" / "RecommendationQueue.lua").read_text(encoding="utf-8")
        for marker in ("observedAt", "ttlSeconds", "state = \"stale\"", "available = fresh"):
            self.assertIn(marker, environment)
        for marker in ("normalizedOrder", "VALID[bucket]", "for _, bucket in ipairs(DEFAULT)"):
            self.assertIn(marker, queue)

    def test_macro_text_fallback_is_direct_only_and_second_binding_is_considered(self) -> None:
        resolver = (ADDON / "Actions" / "ActionBarBindingResolver.lua").read_text(encoding="utf-8")
        semantics = (ADDON / "Actions" / "MacroSemantics.lua").read_text(encoding="utf-8")
        self.assertIn("Only one unconditioned /cast line", resolver)
        self.assertIn('argument:find(";", 1, true)', resolver)
        self.assertIn("primaryBinding, secondaryBinding", resolver)
        self.assertIn("directSlotEligible", semantics)
        self.assertIn("hasMultipleActionLines", semantics)

    def test_icon_target_state_is_role_scoped(self) -> None:
        icon = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.assertIn("requiresHostileTarget ~= true", icon)
        self.assertIn("targetChecked = options.requiresHostileTarget == true", icon)
        self.assertIn('interrupt = { requiresHostileTarget = true }', advisors)
        self.assertIn('defense = { requiresHostileTarget = false }', advisors)


if __name__ == "__main__":
    unittest.main()
