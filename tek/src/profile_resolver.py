import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from tek.src.action_catalog import ActionCatalog, RETRIBUTION_V2
from tek.src.input_planner import InputPlanError, normalize_binding, validate_binding


class ProfileError(ValueError):
    pass


@dataclass(frozen=True)
class Profile:
    schema_version: int
    catalog_version: int
    catalog_fingerprint: str
    profile_id: str
    profile_fingerprint: str
    display_name: str
    bindings: dict[str, str]
    runnable: bool = True
    runtime_status: str = "runnable"

    @property
    def profile_fingerprint16(self) -> int:
        return int(self.profile_fingerprint[:4], 16)


class ProfileResolver:
    def __init__(self, profile: Profile):
        self.profile = profile

    @classmethod
    def from_file(cls, path: str | Path, catalog: ActionCatalog = RETRIBUTION_V2):
        data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
        return cls(load_profile(data, catalog=catalog))

    def resolve(self, action_id: str) -> str:
        try:
            return self.profile.bindings[action_id]
        except KeyError as error:
            raise ProfileError(f"action_unbound:{action_id}") from error


def load_profile(data: dict, catalog: ActionCatalog = RETRIBUTION_V2) -> Profile:
    if data.get("schemaVersion") != 1:
        raise ProfileError("unsupported_schema_version")

    required_action_ids = catalog.action_ids
    if not required_action_ids:
        profile_id = data.get("profileId") or "generic-binding-token"
        if not isinstance(profile_id, str) or not profile_id:
            raise ProfileError("profile_id_required")
        normalized: dict[str, str] = {}
        expected_profile_fingerprint = profile_fingerprint(profile_id, normalized)
        return Profile(
            schema_version=1,
            catalog_version=catalog.version,
            catalog_fingerprint=catalog.fingerprint,
            profile_id=profile_id,
            profile_fingerprint=expected_profile_fingerprint,
            display_name=str(data.get("displayName") or profile_id),
            bindings=normalized,
            runnable=data.get("runnable", True) is True,
            runtime_status=str(data.get("runtimeStatus") or ("runnable" if data.get("runnable", True) is True else "example_only")),
        )

    catalog_version = data.get("catalogVersion")
    if catalog_version != catalog.version:
        raise ProfileError(f"catalog_version_mismatch:{catalog_version}:{catalog.version}")

    catalog_fingerprint = data.get("catalogFingerprint")
    if catalog_fingerprint != catalog.fingerprint:
        raise ProfileError(f"catalog_fingerprint_mismatch:{catalog_fingerprint}:{catalog.fingerprint}")

    profile_id = data.get("profileId")
    if not isinstance(profile_id, str) or not profile_id:
        raise ProfileError("profile_id_required")

    display_name = data.get("displayName") or profile_id
    bindings = data.get("bindings")
    if not isinstance(bindings, dict) or not bindings:
        raise ProfileError("bindings_required")

    observed_action_ids = set(bindings.keys())
    missing = sorted(required_action_ids - observed_action_ids)
    if missing:
        raise ProfileError(f"missing_required_actions:{','.join(missing)}")
    unknown = sorted(observed_action_ids - required_action_ids)
    if unknown:
        raise ProfileError(f"unknown_action_ids:{','.join(unknown)}")

    runnable = data.get("runnable", True) is True
    normalized = {}
    seen_bindings = {}
    for action_id, binding in bindings.items():
        if not isinstance(action_id, str) or not action_id:
            raise ProfileError("invalid_action_id")
        if not isinstance(binding, str) or not binding:
            raise ProfileError(f"invalid_binding:{action_id}")
        try:
            normalized_binding = normalize_binding(binding)
            validate_binding(normalized_binding, allow_unsupported_main=not runnable)
        except InputPlanError as error:
            raise ProfileError(f"invalid_binding:{action_id}:{error}") from error
        previous = seen_bindings.get(normalized_binding)
        if previous:
            raise ProfileError(f"duplicate_physical_binding:{normalized_binding}:{previous}:{action_id}")
        seen_bindings[normalized_binding] = action_id
        normalized[action_id] = normalized_binding

    expected_profile_fingerprint = profile_fingerprint(profile_id, normalized)
    supplied_profile_fingerprint = data.get("profileFingerprint")
    if supplied_profile_fingerprint != expected_profile_fingerprint:
        raise ProfileError(
            f"profile_fingerprint_mismatch:{supplied_profile_fingerprint}:{expected_profile_fingerprint}"
        )

    return Profile(
        schema_version=1,
        catalog_version=catalog_version,
        catalog_fingerprint=catalog_fingerprint,
        profile_id=profile_id,
        profile_fingerprint=expected_profile_fingerprint,
        display_name=str(display_name),
        bindings=normalized,
        runnable=runnable,
        runtime_status=str(data.get("runtimeStatus") or ("runnable" if runnable else "example_only")),
    )


def profile_fingerprint(profile_id: str, bindings: dict[str, str]) -> str:
    payload = {"profileId": profile_id, "bindings": bindings}
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16]


def assert_no_numpad(profile: Profile):
    for action_id, binding in profile.bindings.items():
        if "NUMPAD" in binding:
            raise ProfileError(f"numpad_not_allowed:{action_id}")
