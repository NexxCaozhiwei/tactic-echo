"""TEF development harness; existing TEK engine, hooks and ONE input budget.

Not loaded by WoW; no production TEK modifications or alternate input backend.
"""
import argparse
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--send-input', action='store_true')
    parser.add_argument('--confirm', default='')
    parser.add_argument('--profile', default='examples/profiles/laptop.json')
    parser.add_argument('--trace', default='dist/tef/tek-acceptance.jsonl')
    parser.add_argument('--max-frames',type=int,default=None,help='Optional developer-only bounded run')
    args = parser.parse_args()
    if args.max_frames is not None and args.max_frames<1: parser.error('max-frames must be positive')
    if args.send_input and args.confirm != 'I_UNDERSTAND_TEK_SENDS_KEYS':
        parser.error('real input requires --confirm I_UNDERSTAND_TEK_SENDS_KEYS')
    repo = Path(__file__).resolve().parents[2]
    if not (repo / 'tek/src/engine.py').is_file():
        parser.error('run this developer harness in the TE workspace with existing TEK source')
    sys.path.insert(0, str(repo))
    from tek.src.action_catalog import RETRIBUTION_V2
    from tek.app.worker_controller import AutoLocateFrameSource
    from tek.src.engine import TEKEngine
    from tek.src.keyboard_whitelist import KeyboardInterventionWhitelist, DEFAULT_DISPATCH_EXEMPT_KEYS
    from tek.src.physical_input import PhysicalInputPause, WindowsPhysicalInputMonitor
    from tek.src.profile_resolver import ProfileResolver
    from tek.src.runner import TEKRunner, RunnerConfig
    from tek.src.trace import write_trace
    from tek.src.windows_foreground import WindowsForegroundDetector
    from tek.src.windows_sendinput import WindowsSendInputDispatcher
    resolver = ProfileResolver.from_file(repo / args.profile, catalog=RETRIBUTION_V2)
    if not resolver.profile.runnable:
        parser.error('profile_not_runnable')
    guard = monitor = dispatcher = source = None
    try:
        if args.send_input:
            guard = PhysicalInputPause()
            monitor = WindowsPhysicalInputMonitor(guard, intervention_whitelist=
                KeyboardInterventionWhitelist.from_keys(DEFAULT_DISPATCH_EXEMPT_KEYS))
            if not monitor.start() or not monitor.wait_until_ready(timeout_seconds=.75) or monitor.health_reason():
                raise RuntimeError('physical_input_hook_unavailable')
            dispatcher = WindowsSendInputDispatcher()
        # Same lazy client-relative locator used by TEK.exe. Construction does
        # not require WoW foreground; read retries with the existing backoff.
        source = AutoLocateFrameSource(sampler_backend='pillow',background_relocation=True)
        engine = TEKEngine(RETRIBUTION_V2, resolver, input_dispatcher=dispatcher,
            physical_input_guard=guard, physical_input_monitor=monitor)
        runner = TEKRunner(engine, source, foreground_source=WindowsForegroundDetector())
        config = RunnerConfig(interval_seconds=.05, dispatch_budget=1 if args.send_input else None,
            require_start_toggle=args.send_input, expected_protocol_version=3)
        trace = repo / args.trace
        trace.parent.mkdir(parents=True, exist_ok=True)
        print('TEF acceptance: real input budget=1' if args.send_input else 'TEF acceptance: DRY RUN',flush=True)
        print('Waiting for WoW foreground and TEF signal. Press Ctrl+C together to stop.',flush=True)
        import time
        last_reason=None
        frames=0
        while True:
            record = runner.tick(config)
            write_trace(record, trace, max_bytes=5_000_000)
            if record.reason!=last_reason:
                print('TEK: '+record.reason,flush=True);last_reason=record.reason
            if record.inputSent:
                print('One input sent; stopping. Confirm game receipt separately.')
                break
            frames+=1
            if args.max_frames is not None and frames>=args.max_frames: break
            time.sleep(runner.next_interval_seconds(config, record))
    except KeyboardInterrupt:
        print('Stopped by user.')
    finally:
        try:
            if source and callable(getattr(source, 'close', None)):
                source.close()
        finally:
            try:
                if dispatcher:
                    dispatcher.release_modifiers()
            finally:
                if monitor and not monitor.stop():
                    raise RuntimeError('physical_input_hook_stopping')


if __name__ == '__main__':
    main()
