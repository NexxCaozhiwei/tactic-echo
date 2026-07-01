from dataclasses import dataclass

from tek.src.teap import TEAPFrame, TEAP_FIELD_COUNT, decode_fields


class VisualDecodeError(ValueError):
    pass


@dataclass(frozen=True)
class RGB:
    red: int
    green: int
    blue: int


def decode_rgb_blocks(blocks: list[RGB] | tuple[RGB, ...], tolerance: int = 2) -> TEAPFrame:
    if len(blocks) != TEAP_FIELD_COUNT:
        raise VisualDecodeError(f"invalid_block_count:{len(blocks)}")

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
