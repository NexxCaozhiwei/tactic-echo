import unittest
from tek.src.binding_tokens import encode_binding_token, decode_binding_token, BindingTokenError
from tek.src.teap import encode_fields_v3, decode_fields
from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.engine import TEKEngine
from tek.src.profile_resolver import ProfileResolver
from pathlib import Path
from tek.src.safety_gate import SafetyContext
from tek.src.input_planner import DryRunInputDispatcher

class BindingTokenTests(unittest.TestCase):
    def test_roundtrip_whitelist_keyboard(self):
        token=encode_binding_token('ALT+Q')
        self.assertEqual(decode_binding_token(token).binding, 'ALT+Q')
    def test_roundtrip_shift_digit_and_oem_keys(self):
        for binding in ('SHIFT+1','SHIFT+2','SHIFT+3','SHIFT+4','SHIFT+5','SHIFT+6','SHIFT+7','SHIFT+8','SHIFT+9','SHIFT+0','SHIFT+-','SHIFT+='):
            with self.subTest(binding=binding):
                token=encode_binding_token(binding)
                self.assertEqual(decode_binding_token(token).binding, binding)
        self.assertEqual(decode_binding_token(encode_binding_token('SHIFT--')).binding, 'SHIFT+-')
        self.assertEqual(decode_binding_token(encode_binding_token('SHIFT-EQUALS')).binding, 'SHIFT+=')
    def test_roundtrip_wheel(self):
        token=encode_binding_token('MOUSEWHEELUP')
        self.assertEqual(decode_binding_token(token).input_type, 'wheel')
    def test_rejects_unknown(self):
        with self.assertRaises(BindingTokenError): encode_binding_token('F12')
    def test_v3_decode_and_engine_dynamic_binding(self):
        token=encode_binding_token('Q')
        fields=encode_fields_v3(action_code=1,catalog_fingerprint=RETRIBUTION_V2.fingerprint16,binding_token=token,frame_freshness_counter=2)
        frame=decode_fields(fields)
        self.assertEqual(frame.protocol_version,3)
        engine=TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(Path(__file__).resolve().parents[2] / 'examples' / 'profiles' / 'laptop.json'), input_dispatcher=DryRunInputDispatcher())
        context=SafetyContext(bootstrapped=True,current_session_epoch=frame.session_epoch,last_frame_freshness_counter=1)
        record=engine.process_frame(frame,context)
        self.assertEqual(record.binding,'Q')
        self.assertTrue(record.gatePassed)
