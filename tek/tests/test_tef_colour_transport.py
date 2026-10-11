import unittest
from PIL import Image, ImageDraw
from tek.src.teap import encode_fields_v3, TEAPError
from tek.src.visual_decoder import RGB, protocol_colour, decode_rgb_blocks, _gamma_fields, VisualDecodeError
from tek.src.screen_sampler import locate_te_signal_layout_from_image


class TEFColourTransportTests(unittest.TestCase):
    def test_every_byte_complementary_pair_is_unique(self):
        self.assertEqual(_gamma_fields(tuple(protocol_colour(v,1.2) for v in range(256)),1.2),list(range(256)))

    def test_identity_and_gamma_te_and_tef_frames(self):
        for action,token in ((1,0),(0,5),(0,197)):
            values=encode_fields_v3(state="armed",action_code=action,binding_token=token,sequence=7723,frame_freshness_counter=7723)
            for gamma in (1.0,1.2):
                frame=decode_rgb_blocks(tuple(protocol_colour(v,gamma) for v in values))
                self.assertEqual(frame.raw_fields,tuple(values))

    def test_gamma_locator_with_gap_and_without_gap(self):
        values=encode_fields_v3(state="waiting",sequence=7723,frame_freshness_counter=7723,observation_only=True)
        for gamma in (1.0,1.2):
            for gap in (0,2):
                im=Image.new("RGB",(640,100)); draw=ImageDraw.Draw(im)
                for i,v in enumerate(values):
                    c=protocol_colour(v,gamma); x=24+i*(24+gap)
                    draw.rectangle((x,24,x+23,47),fill=(c.red,c.green,c.blue))
                layout=locate_te_signal_layout_from_image(im,search_width=640)
                self.assertEqual((layout.x,layout.y,layout.block_size,layout.block_gap),(24,24,24,gap))

    def test_corruption_and_unsupported_gamma_fail_closed(self):
        values=encode_fields_v3(action_code=1,sequence=2)
        blocks=list(protocol_colour(v,1.2) for v in values)
        blocks[10]=protocol_colour(9,1.2)
        with self.assertRaises(TEAPError): decode_rgb_blocks(blocks)
        blocks=list(protocol_colour(v,1.2) for v in values); blocks[4]=RGB(40,40,27)
        with self.assertRaises(VisualDecodeError): decode_rgb_blocks(blocks)
        with self.assertRaises((VisualDecodeError,TEAPError)):
            decode_rgb_blocks(tuple(protocol_colour(v,1.5) for v in values))

    def test_live_capture_fixture_crc(self):
        pairs=[(101,183),(86,196),(6,252),(0,255),(40,231),(0,255),(58,219),(43,230),(58,219),(43,230),(0,255),(0,255),(0,255),(0,255),(0,255),(0,255),(4,253),(32,237),(81,200),(177,107)]
        frame=decode_rgb_blocks(tuple(RGB(r,g,27) for r,g in pairs))
        self.assertEqual(frame.session_epoch,28); self.assertEqual(frame.sequence,7723)
        self.assertTrue(frame.observation_only); self.assertEqual(frame.binding_token,0)

    def test_live_quantization_ties_require_unique_crc(self):
        pairs=[(101,183),(86,196),(6,252),(0,255),(42,230),(0,255),(249,13),(4,253),(249,13),(4,253),(0,255),(0,255),(0,255),(0,255),(0,255),(0,255),(4,253),(246,19),(50,224),(177,107)]
        frame=decode_rgb_blocks(tuple(RGB(r,g,27) for r,g in pairs))
        self.assertEqual(frame.session_epoch,29); self.assertEqual(frame.sequence,760)
        self.assertTrue(frame.observation_only)

    def test_excessive_quantization_ambiguity_rejected(self):
        values=encode_fields_v3(action_code=1,sequence=2)
        blocks=list(protocol_colour(v,1.2) for v in values)
        for i in range(4,12): blocks[i]=RGB(42,230,27)
        with self.assertRaisesRegex(VisualDecodeError,"ambiguity_limit"):
            decode_rgb_blocks(blocks)


if __name__ == "__main__": unittest.main()
