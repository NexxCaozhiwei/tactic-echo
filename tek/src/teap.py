from dataclasses import dataclass


class TEAPError(ValueError):
    pass


STATE_BY_CODE = {
    0: "waiting",
    1: "armed",
    2: "paused",
    3: "blocked",
    4: "error",
    5: "channeling",
    6: "empowering",
    7: "manual_hold",
}

STATE_TO_CODE = {value: key for key, value in STATE_BY_CODE.items()}
PROTOCOL_VERSION = 3
TEAP_FIELD_COUNT = 20
COMMIT_BYTE = 0xA5


@dataclass(frozen=True)
class TEAPFrame:
    protocol_version: int
    state: str
    action_code: int
    sequence: int
    checksum: int
    raw_fields: tuple[int, ...]
    session_epoch: int = 0
    frame_freshness_counter: int = 0
    catalog_version: int = 0
    catalog_fingerprint: int = 0
    binding_token: int = 0
    in_combat: bool | None = None
    commit: int | None = None
    observation_only: bool = False
    target_casting: bool = False
    target_interruptible: bool = False
    player_health_critical: bool = False
    monitor_flags: int = 0
    dispatch_origin: str = "official"
    burst_dispatch: bool = False
    reaction_dispatch: bool = False


def decode_fields(fields: list[int] | tuple[int, ...]) -> TEAPFrame:
    """Decode the single supported TEAP v3 20-byte frame.

    Older eight-byte and protocol-v2 fields were removed deliberately: the
    AddOn and TEK now upgrade as one unit and only accept a BindingToken based
    v3 frame.
    """
    raw = tuple(_byte(value) for value in fields)
    if len(raw) != TEAP_FIELD_COUNT:
        raise TEAPError(f"invalid_field_count:{len(raw)}")
    return _decode_v3(raw)


def _decode_v3(raw: tuple[int, ...]) -> TEAPFrame:
    if raw[0] != 84 or raw[1] != 69:
        raise TEAPError("invalid_magic")
    if raw[2] != PROTOCOL_VERSION:
        raise TEAPError(f"unsupported_protocol_version:{raw[2]}")
    if raw[19] != COMMIT_BYTE:
        raise TEAPError(f"commit_mismatch:{raw[19]}:{COMMIT_BYTE}")
    expected_crc = crc16(raw[:17])
    observed_crc = raw[17] + raw[18] * 256
    if observed_crc != expected_crc:
        raise TEAPError(f"crc_mismatch:{observed_crc}:{expected_crc}")
    state = STATE_BY_CODE.get(raw[3])
    if not state:
        raise TEAPError(f"unknown_state:{raw[3]}")

    flags = raw[16]
    burst_dispatch = bool(flags & 0x20)
    reaction_dispatch = bool(flags & 0x40)
    if burst_dispatch and reaction_dispatch:
        raise TEAPError("dispatch_origin_conflict")
    # Compatibility invariant: legacy burst frames remain semantically
    # equivalent to `dispatch_origin="burst"`; Reaction uses a distinct bit.
    dispatch_origin = "reaction" if reaction_dispatch else ("burst" if burst_dispatch else "official")
    return TEAPFrame(
        protocol_version=PROTOCOL_VERSION,
        state=state,
        session_epoch=raw[4] + raw[5] * 256,
        sequence=raw[6] + raw[7] * 256,
        frame_freshness_counter=raw[8] + raw[9] * 256,
        action_code=raw[10],
        catalog_version=raw[11],
        catalog_fingerprint=raw[12] + raw[13] * 256,
        binding_token=raw[14] + raw[15] * 256,
        in_combat=bool(flags & 0x01),
        observation_only=bool(flags & 0x02),
        target_casting=bool(flags & 0x04),
        target_interruptible=bool(flags & 0x08),
        player_health_critical=bool(flags & 0x10),
        monitor_flags=flags & 0x1C,
        dispatch_origin=dispatch_origin,
        burst_dispatch=burst_dispatch,
        reaction_dispatch=reaction_dispatch,
        checksum=observed_crc,
        commit=raw[19],
        raw_fields=raw,
    )


def encode_fields_v3(
    *,
    state: str = "armed",
    session_epoch: int = 1,
    sequence: int = 1,
    frame_freshness_counter: int = 1,
    action_code: int = 1,
    catalog_version: int = 3,
    catalog_fingerprint: int = 53253,
    binding_token: int = 0,
    in_combat: bool = True,
    observation_only: bool = False,
    target_casting: bool = False,
    target_interruptible: bool = False,
    player_health_critical: bool = False,
    dispatch_origin: str = "official",
) -> tuple[int, ...]:
    if dispatch_origin not in {"official", "burst", "reaction"}:
        raise TEAPError(f"invalid_dispatch_origin:{dispatch_origin}")
    flags = (
        (1 if in_combat else 0)
        | (2 if observation_only else 0)
        | (4 if target_casting else 0)
        | (8 if target_interruptible else 0)
        | (16 if player_health_critical else 0)
        | (32 if dispatch_origin == "burst" else 0)
        | (64 if dispatch_origin == "reaction" else 0)
    )
    fields = [
        84,
        69,
        PROTOCOL_VERSION,
        STATE_TO_CODE[state],
        session_epoch % 256,
        session_epoch // 256,
        sequence % 256,
        sequence // 256,
        frame_freshness_counter % 256,
        frame_freshness_counter // 256,
        action_code,
        catalog_version,
        catalog_fingerprint % 256,
        catalog_fingerprint // 256,
        binding_token % 256,
        binding_token // 256,
        flags,
    ]
    crc = crc16(tuple(fields))
    fields.extend([crc % 256, crc // 256, COMMIT_BYTE])
    return tuple(fields)


def crc16(fields: tuple[int, ...]) -> int:
    crc = 0xFFFF
    for value in fields:
        crc ^= _byte(value) << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def _byte(value: int) -> int:
    value = int(value)
    if value < 0 or value > 255:
        raise TEAPError(f"field_out_of_range:{value}")
    return value
