import hashlib
import json
from dataclasses import dataclass


class ActionCatalogError(ValueError):
    pass


@dataclass(frozen=True)
class CatalogAction:
    action_code: int
    action_id: str
    spell_ids: tuple[int, ...]
    macro_strategy: str


@dataclass(frozen=True)
class ActionCatalog:
    version: int
    actions: tuple[CatalogAction, ...]
    fingerprint: str

    def resolve(self, action_code: int) -> str:
        for action in self.actions:
            if action.action_code == action_code:
                return action.action_id
        raise ActionCatalogError(f"unknown_action_code:{action_code}")

    @property
    def fingerprint16(self) -> int:
        return int(self.fingerprint[:4], 16)

    @property
    def action_ids(self) -> set[str]:
        return {action.action_id for action in self.actions}

    @property
    def actions_by_code(self) -> dict[int, str]:
        return {action.action_code: action.action_id for action in self.actions}

    @property
    def codes_by_action_id(self) -> dict[str, int]:
        return {action.action_id: action.action_code for action in self.actions}

    def validate(self) -> None:
        action_ids = set()
        action_codes = set()
        spell_ids = {}
        for action in self.actions:
            if action.action_id in action_ids:
                raise ActionCatalogError(f"duplicate_action_id:{action.action_id}")
            if action.action_code in action_codes:
                raise ActionCatalogError(f"duplicate_action_code:{action.action_code}")
            action_ids.add(action.action_id)
            action_codes.add(action.action_code)
            if len(action.spell_ids) > 1 and not action.macro_strategy:
                raise ActionCatalogError(f"macro_strategy_required:{action.action_id}")
            for spell_id in action.spell_ids:
                previous = spell_ids.get(spell_id)
                if previous and previous != action.action_id:
                    raise ActionCatalogError(f"ambiguous_spell_id:{spell_id}:{previous}:{action.action_id}")
                spell_ids[spell_id] = action.action_id

        expected = catalog_fingerprint(self.version, self.actions)
        if expected != self.fingerprint:
            raise ActionCatalogError(f"catalog_fingerprint_mismatch:{self.fingerprint}:{expected}")


def catalog_fingerprint(version: int, actions: tuple[CatalogAction, ...]) -> str:
    payload = {
        "catalogVersion": version,
        "actions": [
            {
                "actionCode": action.action_code,
                "actionId": action.action_id,
                "spellIDs": list(action.spell_ids),
                "macroStrategy": action.macro_strategy,
            }
            for action in actions
        ],
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16]


RETRIBUTION_ACTIONS_V2 = (
    CatalogAction(1, "PALADIN_RETRIBUTION_JUDGMENT", (20271,), "fallback_spell_names"),
    CatalogAction(2, "PALADIN_RETRIBUTION_BLADE_OF_JUSTICE", (184575,), "single_spell_name"),
    CatalogAction(3, "PALADIN_RETRIBUTION_DIVINE_STORM", (53385,), "single_spell_name"),
    CatalogAction(4, "PALADIN_RETRIBUTION_TEMPLAR_STRIKE", (407480, 406647), "primary_spell_name_manual_verify"),
    CatalogAction(5, "PALADIN_RETRIBUTION_HAMMER_OF_WRATH", (24275,), "fallback_spell_names"),
    CatalogAction(6, "PALADIN_RETRIBUTION_WAKE_OF_ASHES", (255937,), "single_spell_name"),
    CatalogAction(7, "PALADIN_RETRIBUTION_DIVINE_TOLL", (375576,), "single_spell_name"),
    CatalogAction(8, "PALADIN_RETRIBUTION_HAMMER_OF_LIGHT", (427453,), "cast_override_spell_name"),
    CatalogAction(9, "PALADIN_RETRIBUTION_FINAL_VERDICT", (383328,), "single_spell_name"),
    CatalogAction(10, "PALADIN_RETRIBUTION_EXECUTION_SENTENCE", (343527,), "single_spell_name"),
)

RETRIBUTION_V2 = ActionCatalog(
    version=2,
    actions=RETRIBUTION_ACTIONS_V2,
    fingerprint=catalog_fingerprint(2, RETRIBUTION_ACTIONS_V2),
)
RETRIBUTION_V2.validate()

# Compatibility name for older callers; v1 frames are still decoded but fail closed in the gate.
RETRIBUTION_V1 = RETRIBUTION_V2
