import argparse
import sys
import time
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.engine import TEKEngine
from tek.src.profile_resolver import ProfileResolver
from tek.src.runner import RunnerConfig, TEKRunner
from tek.src.safety_gate import SafetyContext
from tek.src.teap import TEAPError, decode_fields
from tek.src.trace import render_trace, write_trace
from tek.src.visual_decoder import RGB, decode_rgb_blocks
from tek.src.screen_sampler import GDIPixelSampler, PillowScreenSampler, SignalLayout, locate_te_signal_layout, runtime_pixel_sampler
from tek.src.windows_foreground import WindowsForegroundDetector
from tek.src.windows_sendinput import WindowsSendInputDispatcher


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="tek", description="Tactic Echo Key POC runner")
    parser.add_argument("--profile", default="examples/profiles/laptop.json")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--fields", help="Comma-separated 20 TEAP v3 byte fields")
    source.add_argument("--rgb", help="Comma-separated 20 TEAP v3 RGB blocks, each as R:G:B")
    source.add_argument("--sample-screen", action="store_true", help="Sample the fixed TE signal position from the desktop")
    source.add_argument("--live", action="store_true", help="Run the standard TE screen-sampling loop with foreground checks")
    parser.add_argument("--signal-x", type=int, default=12)
    parser.add_argument("--signal-y", type=int, default=12)
    parser.add_argument("--signal-block-size", type=int, default=10)
    parser.add_argument("--signal-block-gap", type=int, default=2)
    parser.add_argument("--auto-locate-signal", action="store_true", help="Auto-detect the TEAP v3 color blocks on screen")
    parser.add_argument("--sampler", choices=["auto", "pillow", "gdi"], default="pillow", help="Runtime sampler: Pillow is default; GDI is experimental.")
    parser.add_argument("--last-sequence", type=int, default=-1)
    parser.add_argument("--tek-paused", action="store_true")
    parser.add_argument("--assume-wow-foreground", action="store_true")
    parser.add_argument("--check-foreground", action="store_true")
    parser.add_argument("--send-input", action="store_true", help="Actually dispatch SendInput after all gates pass")
    parser.add_argument("--confirm-send-input", default=None, help="Required literal confirmation when --send-input is used")
    parser.add_argument("--trace", default=None, help="Optional JSONL trace output path")
    parser.add_argument("--loop", action="store_true", help="Run repeatedly instead of processing one frame")
    parser.add_argument("--max-frames", type=int, default=None)
    parser.add_argument("--interval", type=float, default=0.05)
    parser.add_argument("--dispatch-budget", type=int, default=None, help="Optional development cap for real SendInput dispatches")
    parser.add_argument("--require-start-toggle", action="store_true", help="For real input, wait for a paused/non-armed frame and then a fresh armed frame before dispatching")
    args = parser.parse_args(argv)

    try:
        normalize_args(args)
        validate_live_args(args)
        validate_send_input_args(args)
        resolver = ProfileResolver.from_file(Path(args.profile), catalog=RETRIBUTION_V2)
        validate_profile_runtime(args, resolver)
        dispatcher = WindowsSendInputDispatcher() if args.send_input else None
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=resolver,
            input_dispatcher=dispatcher,
        )
        if args.loop:
            runner = TEKRunner(engine, build_frame_source(args), foreground_source=build_foreground_source(args))
            runner.context.last_sequence = args.last_sequence
            records = runner.run(RunnerConfig(
                interval_seconds=args.interval,
                max_frames=args.max_frames,
                trace_path=args.trace,
                tek_armed=not args.tek_paused,
                assume_wow_foreground=args.assume_wow_foreground,
                dispatch_budget=args.dispatch_budget if args.send_input else None,
                require_start_toggle=args.require_start_toggle if args.send_input else False,
            ))
            record = records[-1]
        else:
            frame = decode_cli_frame(args)
            wow_foreground = resolve_foreground(args)
            context = SafetyContext(
                tek_armed=not args.tek_paused,
                wow_foreground=wow_foreground,
                last_sequence=args.last_sequence,
                bootstrapped=True,
                dispatch_budget=args.dispatch_budget if args.send_input else None,
                require_start_toggle=args.require_start_toggle if args.send_input else False,
            )
            record = engine.process_frame(frame, context)
    except (OSError, ValueError, TEAPError) as error:
        print(f"TEK error: {error}", file=sys.stderr)
        return 2

    if args.trace:
        if args.loop:
            print(render_trace(record))
            return 0
        write_trace(record, args.trace)
    print(render_trace(record))
    return 0


def parse_fields(value: str) -> list[int]:
    fields = [part.strip() for part in value.split(",") if part.strip()]
    if len(fields) != 20:
        raise ValueError(f"expected_20_fields:{len(fields)}")
    return [int(part, 0) for part in fields]


def parse_rgb_blocks(value: str) -> list[RGB]:
    blocks = [part.strip() for part in value.split(",") if part.strip()]
    if len(blocks) != 20:
        raise ValueError(f"expected_20_rgb_blocks:{len(blocks)}")

    parsed = []
    for block in blocks:
        channels = [part.strip() for part in block.split(":")]
        if len(channels) != 3:
            raise ValueError(f"invalid_rgb_block:{block}")
        parsed.append(RGB(red=int(channels[0]), green=int(channels[1]), blue=int(channels[2])))
    return parsed


def decode_cli_frame(args):
    if args.fields:
        return decode_fields(parse_fields(args.fields))
    if args.rgb:
        return decode_rgb_blocks(parse_rgb_blocks(args.rgb))
    layout = make_layout(args)
    return decode_rgb_blocks(make_sampler(args).sample(layout))


def build_frame_source(args):
    if args.sample_screen:
        return ScreenFrameSource(make_layout(args), make_sampler(args))
    return SingleFrameSource(decode_cli_frame(args))


def resolve_foreground(args) -> bool:
    if args.assume_wow_foreground:
        return True
    if args.check_foreground:
        return WindowsForegroundDetector().is_wow_foreground()
    return False


def build_foreground_source(args):
    if args.check_foreground and not args.assume_wow_foreground:
        return WindowsForegroundDetector()
    return None


def validate_send_input_args(args) -> None:
    if not args.send_input:
        return
    if args.confirm_send_input != "I_UNDERSTAND_TEK_SENDS_KEYS":
        raise ValueError("send_input_requires_confirmation")
    if not args.trace:
        raise ValueError("send_input_requires_trace")
    if args.assume_wow_foreground:
        raise ValueError("send_input_cannot_assume_foreground")
    if not args.check_foreground:
        raise ValueError("send_input_requires_check_foreground")


def normalize_args(args) -> None:
    if not getattr(args, "live", False):
        return
    args.sample_screen = True
    args.loop = True
    args.check_foreground = True


def validate_live_args(args) -> None:
    if not getattr(args, "live", False):
        return
    if args.assume_wow_foreground:
        raise ValueError("live_cannot_assume_foreground")
    if not args.trace:
        raise ValueError("live_requires_trace")


def validate_profile_runtime(args, resolver: ProfileResolver) -> None:
    if (args.live or args.send_input) and not resolver.profile.runnable:
        raise ValueError(f"profile_not_runnable:{resolver.profile.profile_id}:{resolver.profile.runtime_status}")
    if args.send_input and args.dispatch_budget is not None and args.dispatch_budget < 1:
        raise ValueError("send_input_dispatch_budget_invalid")


class SingleFrameSource:
    def __init__(self, frame):
        self.frame = frame

    def read(self):
        return self.frame


class ScreenFrameSource:
    """Decode one protocol-valid screenshot or pixel read at a time.

    TEAP frames carry a commit byte and CRC16.  Those protocol checks are the
    authoritative torn-frame guard.  Runtime sampling therefore does not demand
    two independently read GDI pixel sets to be byte-identical: a GDI pass can
    straddle the AddOn's redraw even when either pass is individually valid.
    Pillow uses one full screenshot per pass; GDI remains an experimental
    backend selected by settings or CLI.
    """

    def __init__(self, layout, sampler=None, stable_attempts: int = 1):
        self.layout = layout
        self.sampler = sampler or runtime_pixel_sampler()
        self.stable_attempts = max(1, int(stable_attempts))

    def read(self):
        last_error = None
        for attempt in range(self.stable_attempts):
            try:
                # decode_rgb_blocks validates RGB redundancy, TEAP commit and
                # CRC16 in one path.  No second pixel-set equality check here.
                return decode_rgb_blocks(self.sampler.sample(self.layout))
            except (ValueError, OSError) as error:
                last_error = error
                if attempt + 1 < self.stable_attempts:
                    time.sleep(0.003)
        raise last_error


def make_sampler(args):
    if args.sampler == "gdi":
        return GDIPixelSampler()
    if args.sampler == "pillow":
        return PillowScreenSampler()
    return runtime_pixel_sampler("pillow")


def make_layout(args):
    if getattr(args, "auto_locate_signal", False):
        return locate_te_signal_layout()
    return SignalLayout(
        x=args.signal_x,
        y=args.signal_y,
        block_size=args.signal_block_size,
        block_gap=args.signal_block_gap,
    )


if __name__ == "__main__":
    raise SystemExit(main())
