from __future__ import annotations

import ctypes
import os
from ctypes import wintypes
from dataclasses import dataclass
from functools import lru_cache

from tek.src.teap import TEAPError
from tek.src.visual_decoder import RGB, VisualDecodeError, decode_rgb_blocks
from tek.src.windows_display import virtual_desktop_bounds


@dataclass(frozen=True)
class CaptureBounds:
    """Screen-global rectangle used for one coherent Pillow capture."""

    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return max(0, self.right - self.left)

    @property
    def height(self) -> int:
        return max(0, self.bottom - self.top)

    def to_dict(self) -> dict:
        return {
            "left": self.left,
            "top": self.top,
            "right": self.right,
            "bottom": self.bottom,
            "width": self.width,
            "height": self.height,
        }


@dataclass(frozen=True)
class SignalLayout:
    # Fixed-client-anchor default: TEAP is drawn at the WoW client top-left
    # with an 8 physical-pixel safety inset.  Auto-locate mode never treats
    # this value as a trusted desktop fallback; it is retained only for
    # explicit fixed-layout / development callers.
    x: int = 8
    y: int = 8
    block_size: int = 10
    block_gap: int = 2
    block_count: int = 20

    @property
    def strip_width(self) -> int:
        return self.block_count * self.block_size + max(0, self.block_count - 1) * self.block_gap

    @property
    def strip_height(self) -> int:
        return self.block_size

    def strip_bounds(self, *, padding: int = 0) -> CaptureBounds:
        return _cached_strip_bounds(self, max(0, int(padding)))

    def sample_points(self) -> tuple[tuple[int, int], ...]:
        return _cached_sample_points(self)

    @classmethod
    def from_dict(cls, data: dict | None) -> "SignalLayout | None":
        if not isinstance(data, dict):
            return None
        try:
            layout = cls(
                x=int(data.get("x")),
                y=int(data.get("y")),
                block_size=int(data.get("block_size")),
                block_gap=int(data.get("block_gap", 0)),
                block_count=int(data.get("block_count", 20)),
            )
        except (TypeError, ValueError):
            return None
        if layout.block_size < 4 or layout.block_size > 128 or layout.block_gap < 0 or layout.block_gap > 64:
            return None
        if layout.block_count != 20:
            return None
        return layout

    def to_dict(self) -> dict:
        return {
            "x": self.x,
            "y": self.y,
            "block_size": self.block_size,
            "block_gap": self.block_gap,
            "block_count": self.block_count,
        }


@lru_cache(maxsize=1024)
def _cached_strip_bounds(layout: SignalLayout, padding: int) -> CaptureBounds:
    return CaptureBounds(
        left=layout.x - padding,
        top=layout.y - padding,
        right=layout.x + layout.strip_width + padding,
        bottom=layout.y + layout.strip_height + padding,
    )


@lru_cache(maxsize=1024)
def _cached_sample_points(layout: SignalLayout) -> tuple[tuple[int, int], ...]:
    center_offset = layout.block_size // 2
    return tuple(
        (layout.x + index * (layout.block_size + layout.block_gap) + center_offset, layout.y + center_offset)
        for index in range(layout.block_count)
    )


@dataclass(frozen=True)
class RelativeSignalLayout:
    """TEAP geometry expressed relative to one WoW client area.

    The object is intentionally runtime-only. Pixel coordinates remain useful
    as a fallback, while these ratios let the hot path translate a proven strip
    when the same WoW client moves or changes size without re-scanning the
    desktop.
    """

    x_ratio: float
    y_ratio: float
    block_size_ratio: float
    block_gap_ratio: float
    block_count: int
    baseline_client_width: int
    baseline_client_height: int

    @classmethod
    def from_layout(
        cls,
        layout: SignalLayout,
        *,
        client_left: int,
        client_top: int,
        client_width: int,
        client_height: int,
    ) -> "RelativeSignalLayout | None":
        width = int(client_width)
        height = int(client_height)
        if width <= 0 or height <= 0:
            return None
        # WoW UI scale is normally tied to client height.  Retaining the
        # baseline width/height also makes the diagnostic explicit when P2-B
        # needs to fall back to client-area re-location after a major mode
        # change.
        return cls(
            x_ratio=(int(layout.x) - int(client_left)) / width,
            y_ratio=(int(layout.y) - int(client_top)) / height,
            block_size_ratio=int(layout.block_size) / height,
            block_gap_ratio=int(layout.block_gap) / height,
            block_count=int(layout.block_count),
            baseline_client_width=width,
            baseline_client_height=height,
        )

    def project(
        self,
        *,
        client_left: int,
        client_top: int,
        client_width: int,
        client_height: int,
    ) -> SignalLayout | None:
        width = int(client_width)
        height = int(client_height)
        if width <= 0 or height <= 0:
            return None
        block_size = max(4, int(round(self.block_size_ratio * height)))
        block_gap = max(0, int(round(self.block_gap_ratio * height)))
        return SignalLayout(
            x=int(client_left) + int(round(self.x_ratio * width)),
            y=int(client_top) + int(round(self.y_ratio * height)),
            block_size=block_size,
            block_gap=block_gap,
            block_count=max(1, int(self.block_count)),
        )

    @classmethod
    def from_dict(cls, data: dict | None) -> "RelativeSignalLayout | None":
        if not isinstance(data, dict):
            return None
        try:
            result = cls(
                x_ratio=float(data.get("x_ratio")),
                y_ratio=float(data.get("y_ratio")),
                block_size_ratio=float(data.get("block_size_ratio")),
                block_gap_ratio=float(data.get("block_gap_ratio")),
                block_count=int(data.get("block_count", 20)),
                baseline_client_width=int(data.get("baseline_client_width")),
                baseline_client_height=int(data.get("baseline_client_height")),
            )
        except (TypeError, ValueError):
            return None
        values = (result.x_ratio, result.y_ratio, result.block_size_ratio, result.block_gap_ratio)
        if any(value != value or abs(value) > 10.0 for value in values):
            return None
        if result.block_count != 20 or result.baseline_client_width <= 0 or result.baseline_client_height <= 0:
            return None
        if result.block_size_ratio <= 0 or result.block_size_ratio > 0.25 or result.block_gap_ratio < 0 or result.block_gap_ratio > 0.25:
            return None
        return result

    def to_dict(self) -> dict:
        return {
            "x_ratio": self.x_ratio,
            "y_ratio": self.y_ratio,
            "block_size_ratio": self.block_size_ratio,
            "block_gap_ratio": self.block_gap_ratio,
            "block_count": self.block_count,
            "baseline_client_width": self.baseline_client_width,
            "baseline_client_height": self.baseline_client_height,
        }


class GDIPixelSampler:
    backend = "gdi"
    capture_mode = "pixel_reads"

    def __init__(self):
        self.user32 = ctypes.windll.user32
        self.gdi32 = ctypes.windll.gdi32

    def sample(self, layout: SignalLayout = SignalLayout()) -> tuple[RGB, ...]:
        desktop_dc = self.user32.GetDC(0)
        if not desktop_dc:
            raise OSError("getdc_failed")
        try:
            radius = _sample_radius(layout.block_size)
            return tuple(
                _median_rgb(
                    self._get_pixel(desktop_dc, sample_x + dx, sample_y + dy)
                    for dy in range(-radius, radius + 1)
                    for dx in range(-radius, radius + 1)
                )
                for sample_x, sample_y in layout.sample_points()
            )
        finally:
            self.user32.ReleaseDC(0, desktop_dc)

    def _get_pixel(self, dc, x: int, y: int) -> RGB:
        color = self.gdi32.GetPixel(dc, x, y)
        if color == -1:
            raise OSError(f"getpixel_failed:{x}:{y}")
        red = color & 0xFF
        green = (color >> 8) & 0xFF
        blue = (color >> 16) & 0xFF
        return RGB(red=red, green=green, blue=blue)


class _BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", ctypes.c_ulong),
        ("biWidth", ctypes.c_long),
        ("biHeight", ctypes.c_long),
        ("biPlanes", ctypes.c_ushort),
        ("biBitCount", ctypes.c_ushort),
        ("biCompression", ctypes.c_ulong),
        ("biSizeImage", ctypes.c_ulong),
        ("biXPelsPerMeter", ctypes.c_long),
        ("biYPelsPerMeter", ctypes.c_long),
        ("biClrUsed", ctypes.c_ulong),
        ("biClrImportant", ctypes.c_ulong),
    ]


class _RGBQUAD(ctypes.Structure):
    _fields_ = [
        ("rgbBlue", ctypes.c_ubyte),
        ("rgbGreen", ctypes.c_ubyte),
        ("rgbRed", ctypes.c_ubyte),
        ("rgbReserved", ctypes.c_ubyte),
    ]


class _BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", _BITMAPINFOHEADER), ("bmiColors", _RGBQUAD * 1)]


class GDIBlitStripSampler:
    """Capture one TEAP strip through one desktop BitBlt operation.

    Unlike ``GDIPixelSampler`` this obtains all twenty samples from one copied
    bitmap, preventing per-pixel API overhead and reducing torn-frame exposure.
    It is selected by Auto mode only after Pillow has validated live TEAP reads.
    """

    backend = "gdi_blt"
    capture_mode = "strip_blt"
    _SRCCOPY = 0x00CC0020
    _DIB_RGB_COLORS = 0
    _BI_RGB = 0

    def __init__(self):
        if os.name != "nt":
            raise OSError("gdi_blt_windows_only")
        self.user32 = ctypes.windll.user32
        self.gdi32 = ctypes.windll.gdi32
        self._configure_winapi_signatures()
        self._last_capture_bounds: CaptureBounds | None = None

    def _configure_winapi_signatures(self) -> None:
        """Avoid 64-bit handle truncation in ctypes' default ``c_int`` ABI."""
        hdc = wintypes.HANDLE
        hobj = wintypes.HANDLE
        self.user32.GetDC.argtypes = [wintypes.HWND]
        self.user32.GetDC.restype = hdc
        self.user32.ReleaseDC.argtypes = [wintypes.HWND, hdc]
        self.user32.ReleaseDC.restype = ctypes.c_int
        self.gdi32.CreateCompatibleDC.argtypes = [hdc]
        self.gdi32.CreateCompatibleDC.restype = hdc
        self.gdi32.DeleteDC.argtypes = [hdc]
        self.gdi32.DeleteDC.restype = wintypes.BOOL
        self.gdi32.CreateCompatibleBitmap.argtypes = [hdc, ctypes.c_int, ctypes.c_int]
        self.gdi32.CreateCompatibleBitmap.restype = hobj
        self.gdi32.SelectObject.argtypes = [hdc, hobj]
        self.gdi32.SelectObject.restype = hobj
        self.gdi32.DeleteObject.argtypes = [hobj]
        self.gdi32.DeleteObject.restype = wintypes.BOOL
        self.gdi32.BitBlt.argtypes = [
            hdc, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            hdc, ctypes.c_int, ctypes.c_int, wintypes.DWORD,
        ]
        self.gdi32.BitBlt.restype = wintypes.BOOL
        self.gdi32.GetDIBits.argtypes = [
            hdc, hobj, wintypes.UINT, wintypes.UINT, ctypes.c_void_p,
            ctypes.POINTER(_BITMAPINFO), wintypes.UINT,
        ]
        self.gdi32.GetDIBits.restype = ctypes.c_int

    @property
    def last_capture_bounds(self) -> CaptureBounds | None:
        return self._last_capture_bounds

    def sample(self, layout: SignalLayout = SignalLayout()) -> tuple[RGB, ...]:
        bounds = layout.strip_bounds()
        if bounds.width <= 0 or bounds.height <= 0:
            raise OSError("invalid_capture_bounds")
        desktop_dc = self.user32.GetDC(0)
        if not desktop_dc:
            raise OSError("getdc_failed")
        memory_dc = 0
        bitmap = 0
        previous = 0
        try:
            memory_dc = self.gdi32.CreateCompatibleDC(desktop_dc)
            if not memory_dc:
                raise OSError("create_compatible_dc_failed")
            bitmap = self.gdi32.CreateCompatibleBitmap(desktop_dc, bounds.width, bounds.height)
            if not bitmap:
                raise OSError("create_compatible_bitmap_failed")
            previous = self.gdi32.SelectObject(memory_dc, bitmap)
            if not self.gdi32.BitBlt(
                memory_dc,
                0,
                0,
                bounds.width,
                bounds.height,
                desktop_dc,
                bounds.left,
                bounds.top,
                self._SRCCOPY,
            ):
                raise OSError("bitblt_failed")

            info = _BITMAPINFO()
            info.bmiHeader.biSize = ctypes.sizeof(_BITMAPINFOHEADER)
            info.bmiHeader.biWidth = bounds.width
            # A negative height yields top-down rows, matching screen coords.
            info.bmiHeader.biHeight = -bounds.height
            info.bmiHeader.biPlanes = 1
            info.bmiHeader.biBitCount = 32
            info.bmiHeader.biCompression = self._BI_RGB
            raw = (ctypes.c_ubyte * (bounds.width * bounds.height * 4))()
            copied = self.gdi32.GetDIBits(
                memory_dc,
                bitmap,
                0,
                bounds.height,
                ctypes.cast(raw, ctypes.c_void_p),
                ctypes.byref(info),
                self._DIB_RGB_COLORS,
            )
            if int(copied or 0) != bounds.height:
                raise OSError("getdibits_failed")
            self._last_capture_bounds = bounds
            radius = _sample_radius(layout.block_size)

            def read_local(local_x: int, local_y: int) -> RGB:
                if local_x < 0 or local_y < 0 or local_x >= bounds.width or local_y >= bounds.height:
                    raise OSError(f"sample_outside_capture_bounds:{local_x}:{local_y}")
                offset = (local_y * bounds.width + local_x) * 4
                return RGB(
                    red=int(raw[offset + 2]),
                    green=int(raw[offset + 1]),
                    blue=int(raw[offset]),
                )

            pixels: list[RGB] = []
            for x, y in layout.sample_points():
                local_x = x - bounds.left
                local_y = y - bounds.top
                pixels.append(_median_rgb(
                    read_local(local_x + dx, local_y + dy)
                    for dy in range(-radius, radius + 1)
                    for dx in range(-radius, radius + 1)
                ))
            return tuple(pixels)
        finally:
            if memory_dc and previous:
                try:
                    self.gdi32.SelectObject(memory_dc, previous)
                except Exception:
                    pass
            if bitmap:
                try:
                    self.gdi32.DeleteObject(bitmap)
                except Exception:
                    pass
            if memory_dc:
                try:
                    self.gdi32.DeleteDC(memory_dc)
                except Exception:
                    pass
            self.user32.ReleaseDC(0, desktop_dc)


class PillowScreenSampler:
    """Pillow sampler that captures only the TEAP strip during runtime reads.

    ``ImageGrab.grab(all_screens=True)`` used to copy the full virtual desktop
    every 50 ms even though TEK reads twenty pixels.  Runtime sampling now asks
    Pillow for one tight rectangle covering the verified strip.  Full-client
    captures remain available only to initial locate/re-locate/calibration.
    """

    backend = "pillow"
    capture_mode = "strip"

    def __init__(self, *, all_screens: bool = True, bounds_provider=virtual_desktop_bounds):
        self.all_screens = all_screens
        self.bounds_provider = bounds_provider
        self._last_capture_bounds: CaptureBounds | None = None

    @property
    def last_capture_bounds(self) -> CaptureBounds | None:
        return self._last_capture_bounds

    def _grab_virtual_desktop(self):
        """Compatibility helper used only by legacy callers/full scans."""
        bounds = self.bounds_provider()
        if self.all_screens:
            try:
                from PIL import ImageGrab

                image = ImageGrab.grab(all_screens=True)
                return image, bounds.left, bounds.top
            except (TypeError, OSError):
                if bounds.width > 0 and bounds.height > 0:
                    from PIL import ImageGrab

                    image = ImageGrab.grab(bbox=(bounds.left, bounds.top, bounds.right, bounds.bottom))
                    return image, bounds.left, bounds.top
        from PIL import ImageGrab

        image = ImageGrab.grab()
        return image, 0, 0

    def capture_region(self, bounds: CaptureBounds):
        """Capture one exact screen-global rectangle and return its origin."""
        if bounds.width <= 0 or bounds.height <= 0:
            raise OSError("invalid_capture_bounds")
        from PIL import ImageGrab

        bbox = (bounds.left, bounds.top, bounds.right, bounds.bottom)
        try:
            if self.all_screens:
                image = ImageGrab.grab(bbox=bbox, all_screens=True)
            else:
                image = ImageGrab.grab(bbox=bbox)
        except TypeError:
            # Older Pillow builds accept bbox but not all_screens.
            image = ImageGrab.grab(bbox=bbox)
        self._last_capture_bounds = bounds
        return image, bounds.left, bounds.top

    def sample(self, layout: SignalLayout = SignalLayout()) -> tuple[RGB, ...]:
        # One strip capture keeps all twenty blocks inside the same source image
        # while avoiding full-virtual-desktop allocation on every runtime tick.
        bounds = layout.strip_bounds()
        image, origin_x, origin_y = self.capture_region(bounds)
        return _sample_layout_from_image(
            image,
            SignalLayout(
                x=layout.x - origin_x,
                y=layout.y - origin_y,
                block_size=layout.block_size,
                block_gap=layout.block_gap,
                block_count=layout.block_count,
            ),
        )

    def _get_pixel(self, image, x: int, y: int) -> RGB:
        if x < 0 or y < 0 or x >= image.size[0] or y >= image.size[1]:
            raise OSError(f"sample_outside_capture_bounds:{x}:{y}")
        red, green, blue = image.getpixel((x, y))[:3]
        return RGB(red=red, green=green, blue=blue)


def runtime_pixel_sampler(backend: str = "pillow"):
    """Return a runtime sampler selected by an explicit backend preference."""
    requested = str(backend or "pillow").strip().lower()
    if requested == "auto":
        requested = "pillow"
    if requested == "gdi" and os.name == "nt":
        try:
            return GDIPixelSampler()
        except (AttributeError, OSError):
            pass
    if requested == "gdi_blt" and os.name == "nt":
        try:
            return GDIBlitStripSampler()
        except (AttributeError, OSError):
            pass
    # Auto starts with Pillow; AutoLocateFrameSource promotes it only after
    # several independently valid TEAP reads.
    return PillowScreenSampler()


# TEAP v3 header: [T=84][E=69][Version=3][State].  The first three
# fields are intentionally stable and sufficient to recover strip geometry;
# State remains a decoded protocol field and is verified only after the entire
# frame passes the ordinary CRC/commit checks.
_HEADER_VALUES: tuple[int, int] = (84, 69)
# The stable T/E magic bytes are far apart from ordinary small state/version
# values, so a wider discovery tolerance is safe here.  Version=3 is sampled
# only at the geometry-derived third cell, avoiding an ambiguous global search
# where State values 0..7 resemble byte 3.
_HEADER_SEARCH_TOLERANCE = 10
_HEADER_VERSION_TOLERANCE = 2
_MIN_HEADER_BLOCK_SIZE = 4
_MAX_HEADER_BLOCK_SIZE = 64
_MAX_HEADER_PITCH = 128


@dataclass(frozen=True)
class _ColorRect:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return self.right - self.left + 1

    @property
    def height(self) -> int:
        return self.bottom - self.top + 1

    @property
    def center_x(self) -> float:
        return (self.left + self.right) / 2.0

    @property
    def center_y(self) -> float:
        return (self.top + self.bottom) / 2.0


def locate_te_signal_layout_from_image(
    image,
    *,
    search_width: int | None = 360,
    search_height: int | None = 96,
    origin_x: int = 0,
    origin_y: int = 0,
) -> SignalLayout:
    """Recover a TEAP v3 layout from the fixed ``T / E / 3`` header.

    The previous locator first required twenty separately visible colour runs,
    which breaks when UI scaling collapses a physical gap to zero pixels.  This
    locator only discovers the stable first three v3 fields, derives pitch and
    geometry, then uses the existing full 20-byte RGB/CRC/commit decoder as the
    authority for accepting a candidate.  A header match alone never grants a
    dispatch-capable layout.
    """
    width, height = image.size
    max_x = min(width, search_width if search_width is not None else width)
    max_y = min(height, search_height if search_height is not None else height)
    if max_x <= 0 or max_y <= 0:
        raise OSError("te_signal_layout_not_found")

    rectangles = {
        value: _find_colour_rectangles(image, value, max_x=max_x, max_y=max_y)
        for value in _HEADER_VALUES
    }
    for candidate in _header_layout_candidates(image, rectangles):
        try:
            blocks = _sample_layout_from_image(image, candidate)
            decode_rgb_blocks(blocks)
        except (VisualDecodeError, TEAPError, IndexError, OSError):
            continue
        return SignalLayout(
            x=candidate.x + origin_x,
            y=candidate.y + origin_y,
            block_size=candidate.block_size,
            block_gap=candidate.block_gap,
            block_count=candidate.block_count,
        )
    raise OSError("te_signal_layout_not_found")


def locate_te_signal_layout_in_region(bounds: CaptureBounds, *, sampler: PillowScreenSampler | None = None) -> SignalLayout:
    """Locate TEAP inside one caller-supplied WoW client sub-region only."""
    capture = sampler or PillowScreenSampler()
    image, origin_x, origin_y = capture.capture_region(bounds)
    return locate_te_signal_layout_from_image(
        image,
        search_width=None,
        search_height=None,
        origin_x=origin_x,
        origin_y=origin_y,
    )


DEFAULT_PROGRESSIVE_LOCATE_STAGES: tuple[tuple[int, int], ...] = (
    (360, 96),
    (640, 160),
)
MAX_HEADER_SEARCH_WIDTH = 960
MAX_HEADER_SEARCH_HEIGHT = 240


def progressive_client_search_bounds(
    client_bounds: CaptureBounds,
    *,
    stages: tuple[tuple[int, int], ...] = DEFAULT_PROGRESSIVE_LOCATE_STAGES,
) -> tuple[CaptureBounds, ...]:
    """Return bounded top-left header search regions for the current WoW client.

    TEAP's protocol anchor is fixed near the client top-left.  The final stage
    expands only to an adaptive cap of ``960 × 240`` pixels; it deliberately
    never scans the full WoW client or the desktop.  This keeps fullscreen and
    small-window recovery background-safe and avoids visual false positives.
    """
    max_width = min(client_bounds.width, MAX_HEADER_SEARCH_WIDTH)
    max_height = min(client_bounds.height, MAX_HEADER_SEARCH_HEIGHT)
    requested = list(stages)
    requested.append((max_width, max_height))

    regions: list[CaptureBounds] = []
    seen: set[tuple[int, int, int, int]] = set()
    for width, height in requested:
        region = CaptureBounds(
            client_bounds.left,
            client_bounds.top,
            client_bounds.left + min(max_width, max(1, int(width))),
            client_bounds.top + min(max_height, max(1, int(height))),
        )
        key = (region.left, region.top, region.right, region.bottom)
        if region.width > 0 and region.height > 0 and key not in seen:
            regions.append(region)
            seen.add(key)
    return tuple(regions)


def locate_te_signal_layout_progressive_in_region(
    bounds: CaptureBounds,
    *,
    sampler: PillowScreenSampler | None = None,
    stages: tuple[tuple[int, int], ...] = DEFAULT_PROGRESSIVE_LOCATE_STAGES,
) -> SignalLayout:
    """Locate v3's ``T / E / 3`` header in bounded top-left client regions."""
    last_error: Exception | None = None
    capture = sampler or PillowScreenSampler()
    for region in progressive_client_search_bounds(bounds, stages=stages):
        try:
            return locate_te_signal_layout_in_region(region, sampler=capture)
        except OSError as error:
            last_error = error
    if last_error is not None:
        raise last_error
    raise OSError("te_signal_layout_not_found")


def locate_te_signal_layout(*, search_width: int | None = None, search_height: int | None = None) -> SignalLayout:
    """Legacy full-desktop locator retained only for explicit CLI callers."""
    sampler = PillowScreenSampler()
    image, origin_x, origin_y = sampler._grab_virtual_desktop()
    return locate_te_signal_layout_from_image(
        image,
        search_width=search_width,
        search_height=search_height,
        origin_x=origin_x,
        origin_y=origin_y,
    )


def _header_layout_candidates(image, rectangles: dict[int, tuple[_ColorRect, ...]]):
    """Yield geometry candidates from compatible T, E and derived Version=3.

    State is encoded immediately after Version and may be any byte 0..7.  A
    broad global component search for byte 3 would merge with nearby state
    colours at small RGB tolerances.  We instead recover pitch from T/E, then
    inspect only the derived third-cell centre for the v3 byte.
    """
    t_rectangles = rectangles.get(84, ())
    e_rectangles = rectangles.get(69, ())
    for t_rect in t_rectangles:
        for e_rect in e_rectangles:
            pitch = e_rect.center_x - t_rect.center_x
            if pitch <= 0 or pitch > _MAX_HEADER_PITCH:
                continue
            if not _rectangles_compatible(t_rect, e_rect, pitch):
                continue
            block_size = _median_int([
                t_rect.width, t_rect.height,
                e_rect.width, e_rect.height,
            ])
            if block_size < _MIN_HEADER_BLOCK_SIZE or block_size > _MAX_HEADER_BLOCK_SIZE:
                continue
            pitch_pixels = max(block_size, int(round(pitch)))
            block_gap = max(0, pitch_pixels - block_size)
            layout = SignalLayout(
                x=t_rect.left,
                y=_median_int([t_rect.top, e_rect.top]),
                block_size=block_size,
                block_gap=block_gap,
                block_count=20,
            )
            try:
                version = _sample_layout_block(image, layout, 2)
            except OSError:
                continue
            if _matches_protocol_value(version, 3, tolerance=_HEADER_VERSION_TOLERANCE):
                yield layout


def _rectangles_compatible(first: _ColorRect, second: _ColorRect, pitch: float) -> bool:
    if not _dimension_compatible(first.width, second.width):
        return False
    if not _dimension_compatible(first.height, second.height):
        return False
    vertical_tolerance = max(2.0, min(first.height, second.height) * 0.40)
    if abs(first.center_y - second.center_y) > vertical_tolerance:
        return False
    overlap = min(first.bottom, second.bottom) - max(first.top, second.top) + 1
    if overlap < max(2, int(round(min(first.height, second.height) * 0.60))):
        return False
    return pitch >= max(first.width, second.width) - 1


def _dimension_compatible(first: int, second: int) -> bool:
    larger = max(first, second)
    smaller = min(first, second)
    return smaller >= _MIN_HEADER_BLOCK_SIZE and larger <= max(smaller + 2, int(round(smaller * 1.50)))


def _find_colour_rectangles(image, value: int, *, max_x: int, max_y: int) -> tuple[_ColorRect, ...]:
    """Return connected, colour-specific rectangles for one header byte.

    Components are located per exact header value rather than with the old
    generic TE-colour run.  Adjacent blocks with ``gap == 0`` remain distinct
    because their byte values and therefore RGB colours differ.
    """
    width, height = image.size
    scan_width = min(width, max_x)
    scan_height = min(height, max_y)
    pixels = image.load()
    seen = bytearray(scan_width * scan_height)
    matches: list[_ColorRect] = []

    def pixel_matches(x: int, y: int) -> bool:
        red, green, blue = pixels[x, y][:3]
        return (
            abs(int(red) - value) <= _HEADER_SEARCH_TOLERANCE
            and abs(int(green) - (255 - value)) <= _HEADER_SEARCH_TOLERANCE
            and abs(int(blue) - 17) <= _HEADER_SEARCH_TOLERANCE
        )

    for start_y in range(scan_height):
        row_offset = start_y * scan_width
        for start_x in range(scan_width):
            start_index = row_offset + start_x
            if seen[start_index] or not pixel_matches(start_x, start_y):
                continue
            seen[start_index] = 1
            stack = [(start_x, start_y)]
            left = right = start_x
            top = bottom = start_y
            area = 0
            while stack:
                x, y = stack.pop()
                area += 1
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if nx < 0 or ny < 0 or nx >= scan_width or ny >= scan_height:
                        continue
                    index = ny * scan_width + nx
                    if seen[index] or not pixel_matches(nx, ny):
                        continue
                    seen[index] = 1
                    stack.append((nx, ny))
            rect = _ColorRect(left, top, right, bottom)
            # Ignore scattered UI pixels: a candidate header block must carry
            # enough solid area to support centre-region sampling.
            if (
                rect.width >= _MIN_HEADER_BLOCK_SIZE
                and rect.height >= _MIN_HEADER_BLOCK_SIZE
                and area >= int(rect.width * rect.height * 0.70)
            ):
                matches.append(rect)
    return tuple(matches)


def _matches_protocol_value(block: RGB, value: int, *, tolerance: int) -> bool:
    return (
        abs(int(block.red) - value) <= tolerance
        and abs(int(block.green) - (255 - value)) <= tolerance
        and abs(int(block.blue) - 17) <= tolerance
    )


def _sample_layout_block(image, layout: SignalLayout, index: int) -> RGB:
    if index < 0 or index >= layout.block_count:
        raise OSError(f"sample_block_out_of_range:{index}")
    center_x, center_y = layout.sample_points()[index]
    radius = _sample_radius(layout.block_size)
    pixels = image.load()
    width, height = image.size
    samples: list[RGB] = []
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            x = center_x + dx
            y = center_y + dy
            if x < 0 or y < 0 or x >= width or y >= height:
                raise OSError(f"sample_outside_capture_bounds:{x}:{y}")
            red, green, blue = pixels[x, y][:3]
            samples.append(RGB(red=int(red), green=int(green), blue=int(blue)))
    return _median_rgb(samples)


def _sample_layout_from_image(image, layout: SignalLayout) -> tuple[RGB, ...]:
    return tuple(_sample_layout_block(image, layout, index) for index in range(layout.block_count))


def _sample_radius(block_size: int) -> int:
    # 3×3 sampling for compact but valid blocks; 5×5 once there is enough
    # interior area.  This samples the same small, central region across all
    # backends and is safe even when visual block gaps shrink to zero.
    return 2 if int(block_size) >= 8 else 1


def _median_rgb(samples) -> RGB:
    values = tuple(samples)
    if not values:
        raise OSError("empty_pixel_sample")
    return RGB(
        red=_median_int([sample.red for sample in values]),
        green=_median_int([sample.green for sample in values]),
        blue=_median_int([sample.blue for sample in values]),
    )


def _median_int(values: list[int]) -> int:
    if not values:
        raise ValueError("median_requires_values")
    ordered = sorted(int(value) for value in values)
    return int(ordered[len(ordered) // 2])
