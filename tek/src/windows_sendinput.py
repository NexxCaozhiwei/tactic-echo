import ctypes
from ctypes import wintypes

# Use fixed-width Win32 ABI aliases. ctypes.wintypes maps several aliases to
# host C longs on non-Windows test hosts, which can produce an invalid INPUT
# layout and conceal packaging defects.
WORD = ctypes.c_uint16
DWORD = ctypes.c_uint32
LONG = ctypes.c_int32
UINT = ctypes.c_uint32
ULONG_PTR = ctypes.c_size_t

from tek.src.input_planner import DispatchResult, InputPlan, KeyEvent


KEYEVENTF_KEYUP = 0x0002
INPUT_MOUSE = 0
INPUT_KEYBOARD = 1
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800
WHEEL_DELTA = 120
VIRTUAL_KEYS = {
    "CTRL": 0x11,
    "ALT": 0x12,
    "SHIFT": 0x10,
    "WIN": 0x5B,
    "0": 0x30,
    "1": 0x31,
    "2": 0x32,
    "3": 0x33,
    "4": 0x34,
    "5": 0x35,
    "6": 0x36,
    "7": 0x37,
    "8": 0x38,
    "9": 0x39,
    "A": 0x41,
    "B": 0x42,
    "C": 0x43,
    "D": 0x44,
    "E": 0x45,
    "F": 0x46,
    "G": 0x47,
    "H": 0x48,
    "I": 0x49,
    "J": 0x4A,
    "K": 0x4B,
    "L": 0x4C,
    "M": 0x4D,
    "N": 0x4E,
    "O": 0x4F,
    "P": 0x50,
    "Q": 0x51,
    "R": 0x52,
    "S": 0x53,
    "T": 0x54,
    "U": 0x55,
    "V": 0x56,
    "W": 0x57,
    "X": 0x58,
    "Y": 0x59,
    "Z": 0x5A,
    "NUMPAD0": 0x60,
    "NUMPAD1": 0x61,
    "NUMPAD2": 0x62,
    "NUMPAD3": 0x63,
    "NUMPAD4": 0x64,
    "NUMPAD5": 0x65,
    "NUMPAD6": 0x66,
    "NUMPAD7": 0x67,
    "NUMPAD8": 0x68,
    "NUMPAD9": 0x69,
    "F1": 0x70, "F2": 0x71, "F3": 0x72, "F4": 0x73,
    "`": 0xC0,
    "-": 0xBD,
    "=": 0xBB,
}


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", WORD),
        ("wScan", WORD),
        ("dwFlags", DWORD),
        ("time", DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", LONG),
        ("dy", LONG),
        ("mouseData", DWORD),
        ("dwFlags", DWORD),
        ("time", DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", DWORD),
        ("wParamL", WORD),
        ("wParamH", WORD),
    ]


class INPUTUNION(ctypes.Union):
    _fields_ = [
        ("mi", MOUSEINPUT),
        ("ki", KEYBDINPUT),
        ("hi", HARDWAREINPUT),
    ]


class INPUT(ctypes.Structure):
    _fields_ = [("type", DWORD), ("union", INPUTUNION)]


class WindowsSendInputDispatcher:
    backend = "windows_sendinput"

    def __init__(self, user32=None, kernel32=None):
        self.user32 = user32 or ctypes.windll.user32
        self.kernel32 = kernel32 or ctypes.windll.kernel32
        try:
            self.user32.SendInput.argtypes = (UINT, ctypes.POINTER(INPUT), ctypes.c_int)
            self.user32.SendInput.restype = UINT
        except AttributeError:
            pass
        if hasattr(self.kernel32, "GetLastError"):
            try:
                self.kernel32.GetLastError.argtypes = ()
                self.kernel32.GetLastError.restype = DWORD
            except AttributeError:
                pass

    def dispatch(self, plan: InputPlan) -> DispatchResult:
        inputs = (INPUT * len(plan.events))()
        for index, event in enumerate(plan.events):
            if event.event == "wheel":
                delta = WHEEL_DELTA if event.key == "MOUSEWHEELUP" else -WHEEL_DELTA
                inputs[index].type = INPUT_MOUSE
                inputs[index].union.mi = MOUSEINPUT(0, 0, delta & 0xFFFFFFFF, MOUSEEVENTF_WHEEL, 0, 0)
                continue
            if event.key == "BUTTON3":
                inputs[index].type = INPUT_MOUSE
                flag = MOUSEEVENTF_MIDDLEUP if event.event == "up" else MOUSEEVENTF_MIDDLEDOWN
                inputs[index].union.mi = MOUSEINPUT(0, 0, 0, flag, 0, 0)
                continue
            virtual_key = VIRTUAL_KEYS.get(event.key)
            if virtual_key is None:
                return DispatchResult(
                    sent=False,
                    backend=self.backend,
                    reason=f"unsupported_key:{event.key}",
                    events_sent=0,
                )
            inputs[index].type = INPUT_KEYBOARD
            inputs[index].union.ki = KEYBDINPUT(
                wVk=virtual_key,
                wScan=0,
                dwFlags=KEYEVENTF_KEYUP if event.event == "up" else 0,
                time=0,
                dwExtraInfo=0,
            )

        try:
            sent = self.user32.SendInput(len(inputs), inputs, ctypes.sizeof(INPUT))
        except Exception as error:
            return DispatchResult(
                sent=False,
                backend=self.backend,
                reason=f"sendinput_exception:{type(error).__name__}:{error}",
                events_sent=0,
            )
        if sent != len(inputs):
            last_error = self.kernel32.GetLastError() if hasattr(self.kernel32, "GetLastError") else 0
            return DispatchResult(
                sent=False,
                backend=self.backend,
                reason=f"sendinput_partial:{sent}:{len(inputs)}:last_error:{last_error}",
                events_sent=sent,
            )

        return DispatchResult(
            sent=True,
            backend=self.backend,
            reason="input_sent",
            events_sent=sent,
        )

    def release_modifiers(self, plan: InputPlan | None = None) -> DispatchResult:
        events = tuple(KeyEvent(key=key, event="up") for key in ("CTRL", "ALT", "SHIFT", "WIN"))
        return self.dispatch(InputPlan(binding="release_modifiers", events=events))
