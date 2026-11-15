"""Save the portrait tile emitted by Forever; never replace a saved native face."""
import ctypes as C
from ctypes import wintypes as W
import io
import re
import time
from pathlib import Path

from PIL import Image


def decode(image):
    data = bytearray()
    for y in range(1, 16, 2):
        byte = 0
        for x in range(1, 64, 2):
            rgb = image.getpixel((x, y))
            if min(rgb) > 180:
                bit = 1
            elif max(rgb) < 65:
                bit = 0
            else:
                return
            byte = byte * 2 + bit
            if x % 16 == 15:
                data.append(byte)
                byte = 0
    if data[:4] != b"GLP1" or sum(i*b for i,b in enumerate(data[:-1], 1)) % 251 != data[-1]:
        return
    tail = data[4:-1].rstrip(b"\0")
    if re.fullmatch(rb"[0-9]{1,10}-[0-9A-Fa-f]{1,16}", tail):
        return "Player-" + tail.decode("ascii")


def window_tile(game):
    user, gdi, kernel = C.windll.user32, C.windll.gdi32, C.windll.kernel32
    # Windows handles are pointer-sized, including on 64-bit Python.
    for fn in (user.GetForegroundWindow,user.GetDC,gdi.CreateCompatibleDC,gdi.CreateDIBSection,
               gdi.SelectObject,kernel.OpenProcess):
        fn.restype = W.HANDLE
    try:
        user.SetThreadDpiAwarenessContext(C.c_void_p(-4))
    except AttributeError:
        pass
    accepted = None
    while True:
        hwnd = W.HWND(user.GetForegroundWindow())
        if not hwnd.value:
            yield None
            continue
        pid = W.DWORD()
        user.GetWindowThreadProcessId(hwnd, C.byref(pid))
        key = (hwnd.value, pid.value)
        if key != accepted:
            process = W.HANDLE(kernel.OpenProcess(0x1000, False, pid))
            if not process:
                yield None
                continue
            path, length = C.create_unicode_buffer(32768), W.DWORD(32768)
            try:
                ok = kernel.QueryFullProcessImageNameW(process, 0, path, C.byref(length))
            finally:
                kernel.CloseHandle(process)
            if not ok or Path(path.value) != game / "Wow.exe":
                yield None
                continue
            accepted = key
        pos = W.POINT()
        if not user.ClientToScreen(hwnd, C.byref(pos)):
            yield None
            continue
        screen = W.HDC(user.GetDC(None))
        image = None
        try:
            # First two bits of ASCII G are black then white. Avoid copying idle frames.
            dark = gdi.GetPixel(screen,pos.x+1,pos.y+1)
            light = gdi.GetPixel(screen,pos.x+3,pos.y+1)
            if dark >= 0 and light >= 0 and all((dark >> shift) & 255 < 65 and
                    (light >> shift) & 255 > 180 for shift in (0,8,16)):
                dc = W.HDC(gdi.CreateCompatibleDC(screen))
                bits = C.c_void_p()
                header = (W.DWORD*10)(40,64,2**32-80,0x200001,0,0,0,0,0,0)
                bitmap = W.HANDLE(gdi.CreateDIBSection(screen,C.byref(header),0,C.byref(bits),None,0))
                old = W.HANDLE(gdi.SelectObject(dc,bitmap)) if dc and bitmap else None
                try:
                    if old and bits and gdi.BitBlt(dc,0,0,64,80,screen,pos.x,pos.y,0x00CC0020):
                        gdi.GdiFlush()
                        image = Image.frombytes("RGB",(64,80),C.string_at(bits,64*80*4),"raw","BGRX")
                finally:
                    if old: gdi.SelectObject(dc,old)
                    if bitmap: gdi.DeleteObject(bitmap)
                    if dc: gdi.DeleteDC(dc)
        finally:
            user.ReleaseDC(None,screen)
        yield image if user.GetForegroundWindow() == hwnd.value else None


def native_guids(folder):
    saved = {}
    for path in folder.glob("Player-*-native.tga"):
        guid = path.name.removesuffix("-native.tga")
        if re.fullmatch(r"Player-[0-9]{1,10}-[0-9A-Fa-f]{1,16}", guid):
            try:
                with Image.open(path) as image:
                    if image.format == "TGA" and image.size == (64,64):
                        image.load()
                        saved[guid] = True
            except (ValueError, OSError):
                continue
    return saved


def watch(game, folder, write_atomic, lua):
    saved = native_guids(folder)
    def publish():
        write_atomic(folder/"NativePortraits.lua", ("GrudgeLedgerNativePortraits = "+lua(saved)+"\n").encode())
    publish()
    previous = None
    for image in window_tile(game):
        try:
            guid = decode(image) if image is not None else None
            if guid and previous == guid:
                dest = folder/(guid+"-native.tga")
                if guid not in saved:
                    face = image.crop((0,16,64,80))
                    if len(face.resize((16,16)).getcolors(256) or []) >= 16:
                        data = io.BytesIO()
                        face.save(data,format="TGA")
                        write_atomic(dest,data.getvalue())
                        saved[guid] = True
                        try:
                            publish()
                        except OSError:
                            del saved[guid]
                            raise
            previous = guid
        except OSError:
            previous = None
        time.sleep(.25)
