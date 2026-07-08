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


GENERIC_ACTIONS_V3: tuple[CatalogAction, ...] = ()

GENERIC_V3 = ActionCatalog(
    version=3,
    actions=GENERIC_ACTIONS_V3,
    fingerprint=catalog_fingerprint(3, GENERIC_ACTIONS_V3),
)
GENERIC_V3.validate()

# Compatibility names for older callers.  TEAP v3 now dispatches solely through
# BindingToken, so the catalog is an empty protocol identity rather than a
# class- or specialization-specific action list.
RETRIBUTION_ACTIONS_V2 = GENERIC_ACTIONS_V3
RETRIBUTION_V2 = GENERIC_V3
RETRIBUTION_V1 = GENERIC_V3
