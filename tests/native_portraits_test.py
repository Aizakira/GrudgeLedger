"""Exercise the actual WoW marker encoder and Windows decoder together."""
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

from lupa.lua51 import LuaRuntime
from PIL import Image

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root/"tools"))
import native_portraits_windows as native
from sync_portraits import lua, write_atomic

vm = LuaRuntime(unpack_returned_tuples=True)
vm.execute("""
GrudgeLedger, GrudgeLedgerNativePortraits, cells = {}, {}, {}
local widget = {}
widget.__index = function(self,k) return widget[k] end
function widget:SetPoint(_,parent,_,x,y) self.x,self.y=x,y end
function widget:SetColorTexture(v) if self.layer=="OVERLAY" then cells[-self.y*64+self.x]=v end end
function widget:CreateTexture(_,layer) return setmetatable({layer=layer},widget) end
for _,k in ipairs({"SetFrameStrata","Hide","Show","SetAllPoints","SetSize","SetScale","SetTexture"}) do widget[k]=function() end end
function CreateFrame() return setmetatable({},widget) end
UIParent={GetHeight=function() return 768 end}
GetPhysicalScreenSize=function() return 4096,2160 end
GetTime=function() return 40 end
C_Timer={After=function(_,fn) nextFrame=fn end}
UnitGUID=function() return current end
SetPortraitTexture=function() end
""")
vm.execute((root/"GrudgeLedger/NativePortrait.lua").read_text("utf8"))
def tile(guid,color):
    vm.globals().current=guid
    vm.globals().GrudgeLedger.QueueNativePortrait("target",guid)
    image=Image.new("RGB",(64,80))
    for coord,value in vm.globals().cells.items():
        y,x=divmod(coord,64)
        image.paste((int(value)*255,)*3,(x,y,x+2,y+2))
    face=Image.linear_gradient("L").resize((64,64)).point(lambda v:v//2+color).convert("RGB")
    image.paste(face,(0,16))
    vm.globals().nextFrame()
    return image

one,two="Player-6842-0098E113","Player-1234567890-000000000000000A"
first,second=tile(one,10),tile(two,100)
assert native.decode(first)==one and native.decode(second)==two
broken=first.copy()
broken.putpixel((63,15),(120,120,120))
assert native.decode(broken) is None
with tempfile.TemporaryDirectory() as tmp:
    folder=Path(tmp)
    black=first.copy()
    black.paste((0,0,0),(0,16,64,80))
    # A single frame, a damaged tag and a blank portrait must never claim the slot.
    with patch.object(native,"window_tile",return_value=[first,broken,black,black]),patch.object(native.time,"sleep"):
        native.watch(folder,folder,write_atomic,lua)
    assert not list(folder.glob("*.tga"))
    with patch.object(native,"window_tile",return_value=[first,first,second,second]),patch.object(native.time,"sleep"):
        native.watch(folder,folder,write_atomic,lua)
    for guid,image in ((one,first),(two,second)):
        with Image.open(folder/(guid+"-native.tga")) as saved:
            assert saved.tobytes()==image.crop((0,16,64,80)).tobytes()
    dest=folder/(one+"-native.tga")
    before=dest.read_bytes()
    changed=first.copy()
    changed.paste(second.crop((0,16,64,80)),(0,16))
    with patch.object(native,"window_tile",return_value=[changed,changed]),patch.object(native.time,"sleep"):
        native.watch(folder,folder,write_atomic,lua)
    assert dest.read_bytes()==before
    vm.execute((folder/"NativePortraits.lua").read_text())
    assert vm.globals().GrudgeLedgerNativePortraits[one] and vm.globals().GrudgeLedgerNativePortraits[two]
print("PASS native capture, identity, persistence and first portrait preservation")
