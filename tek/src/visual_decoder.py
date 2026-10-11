from dataclasses import dataclass
from functools import lru_cache
from math import floor
from itertools import product

from tek.src.teap import TEAPFrame, TEAP_FIELD_COUNT, decode_fields


class VisualDecodeError(ValueError):
    pass


@dataclass(frozen=True)
class RGB:
    red: int
    green: int
    blue: int


# Shared TE/TEF colour transport; only the live-CRC-verified transform is added.
SUPPORTED_DISPLAY_GAMMAS = (1.0, 1.2)


def protocol_colour(value: int, gamma: float = 1.0) -> RGB:
    def channel(v):
        return floor(255 * (v / 255) ** (1 / gamma) + 0.5)
    return RGB(channel(value), channel(255 - value), channel(17))


@lru_cache(maxsize=2)
def _colour_table(gamma):
    return tuple(protocol_colour(value, gamma) for value in range(256))


def _gamma_candidates(blocks, gamma):
    choices = []
    combinations = 1
    for block in blocks:
        if any(not isinstance(v, int) or not 0 <= v <= 255 for v in (block.red, block.green, block.blue)):
            raise VisualDecodeError("gamma_channel_invalid")
        candidates = []
        for value, expected in enumerate(_colour_table(gamma)):
            dr, dg, db = abs(block.red-expected.red), abs(block.green-expected.green), abs(block.blue-expected.blue)
            if dr <= 1 and dg <= 1 and db <= 2:
                candidates.append((dr+dg, value))
        candidates.sort()
        if not candidates:
            raise VisualDecodeError("gamma_colour_unknown")
        best=[value for score,value in candidates if score==candidates[0][0]]
        combinations *= len(best)
        if combinations > 64:
            raise VisualDecodeError("gamma_colour_ambiguity_limit")
        choices.append(best)
    return choices


def _gamma_fields(blocks,gamma):
    choices=_gamma_candidates(blocks,gamma)
    if any(len(values)!=1 for values in choices):
        raise VisualDecodeError("gamma_colour_ambiguous")
    return [values[0] for values in choices]


def _decode_gamma(blocks,gamma):
    from tek.src.teap import TEAPError
    accepted=[]
    for fields in product(*_gamma_candidates(blocks,gamma)):
        try: accepted.append(decode_fields(fields))
        except TEAPError: continue
        if len(accepted)>1: raise VisualDecodeError("gamma_multiple_valid_frames")
    if not accepted: raise TEAPError("gamma_no_crc_valid_frame")
    return accepted[0]


def decode_rgb_blocks(blocks: list[RGB] | tuple[RGB, ...], tolerance: int = 2) -> TEAPFrame:
    if len(blocks) != TEAP_FIELD_COUNT:
        raise VisualDecodeError(f"invalid_block_count:{len(blocks)}")

    # Fixed header selects the transform. Quantization ties are bounded to
    # 64 combinations; exactly one complete CRC/commit-valid frame is required.
    for gamma in SUPPORTED_DISPLAY_GAMMAS[1:]:
        if all(max(abs(b.red-c.red), abs(b.green-c.green), abs(b.blue-c.blue)) <= 2
               for b,c in zip(blocks[:3], (protocol_colour(v,gamma) for v in (84,69,3)))):
            return _decode_gamma(blocks,gamma)
    fields = []
    for block in blocks:
        validate_block(block, tolerance=tolerance)
        fields.append(block.red)
    return decode_fields(fields)


def decode_stable_rgb_samples(
    first: list[RGB] | tuple[RGB, ...],
    second: list[RGB] | tuple[RGB, ...],
    tolerance: int = 2,
) -> TEAPFrame:
    if tuple(first) != tuple(second):
        raise VisualDecodeError("unstable_frame_sample")
    return decode_rgb_blocks(first, tolerance=tolerance)


def validate_block(block: RGB, tolerance: int):
    for channel_name, value in [("red", block.red), ("green", block.green), ("blue", block.blue)]:
        if value < 0 or value > 255:
            raise VisualDecodeError(f"{channel_name}_out_of_range:{value}")

    expected_green = 255 - block.red
    if abs(block.green - expected_green) > tolerance:
        raise VisualDecodeError(f"green_mismatch:{block.green}:{expected_green}")

    if abs(block.blue - 17) > tolerance:
        raise VisualDecodeError(f"blue_mismatch:{block.blue}:17")


def encode_test_blocks(fields: list[int] | tuple[int, ...]) -> tuple[RGB, ...]:
    return tuple(RGB(red=int(value), green=255 - int(value), blue=17) for value in fields)
