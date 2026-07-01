from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class P56TeapV3AutoLocateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.sampler = (ROOT / "tek" / "src" / "screen_sampler.py").read_text(encoding="utf-8")
        self.worker = (ROOT / "tek" / "app" / "worker_controller.py").read_text(encoding="utf-8")
        self.window = (ROOT / "tek" / "app" / "status_window.py").read_text(encoding="utf-8")

    def test_addon_keeps_v3_payload_but_uses_client_top_left_physical_geometry(self) -> None:
        self.assertIn('local CLIENT_ANCHOR_MARGIN_PX = 8', self.signal)
        self.assertIn('local MIN_BLOCK_SIZE_PX = 8', self.signal)
        self.assertIn('UIParent:GetEffectiveScale()', self.signal)
        self.assertIn('frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", anchorMargin, -anchorMargin)', self.signal)
        self.assertIn('function SignalFrame:GetGeometry()', self.signal)
        self.assertNotIn('frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -12)', self.signal)
        # The protocol encoder is deliberately untouched by this layout-only revision.
        encoder = (ADDON / "Signal" / "SignalEncoder.lua").read_text(encoding="utf-8")
        self.assertIn('protocolVersion = 3', encoder)
        self.assertIn('local fields = {\n        84,\n        69,\n        self.protocolVersion,', encoder)
        self.assertIn('self:GetStateCode(message.state)', encoder)

    def test_tek_uses_bounded_te3_header_location_and_zero_gap_safe_sampling(self) -> None:
        for marker in (
            '_HEADER_VALUES: tuple[int, int] = (84, 69)',
            'TEAP v3 header: [T=84][E=69][Version=3][State]',
            'MAX_HEADER_SEARCH_WIDTH = 960',
            'MAX_HEADER_SEARCH_HEIGHT = 240',
            'gap == 0',
            '_sample_radius(block_size: int)',
            'return 2 if int(block_size) >= 8 else 1',
        ):
            self.assertIn(marker, self.sampler)
        self.assertNotIn('fallback to the full client', self.sampler)

    def test_candidate_layout_requires_two_complete_freshness_advancing_frames(self) -> None:
        for marker in (
            'layout_verification_frames: int = 2',
            'max(2, int(layout_verification_frames))',
            'te_signal_layout_verification_freshness_stalled',
            'candidate_header_located',
            'cached_layout_pending_proof',
            'bounded_top_left_te_v3_header',
            'client_locate_function=locate_te_signal_layout_progressive_in_region',
        ):
            self.assertIn(marker, self.worker)
        self.assertIn('Automatic operation has no absolute-coordinate fallback', self.worker)
        self.assertIn('te_signal_layout_search_backoff', self.worker)

    def test_connection_ui_describes_background_auto_location_not_manual_calibration(self) -> None:
        self.assertIn('后台自动定位 TEAP（固定客户区左上）', self.window)
        self.assertIn('无需切出 WoW 手动校准', self.window)
        self.assertNotIn('text="校准色块"', self.window)
        self.assertIn('手动固定布局 X / Y（仅关闭自动定位时使用）', self.window)


if __name__ == "__main__":
    unittest.main()
