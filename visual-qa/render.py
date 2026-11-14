"""Offline approximation of actual Lua-native UI geometry, never a game screenshot.

Loads the real addon files in Lua5.1 and captures SetPoint/size/font/color/texture
calls. Run native_art.py once for matching Classic texture references. Optional
extracted FRIZQT__.TTF, ARIALN.TTF and MORPHEUS.TTF can be placed in
renders/native/Fonts or supplied with GRUDGE_LEDGER_QA_FONTS. All rendering is
offline, with no desktop, client or SavedVariables access.
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
from pathlib import Path
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont, ImageChops
from native_art import CACHE, PATHS

BASE = Path(__file__).resolve().parent
WORK = BASE.parent
ADDON = WORK / "GrudgeLedger"
sys.path.insert(0, str(WORK / "test-runtime"))
from lupa.lua51 import LuaRuntime

FONTS = Path("C:/Windows/Fonts")
LOCALE = os.environ.get("GRUDGE_LEDGER_QA_LOCALE", "frFR")
OUT = BASE / "renders" if LOCALE == "frFR" else BASE / "renders" / LOCALE
OUT.mkdir(exist_ok=True, parents=True)
POINTS = {"TOPLEFT": (0, 0), "TOP": (.5, 0), "TOPRIGHT": (1, 0),
          "LEFT": (0, .5), "CENTER": (.5, .5), "RIGHT": (1, .5),
          "BOTTOMLEFT": (0, 1), "BOTTOM": (.5, 1), "BOTTOMRIGHT": (1, 1)}


def fontsize(obj):
    obj = str(obj or "")
    fancy = re.search(r"Fancy(\d+)Font", obj)
    if fancy: return int(fancy.group(1))
    if obj == "QuestFont_Large": return 15
    if "Huge" in obj: return 20
    if "Large" in obj: return 16
    if "Small" in obj: return 10
    return 12


@lru_cache(maxsize=100)
def font(size, face=None):
    return ImageFont.truetype(str(font_path(face)), max(1, size))


@lru_cache(maxsize=32)
def font_path(face):
    name = (face or "").replace("\\", "/").rsplit("/", 1)[-1].lower()
    if name.startswith("ptserif-"):
        return ADDON / "Media" / "Fonts" / face.replace("\\", "/").rsplit("/", 1)[-1]
    candidates = {"frizqt__.ttf": ("FRIZQT__.TTF", "georgia.ttf"),
                  "morpheus.ttf": ("MORPHEUS.TTF", "georgia.ttf"),
                  "arialn.ttf": ("ARIALN.TTF", "arial.ttf")}
    if name in candidates:
        actual, substitute = candidates[name]
        for folder in (os.environ.get("GRUDGE_LEDGER_QA_FONTS"), CACHE / "Fonts", FONTS):
            if folder and (Path(folder) / actual).is_file():
                return Path(folder) / actual
        return FONTS / substitute
    return FONTS / "arial.ttf"


def plaintext(value):
    text = str(value or "").replace("||", "\x01")
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text).replace("\x01", "|")


def wrap(text, width, size, face=None, wordwrap=True):
    f = font(size, face)
    result = []
    for para in plaintext(text).split("\n"):
        if not wordwrap or width <= 0:
            result.append(para)
            continue
        line = ""
        for word in para.split(" "):
            candidate = (line + " " + word) if line else word
            if line and f.getlength(candidate) > width:
                result.append(line)
                line = word
            else: line = candidate
        result.append(line)
    return result or [""]


def textheight(text, width, size, spacing=0, face=None):
    count = len(wrap(text, width, size, face))
    return count * (size + 2) + max(0, count - 1) * spacing


def convert(value):
    if hasattr(value, "items"):
        data = dict(value.items())
        if data and all(isinstance(k, int) for k in data) and sorted(data) == list(range(1, len(data) + 1)):
            return [convert(data[i]) for i in range(1, len(data) + 1)]
        return {str(k): convert(v) for k, v in data.items()}
    return value


class Layout:
    def __init__(self, frames):
        self.frames = {r["id"]: r for r in frames}
        self.bounds = {}
        self.resolving = set()

    def scale(self, n):
        r = self.frames[n]
        return r.get("scale", 1) * (self.scale(r["parent"]) if r.get("parent") else 1)

    def alpha(self, n):
        r = self.frames[n]
        return r.get("alpha", 1) * (self.alpha(r["parent"]) if r.get("parent") and not r.get("ignoreParentAlpha") else 1)

    def visible(self, n):
        r = self.frames[n]
        if r.get("buttonState") in ("pushed", "highlight") or r.get("layer") == "HIGHLIGHT": return False
        if r.get("buttonState") == "normal" and not self.frames[r["parent"]].get("enabled", True) and self.frames[r["parent"]].get("hasDisabledTexture"): return False
        if r.get("buttonState") == "disabled" and self.frames[r["parent"]].get("enabled",True): return False
        return r.get("shown", True) and (self.visible(r["parent"]) if r.get("parent") else True)

    def descendant(self, n, ancestor):
        return n == ancestor or (bool(self.frames[n].get("parent")) and self.descendant(self.frames[n]["parent"], ancestor))

    def framelevel(self, n):
        r = self.frames[n]
        if r.get("level") is not None: return r["level"]
        if r.get("parent"): return self.framelevel(r["parent"]) + (0 if r["kind"] in ("Texture", "FontString", "Mask") else 1)
        return 0

    def resolve(self, n):
        if n in self.bounds: return self.bounds[n]
        r = self.frames[n]
        if n in self.resolving: return (0, 0, r.get("width", 0), r.get("height", 0))
        self.resolving.add(n)
        scale = self.scale(n)
        size = r.get("fontSize") or fontsize(r.get("fontObject") or r.get("template"))
        w = r.get("width")
        h = r.get("height")
        if w is None:
            w = font(size, r.get("font")).getlength(plaintext(r.get("text"))) if r.get("text") else 0
        if h is None: h = size + 2 if r["kind"] == "FontString" else 0
        w, h = w * scale, h * scale
        parent = r.get("parent")
        pb = self.resolve(parent) if parent else (0, 0, w, h)
        anchors = r.get("anchors") or []
        if isinstance(anchors, dict): anchors = list(anchors.values())
        equations = [[], []]
        for a in anchors:
            ref = self.resolve(a.get("relative") or parent) if a.get("relative") or parent else pb
            own, rel = POINTS[a["point"]], POINTS[a["relativePoint"]]
            equations[0].append((own[0], ref[0] + rel[0] * ref[2] + a["x"] * scale))
            equations[1].append((own[1], ref[1] + rel[1] * ref[3] - a["y"] * scale))
        def solve(eq, length, default):
            for a in eq:
                for b in eq:
                    if a[0] != b[0]:
                        length = (b[1] - a[1]) / (b[0] - a[0])
                        return a[1] - a[0] * length, max(0, length)
            return ((eq[0][1] - eq[0][0] * length) if eq else default), length
        x, w = solve(equations[0], w, pb[0])
        if r["kind"] == "FontString" and r.get("height") is None:
            lines = wrap(r.get("text"), w / max(scale, .01), size, r.get("font"), wordwrap=r.get("wordWrap", True))
            if r.get("maxLines"): lines = lines[:int(r["maxLines"])]
            h = (len(lines) * (size + 2) + max(0, len(lines) - 1) * r.get("spacing", 0)) * scale
        y, h = solve(equations[1], h, pb[1])
        if parent and self.frames[parent].get("scrollChild") == n:
            y -= self.frames[parent].get("vertical", 0) * scale
        result = (x, y, w, h)
        self.resolving.remove(n)
        self.bounds[n] = result
        return result

    def clip(self, n, root):
        rb = self.resolve(root)
        clip = (rb[0], rb[1], rb[0] + rb[2], rb[1] + rb[3])
        parent = self.frames[n].get("parent")
        while parent:
            r = self.frames[parent]
            if r["kind"] == "ScrollFrame":
                x, y, w, h = self.resolve(parent)
                clip = (max(clip[0], x), max(clip[1], y), min(clip[2], x + w), min(clip[3], y + h))
            parent = r.get("parent")
        return clip


def color(value, alpha=1, fallback=(1, 1, 1, 1)):
    value = value or fallback
    if isinstance(value, dict): value = list(value.values())
    value = list(value)
    value += [1] * (4 - len(value))
    return tuple(round(max(0, min(1, v)) * 255) for v in value[:3]) + (round(max(0, min(1, value[3] * alpha)) * 255),)


@lru_cache(maxsize=96)
def actual_texture(path):
    if not path: return None
    parts = path.replace("\\", "/").split("/")
    if "GrudgeLedger" in parts:
        p = ADDON.joinpath(*parts[parts.index("GrudgeLedger") + 1:])
        if not p.suffix: p = p.with_suffix(".tga")
        if p.is_file(): return Image.open(p).convert("RGBA")
    native = PATHS.get("/".join(parts).lower())
    if native and native.is_file(): return Image.open(native).convert("RGBA")
    return None


def draw_native_icon(draw, box, path, fill):
    x, y, x2, y2 = box
    cx, cy, rad = (x + x2) / 2, (y + y2) / 2, max(1, min(x2 - x, y2 - y) / 2 - 2)
    if "QuestionMark" in (path or ""):
        draw.rounded_rectangle(box, radius=2, fill=(33,28,23,255), outline=(122,98,65,255))
        draw.text((cx,cy), "?", anchor="mm", font=font(max(7,rad*1.6)), fill=(215,188,135,255))
    elif "Shield" in (path or ""):
        draw.polygon([(cx-rad,cy-rad),(cx+rad,cy-rad),(cx+rad*.8,cy+rad*.4),(cx,cy+rad),(cx-rad*.8,cy+rad*.4)], fill=fill, outline=(225,210,155,255))
    elif "Skull" in (path or ""):
        draw.ellipse((cx-rad,cy-rad,cx+rad,cy+rad*.6), fill=fill)
        draw.rectangle((cx-rad*.5,cy,cx+rad*.5,cy+rad), fill=fill)
        for dx in [-.4,.4]: draw.ellipse((cx+dx*rad-rad*.2,cy-rad*.3,cx+dx*rad+rad*.2,cy+rad*.1),fill=(20,15,15,255))
    elif "Alert" in (path or ""):
        draw.polygon([(cx,cy-rad),(cx+rad,cy+rad),(cx-rad,cy+rad)], fill=fill)
        draw.line((cx,cy-rad*.4,cx,cy+rad*.35), fill=(20,15,15,255), width=max(1,round(rad*.15)))
    elif "TrackingBorder" in (path or "") or "Border" in (path or ""):
        draw.ellipse(box, outline=(151,113,55,255), width=max(1,round(rad*.12)))


def render(name, frames, root):
    lay = Layout(frames)
    rb = lay.resolve(root)
    margin, banner = 22, 34
    # Minimap controls may deliberately extend beyond the map disc.
    if name.startswith("minimap"): margin = 48
    transparent = name == "journal-transparent"
    canvas = Image.new("RGBA", (math.ceil(rb[2] + margin*2), math.ceil(rb[3] + margin*2 + banner)), (0,0,0,0) if transparent else (20,21,23,255))
    offsetx, offsety = margin - rb[0], margin + banner - rb[1]
    heading = ImageDraw.Draw(canvas)
    if not transparent:
        heading.text((12,10), "SIMULATION HORS JEU  /  " + name.upper(), font=font(11), fill=(183,174,155,255))
    layers = {"BACKGROUND":0,"BORDER":1,"ARTWORK":2,"OVERLAY":3,"HIGHLIGHT":4}
    minimap_button = next((r["id"] for r in frames if r.get("name") == "GrudgeLedgerMinimapButton"), None)
    regions = [r for r in frames if (lay.descendant(r["id"], root) or
        (name.startswith("minimap") and minimap_button and lay.descendant(r["id"], minimap_button))) and lay.visible(r["id"])]
    regions.sort(key=lambda r: (lay.framelevel(r["id"]) + (.5 if r["kind"] == "EditBox" else 0), layers.get(r.get("layer"), -1), r.get("sublevel",0), r["id"]))
    issues = []
    for r in regions:
        x, y, w, h = lay.resolve(r["id"])
        if w <= 0 or h <= 0 or r["kind"] == "Mask": continue
        x, y = x + offsetx, y + offsety
        layer = Image.new("RGBA", canvas.size)
        draw = ImageDraw.Draw(layer)
        box = (round(x), round(y), round(x+w), round(y+h))
        alpha = lay.alpha(r["id"])
        if r.get("color") is not None: draw.rectangle(box, fill=color(r["color"], alpha))
        if r["kind"] == "Minimap":
            draw.ellipse(box, fill=(43,51,43,255), outline=(144,115,66,255), width=4)
            draw.line((x+w*.2,y+h*.72,x+w*.8,y+h*.25),fill=(85,90,65,255),width=12)
            draw.text((x+w*.46,y+h*.04),"N",font=font(12),fill=(235,211,143,255))
            draw.ellipse((x+w*.47,y+h*.47,x+w*.53,y+h*.53),fill=(221,202,115,255))
        texture_name = r.get("texture") or ""
        missing_paper = (name == "journal-no-paper" and any(asset in texture_name for asset in ("JournalPaper", "JournalBookSurface"))) or (name == "journal-no-book" and "JournalBookSurface" in texture_name)
        tex = None if missing_paper else actual_texture(r.get("texture"))
        if tex:
            coords = r.get("texCoord")
            if coords and len(coords) == 4:
                left, right, top, bottom = coords
                tex = tex.crop((round(left*tex.width), round(top*tex.height), round(right*tex.width), round(bottom*tex.height)))
            tex = tex.resize((max(1,round(w)),max(1,round(h))), Image.Resampling.LANCZOS)
            tex = ImageChops.multiply(tex, Image.new("RGBA", tex.size, color(r.get("tint"), alpha)))
            if r.get("mask"):
                native_mask = actual_texture(r["mask"])
                if native_mask:
                    mask = native_mask.getchannel("A").resize(tex.size, Image.Resampling.LANCZOS)
                else:
                    mask = Image.new("L", tex.size, 0)
                    ImageDraw.Draw(mask).ellipse((0,0,tex.width,tex.height), fill=255)
                tex.putalpha(ImageChops.multiply(tex.getchannel("A"), mask))
            layer.alpha_composite(tex, (round(x),round(y)))
        elif not missing_paper and r.get("texture") and r["kind"] == "Texture":
            draw_native_icon(draw, box, r["texture"], color(r.get("tint"),alpha))
        if r.get("template") == "UIPanelButtonTemplate":
            draw.rounded_rectangle(box,radius=3,fill=(70,35,32,255),outline=(122,98,65,255))
        if r["kind"] == "EditBox" and r.get("template") == "InputBoxTemplate":
            draw.rectangle(box,fill=(15,14,13,255),outline=(96,78,55,255))
        if r["kind"] == "CheckButton":
            cb=(round(x+4),round(y+4),round(x+w-4),round(y+h-4))
            draw.rectangle(cb, fill=(20,18,16,255),outline=(131,108,66,255))
            if r.get("checked"): draw.line([(x+7,y+h*.55),(x+w*.45,y+h-7),(x+w-5,y+6)],fill=(226,190,98,255),width=2)
        if r.get("text") and not r.get("fontString"):
            region_scale = lay.scale(r["id"])
            size = (r.get("fontSize") or fontsize(r.get("fontObject") or r.get("template"))) * region_scale
            face = r.get("font")
            f = font(size/region_scale,face)
            inset = r.get("insets") or [0,0,0,0]
            if isinstance(inset,dict): inset=list(inset.values())
            ix,ir,it,ib = (list(inset)+[0]*4)[:4]
            if r["kind"] == "EditBox" and r.get("template"): ix += 7; ir += 7
            ix,ir,it,ib = (v * region_scale for v in (ix,ir,it,ib))
            textw = max(1,w-ix-ir)
            wrapping = r.get("wordWrap", r["kind"] == "FontString" or r["kind"] == "EditBox")
            # Layout wraps in UI units, before scale; scaled glyph hinting must not reflow it.
            lines = wrap(r["text"],textw/region_scale,size/region_scale,face,wrapping)
            line_height, spacing = size + 2*region_scale, r.get("spacing",0)*region_scale
            natural = len(lines)*line_height + max(0,len(lines)-1)*spacing
            all_lines = lines
            if r.get("maxLines"): lines=lines[:int(r["maxLines"])]
            just = r.get("justifyH") or ("CENTER" if r["kind"] == "Button" else "LEFT")
            ty = y+it
            if r["kind"] in ("Button", "EditBox") and r.get("justifyV") != "TOP" and natural <= h-it-ib: ty += (h-it-ib-natural)/2
            elif r.get("justifyV") == "MIDDLE": ty += (h-natural)/2
            textlayer = Image.new("RGBA", (math.ceil(canvas.width/region_scale), math.ceil(canvas.height/region_scale)))
            td = ImageDraw.Draw(textlayer)
            rgba=color(r.get("textColor"), alpha, fallback=(.91,.86,.74,1))
            owner = lay.frames.get(r.get("parent"), {})
            if not r.get("textColor") and (not r.get("enabled",True) or (owner.get("kind") == "Button" and not owner.get("enabled",True))):
                rgba=(110,105,96,round(alpha*255))
            for line in lines:
                if not wrapping or r.get("maxLines"):
                    truncated = f.getlength(line)*region_scale > textw or (line == lines[-1] and len(all_lines)>len(lines))
                    if truncated:
                        while line and f.getlength(line + "…")*region_scale > textw: line=line[:-1]
                        line += "…"
                tx=x+ix
                if just == "CENTER": tx += (textw-f.getlength(line)*region_scale)/2
                elif just == "RIGHT": tx += textw-f.getlength(line)*region_scale
                linecolor = rgba
                for hexcolor, phrase in re.findall(r"(?<!\|)\|c([0-9a-fA-F]{8})(.*?)\|r",r["text"]):
                    if phrase and phrase in line:
                        linecolor=tuple(int(hexcolor[k:k+2],16) for k in (2,4,6))+(int(hexcolor[:2],16),)
                        break
                if r.get("shadow") and r.get("shadowOffset"):
                    dx, dy = r["shadowOffset"]
                    td.text((tx/region_scale+dx,ty/region_scale-dy),line,font=f,fill=color(r["shadow"],alpha),anchor="lt")
                td.text((tx/region_scale,ty/region_scale),line,font=f,fill=linecolor,anchor="lt")
                ty += line_height+spacing
            if region_scale != 1:
                textlayer = textlayer.resize(canvas.size, Image.Resampling.LANCZOS)
            rect=(max(0,round(x)),max(0,round(y)),min(canvas.width,round(x+w)),min(canvas.height,round(y+h)))
            if rect[2]>rect[0] and rect[3]>rect[1]: layer.alpha_composite(textlayer.crop(rect),(rect[0],rect[1]))
            if natural > h+3 and not r.get("maxLines") and r["kind"] == "FontString":
                issues.append({"kind":"text_height", "id":r["id"], "text":r["text"][:110], "natural":round(natural,1),"available":round(h,1)})
        clip = lay.clip(r["id"],root)
        if name.startswith("minimap"): clip=(rb[0]-40,rb[1]-40,rb[0]+rb[2]+40,rb[1]+rb[3]+40)
        clip = (max(0,round(clip[0]+offsetx)),max(0,round(clip[1]+offsety)),min(canvas.width,round(clip[2]+offsetx)),min(canvas.height,round(clip[3]+offsety)))
        if clip[2]>clip[0] and clip[3]>clip[1]: canvas.alpha_composite(layer.crop(clip),(clip[0],clip[1]))
        if r["id"] != root and not name.startswith("minimap"):
            scroll_ancestor=False; p=r.get("parent")
            while p:
                scroll_ancestor |= lay.frames[p]["kind"]=="ScrollFrame"
                p=lay.frames[p].get("parent")
            xx,yy,ww,hh=lay.resolve(r["id"])
            if not scroll_ancestor and (xx<rb[0]-4 or yy<rb[1]-4 or xx+ww>rb[0]+rb[2]+4 or yy+hh>rb[1]+rb[3]+4):
                issues.append({"kind":"outside_window","id":r["id"],"text":r.get("text","")[:100],"bounds":[xx-rb[0],yy-rb[1],ww,hh]})
            if r["kind"] == "FontString" and r.get("parent") and lay.frames[r["parent"]]["kind"] == "Button":
                px,py,pw,ph=lay.resolve(r["parent"])
                if yy+hh>py+ph+2:
                    issues.append({"kind":"text_outside_button","id":r["id"],"text":r.get("text","")[:100],"bottom":yy+hh-py,"button_height":ph})
    # True sibling controls overlapping is a deterministic geometry problem.
    controls=[r for r in regions if r["kind"] in ("Button","EditBox","CheckButton") and r["id"]!=root]
    for i,a in enumerate(controls):
        ax,ay,aw,ah=lay.resolve(a["id"])
        for b in controls[i+1:]:
            if a.get("parent") != b.get("parent"): continue
            bx,by,bw,bh=lay.resolve(b["id"])
            if min(ax+aw,bx+bw)-max(ax,bx)>2 and min(ay+ah,by+bh)-max(ay,by)>2:
                issues.append({"kind":"control_overlap","ids":[a["id"],b["id"]],"text":[a.get("text"),b.get("text")]})
    # A native template scrollbar is not present in the mock tree: approximate its
    # track/thumb from the actual ScrollFrame viewport and child dimensions.
    sd=ImageDraw.Draw(canvas)
    for r in regions:
        if r["kind"]=="ScrollFrame" and r.get("scrollChild"):
            x,y,w,h=lay.resolve(r["id"]);_,_,_,ch=lay.resolve(r["scrollChild"])
            if ch>h+1:
                x,y=x+offsetx+w+8,y+offsety
                sd.rounded_rectangle((x,y,x+5,y+h),radius=2,fill=(46,37,29,255))
                th=max(18,h*h/ch);top=y+min(h-th,r.get("vertical",0)/max(1,ch-h)*(h-th))
                sd.rounded_rectangle((x,top,x+5,top+th),radius=2,fill=(129,98,51,255))
    if transparent:
        left, top, right, bottom = margin, margin+banner, margin+round(rb[2]), margin+banner+round(rb[3])
        alpha = canvas.getchannel("A")
        for box in ((0,0,canvas.width,top), (0,bottom,canvas.width,canvas.height), (0,top,left,bottom), (right,top,canvas.width,bottom)):
            assert alpha.crop(box).getextrema()[1] == 0, "journal has a rectangular shadow outside the book"
        for point in ((left,top), (right-1,top), (left,bottom-1), (right-1,bottom-1)):
            assert alpha.getpixel(point) <= 3, "journal backing covers a transparent artwork corner"
        canvas.crop((left,top,right,bottom)).save(OUT/(name+".png"))
        # A light checkerboard exposes dark halos that a dark preview would hide.
        checker = Image.new("RGBA", canvas.size, (190,190,182,255))
        draw = ImageDraw.Draw(checker)
        for y in range(0,canvas.height,16):
            for x in range(0,canvas.width,16):
                if (x//16+y//16)%2: draw.rectangle((x,y,x+15,y+15), fill=(221,221,213,255))
        checker.alpha_composite(canvas)
        canvas = checker
        heading = ImageDraw.Draw(canvas)
        heading.text((12,10), "SIMULATION HORS JEU  /  TRANSPARENCE", font=font(11), fill=(50,50,45,255))
        canvas.convert("RGB").save(OUT/(name+"-checker.png"))
    else:
        canvas.convert("RGB").save(OUT/(name+".png"))
    return issues, canvas.convert("RGB")


def main():
    lua=LuaRuntime(unpack_returned_tuples=True)
    g=lua.globals();g.TEST_ROOT=ADDON.as_posix();g.TEST_WORK=WORK.as_posix()
    g.GetLocale=lambda: LOCALE
    g.QA_FontSize=fontsize
    g.QA_TextHeight=textheight
    g.QA_TextWidth=lambda text,size,face=None: font(size,face).getlength(plaintext(text))
    g.QA_TextLines=lambda text,width,size,face=None: len(wrap(text,width,size,face))
    lua.execute((BASE/"capture.lua").read_text(encoding="utf-8"))
    views=["statistics", "statistics-small", "statistics-readable", "statistics-empty", "guild-rankings", "journal","journal-readable","journal-transparent","journal-no-paper","journal-no-book","journal-horde-friends","journal-empty","journal-small","journal-small-bottom","journal-readable-small-bottom","guilds","note","note-readable","settings","settings-readable","corrections","diagnostic","minimap","minimap-large","alert","alert-after-death","alert-long-guild"]
    views += ["note-edit", "note-delete", "honor", "honor-readable", "honor-small", "honor-empty", "honor-year",
              "chronicle", "chronicle-readable", "chronicle-small", "chronicle-empty", "chronicle-notes"]
    views += ["statistics-encounters", "statistics-recent", "statistics-friends", "statistics-friends-recent",
              "statistics-group", "statistics-combat", "statistics-horde", "guild-rankings-combat", "statistics-readable-small"]
    views += ["journal-history", "journal-matchup", "journal-notes", "journal-history-small", "journal-notes-readable-small",
              "settings-alerts", "settings-relations", "settings-shortcuts", "settings-data", "settings-readable-alerts-small",
              "honor-story", "guide"]
    views += ["journal-largeprint", "journal-history-largeprint-small", "statistics-largeprint",
              "honor-largeprint-small", "settings-readable-alerts-largeprint-small"]
    views += ["journal-compact", "journal-history-page2", "journal-history-filter", "correction-voided",
              "honor-annual", "honor-annual-copy", "honor-annual-empty", "honor-annual-largeprint-small", "honor-podium",
              "honor-races", "honor-classes", "honor-zones", "honor-subzones", "honor-initiative",
              "honor-initiative-empty", "honor-initiative-largeprint-small", "chronicle-honor", "journal-history-honor",
              "guild-exceptions", "guild-rankings-largeprint-small",
              "settings-appearance-markers", "settings-data-experimental", "alert-preview", "kill-details"]
    # Explicit view names keep a visual correction cycle small; no arguments run
    # the complete set of real Lua page flows.
    if sys.argv[1:]: views = sys.argv[1:]
    images, report, snapshots=[],{},{}
    for name in views:
        root=g.QA.capture(name)
        assert root is not None, name+" frame absent"
        assert len(g.GrudgeLedger.errors) == 0, name+" raised an addon error"
        raw, root_id=g.QA.snapshot(root)
        frames=convert(raw)
        snapshots[name]={"root":root_id,"frames":frames}
        issues,img=render(name,frames,root_id)
        report[name]=issues
        images.append((name,img))
    # Native size thumbnails remain separate; contact sheet provides all real views.
    tilew,tileh=700,560
    sheet=Image.new("RGB",(tilew*3,tileh*math.ceil(len(images)/3)),(16,17,19))
    for i,(name,img) in enumerate(images):
        preview=img.copy();preview.thumbnail((tilew-20,tileh-20),Image.Resampling.LANCZOS)
        sheet.paste(preview,(i%3*tilew+(tilew-preview.width)//2,i//3*tileh+10))
    sheet.save(OUT/"contact-sheet.png")
    # Inspect the actual generated icon at native 32 pixels and enlarged 128 pixels.
    icon=actual_texture(g.GrudgeLedger.minimapIcon)
    if icon:
        icon.resize((32,32),Image.Resampling.LANCZOS).save(OUT/"icon-32px.png")
        swatch=Image.new("RGBA",(360,180),(25,23,23,255));d=ImageDraw.Draw(swatch)
        for x,size in ((35,32),(150,128)):
            swatch.alpha_composite(icon.resize((size,size),Image.Resampling.LANCZOS),(x,30))
            d.text((x,162),str(size)+" px",font=font(11),fill=(218,207,176,255))
        swatch.convert("RGB").save(OUT/"icon-natural-and-zoom.png")
    requested = {r["texture"] for view in snapshots.values() for r in view["frames"] if r.get("texture")}
    faces = {r["font"] for view in snapshots.values() for r in view["frames"] if r.get("font")}
    assets = {"fonts": {face: font_path(face).name for face in sorted(faces)},
              "missing_texture_files": sorted(path for path in requested if not actual_texture(path))}
    (OUT/"asset-report.json").write_text(json.dumps(assets,ensure_ascii=False,indent=2),encoding="utf-8")
    (OUT/"geometry-report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    (OUT/"captured-frames.json").write_text(json.dumps(snapshots,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"views":len(views),"issues":report,"contact_sheet":str(OUT/"contact-sheet.png")},ensure_ascii=False))
    assert not any(report.values()), "Visual geometry checks failed; inspect geometry-report.json"


if __name__=="__main__": main()
