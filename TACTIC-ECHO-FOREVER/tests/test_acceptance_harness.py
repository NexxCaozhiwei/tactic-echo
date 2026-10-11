import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
from unittest.mock import patch, MagicMock

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent))
spec=importlib.util.spec_from_file_location('tef_acceptance',ROOT/'scripts/tek_acceptance.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class HarnessTests(unittest.TestCase):
    def test_real_assembly_has_hook_budget_foreground_and_cleanup(self):
        patches={
            'tek.src.profile_resolver.ProfileResolver.from_file': MagicMock(return_value=SimpleNamespace(profile=SimpleNamespace(runnable=True))),
            'tek.app.worker_controller.AutoLocateFrameSource': MagicMock(),
            'tek.src.physical_input.WindowsPhysicalInputMonitor': MagicMock(),
            'tek.src.physical_input.PhysicalInputPause': MagicMock(),
            'tek.src.windows_sendinput.WindowsSendInputDispatcher': MagicMock(),
            'tek.src.windows_foreground.WindowsForegroundDetector': MagicMock(),
            'tek.src.engine.TEKEngine': MagicMock(),
            'tek.src.runner.TEKRunner': MagicMock(),
            'tek.src.trace.write_trace': MagicMock(),
        }
        monitor=patches['tek.src.physical_input.WindowsPhysicalInputMonitor'].return_value
        monitor.start.return_value=True;monitor.wait_until_ready.return_value=True;monitor.health_reason.return_value=None
        runner=patches['tek.src.runner.TEKRunner'].return_value
        runner.tick.side_effect=[SimpleNamespace(inputSent=False,reason="wow_not_foreground"),
            SimpleNamespace(inputSent=False,reason="te_signal_layout_not_found"),
            SimpleNamespace(inputSent=True,reason="dispatched")]
        runner.next_interval_seconds.return_value=0
        from contextlib import ExitStack
        with ExitStack() as stack:
            for name,mock in patches.items():stack.enter_context(patch(name,mock))
            stack.enter_context(patch.object(sys,'argv',['test','--send-input','--confirm','I_UNDERSTAND_TEK_SENDS_KEYS']))
            module.main()
        config=runner.tick.call_args.args[0]
        self.assertEqual(config.dispatch_budget,1);self.assertTrue(config.require_start_toggle)
        self.assertFalse(config.assume_wow_foreground)
        monitor.start.assert_called_once();monitor.stop.assert_called_once()
        patches['tek.src.windows_sendinput.WindowsSendInputDispatcher'].return_value.release_modifiers.assert_called_once()
        engine=patches['tek.src.engine.TEKEngine'].call_args.kwargs
        self.assertIs(engine['physical_input_monitor'],monitor)
        self.assertIsNotNone(engine['physical_input_guard'])
        self.assertEqual(runner.tick.call_count,3)

    def test_real_requires_explicit_literal(self):
        with patch.object(sys,'argv',['test','--send-input']),self.assertRaises(SystemExit):module.main()

if __name__=='__main__':unittest.main()
