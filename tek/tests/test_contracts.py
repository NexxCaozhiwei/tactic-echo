import re
import unittest
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.profile_resolver import ProfileResolver


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"


def read(path):
    return path.read_text(encoding="utf-8-sig")


def lua_actions():
    text = read(ADDON / "Actions" / "ActionRegistry.lua")
    actions = {}
    for block in re.findall(r"register\(\{(.*?)\}\)", text, flags=re.S):
        action_id = re.search(r'actionId\s*=\s*"([^"]+)"', block).group(1)
        action_code = int(re.search(r"actionCode\s*=\s*(\d+)", block).group(1))
        spell_ids = tuple(int(value) for value in re.search(r"spellIDs\s*=\s*\{([^}]+)\}", block).group(1).split(","))
        macro_strategy = re.search(r'macroStrategy\s*=\s*"([^"]+)"', block)
        macro_cast_spell_id = re.search(r"macroCastSpellID\s*=\s*(\d+)", block)
        macro_cast_spell_ids = re.search(r"macroCastSpellIDs\s*=\s*\{([^}]+)\}", block)
        actions[action_id] = {
            "actionCode": action_code,
            "spellIDs": spell_ids,
            "macroStrategy": macro_strategy.group(1) if macro_strategy else None,
            "macroCastSpellID": int(macro_cast_spell_id.group(1)) if macro_cast_spell_id else None,
            "macroCastSpellIDs": tuple(int(value) for value in macro_cast_spell_ids.group(1).split(",")) if macro_cast_spell_ids else None,
        }
    return actions


def lua_bindings():
    text = read(ADDON / "Profiles" / "BindingProfile.lua")
    return dict(re.findall(r"(PALADIN_RETRIBUTION_[A-Z_]+)\s*=\s*\"([^\"]+)\"", text))


class AddonTekContractTests(unittest.TestCase):
    def test_toc_does_not_load_retired_macro_registry(self):
        toc = [line.strip() for line in read(ADDON / "!TacticEcho.toc").splitlines() if line.strip() and not line.startswith("##")]

        self.assertIn("Profiles/BindingProfile.lua", toc)
        self.assertNotIn("Actions/MacroRegistry.lua", toc)
        self.assertFalse((ADDON / "Actions" / "MacroRegistry.lua").exists())
        for dependency in ["Core/Context.lua", "Actions/ActionRegistry.lua", "Profiles/BindingProfile.lua"]:
            self.assertIn(dependency, toc)

    def test_lua_action_registry_matches_tek_catalog(self):
        lua = lua_actions()

        self.assertEqual(set(lua), RETRIBUTION_V2.action_ids)
        for action in RETRIBUTION_V2.actions:
            self.assertEqual(lua[action.action_id]["actionCode"], action.action_code)
            self.assertEqual(lua[action.action_id]["spellIDs"], action.spell_ids)
            self.assertEqual(lua[action.action_id]["macroStrategy"], action.macro_strategy)

    def test_hammer_of_light_uses_wake_of_ashes_macro_cast_spell(self):
        lua = lua_actions()

        self.assertEqual(lua["PALADIN_RETRIBUTION_HAMMER_OF_LIGHT"]["spellIDs"], (427453,))
        self.assertEqual(lua["PALADIN_RETRIBUTION_HAMMER_OF_LIGHT"]["macroCastSpellID"], 255937)

    def test_judgment_stage_uses_hammer_then_judgment_macro_fallback(self):
        lua = lua_actions()

        self.assertEqual(lua["PALADIN_RETRIBUTION_JUDGMENT"]["macroStrategy"], "fallback_spell_names")
        self.assertEqual(lua["PALADIN_RETRIBUTION_JUDGMENT"]["macroCastSpellIDs"], (24275, 20271))
        self.assertEqual(lua["PALADIN_RETRIBUTION_HAMMER_OF_WRATH"]["macroStrategy"], "fallback_spell_names")
        self.assertEqual(lua["PALADIN_RETRIBUTION_HAMMER_OF_WRATH"]["macroCastSpellIDs"], (24275, 20271))

    def test_default_actions_have_wow_and_tek_bindings(self):
        wow_bindings = lua_bindings()
        tek_profile = ProfileResolver.from_file(LAPTOP).profile

        self.assertEqual(set(wow_bindings), RETRIBUTION_V2.action_ids)
        self.assertEqual(set(tek_profile.bindings), RETRIBUTION_V2.action_ids)
        for action_id, wow_binding in wow_bindings.items():
            self.assertEqual(wow_binding.replace("-", "+"), tek_profile.bindings[action_id])


if __name__ == "__main__":
    unittest.main()
