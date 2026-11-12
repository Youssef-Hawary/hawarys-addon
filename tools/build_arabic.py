#!/usr/bin/env python3
"""Build Arabic support for Hawary's Addon.

WoW's text engine draws left-to-right and doesn't join Arabic letters, so this tool:
  1. shapes every Arabic word into its joined letter forms (Unicode presentation forms),
  2. puts each line in visual (right-to-left) order, keeping English words, numbers,
     placeholders (%s, %d) and |c...|r colour codes readable,
  3. writes HawarysAddon/Locales/arAR.lua,
  4. (with --font) builds HawarysAddon/Media/HawarysArabic.ttf = Noto Sans Arabic + Noto Sans
     (both SIL Open Font License), because WoW's own fonts have no Arabic letters.

Usage: python3 tools/build_arabic.py [--font]   (--font needs the fontTools package)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "locales", "ar.txt")
OUT = os.path.join(ROOT, "HawarysAddon", "Locales", "arAR.lua")
FONT_OUT = os.path.join(ROOT, "HawarysAddon", "Media", "HawarysArabic.ttf")
WRAP = 46  # characters per line for long texts (each line is reversed on its own)

# letter -> (isolated, final, initial, medial); right-joining letters have only 2 forms
FORMS = {
    0x0621: (0xFE80,), 0x0622: (0xFE81, 0xFE82), 0x0623: (0xFE83, 0xFE84), 0x0624: (0xFE85, 0xFE86),
    0x0625: (0xFE87, 0xFE88), 0x0626: (0xFE89, 0xFE8A, 0xFE8B, 0xFE8C), 0x0627: (0xFE8D, 0xFE8E),
    0x0628: (0xFE8F, 0xFE90, 0xFE91, 0xFE92), 0x0629: (0xFE93, 0xFE94), 0x062A: (0xFE95, 0xFE96, 0xFE97, 0xFE98),
    0x062B: (0xFE99, 0xFE9A, 0xFE9B, 0xFE9C), 0x062C: (0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0),
    0x062D: (0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4), 0x062E: (0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8), 0x062F: (0xFEA9, 0xFEAA),
    0x0630: (0xFEAB, 0xFEAC), 0x0631: (0xFEAD, 0xFEAE), 0x0632: (0xFEAF, 0xFEB0),
    0x0633: (0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4), 0x0634: (0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8),
    0x0635: (0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC), 0x0636: (0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0),
    0x0637: (0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4), 0x0638: (0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8),
    0x0639: (0xFEC9, 0xFECA, 0xFECB, 0xFECC), 0x063A: (0xFECD, 0xFECE, 0xFECF, 0xFED0),
    0x0641: (0xFED1, 0xFED2, 0xFED3, 0xFED4), 0x0642: (0xFED5, 0xFED6, 0xFED7, 0xFED8),
    0x0643: (0xFED9, 0xFEDA, 0xFEDB, 0xFEDC), 0x0644: (0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0),
    0x0645: (0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4), 0x0646: (0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8),
    0x0647: (0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC), 0x0648: (0xFEED, 0xFEEE), 0x0649: (0xFEEF, 0xFEF0),
    0x064A: (0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4),
}
LAM_ALEF = {0x0622: (0xFEF5, 0xFEF6), 0x0623: (0xFEF7, 0xFEF8), 0x0625: (0xFEF9, 0xFEFA), 0x0627: (0xFEFB, 0xFEFC)}
TATWEEL = 0x0640
HARAKAT = set(range(0x064B, 0x0653))
MIRROR = {"(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{", "<": ">", ">": "<", "«": "»", "»": "«"}


def is_arabic(ch):
    o = ord(ch)
    return 0x0600 <= o <= 0x06FF or 0xFB50 <= o <= 0xFDFF or 0xFE70 <= o <= 0xFEFF


def joins_next(cp):  # can this letter connect to the letter after it?
    return cp == TATWEEL or (cp in FORMS and len(FORMS[cp]) == 4)


def joins_prev(cp):
    return cp == TATWEEL or (cp in FORMS and len(FORMS[cp]) >= 2)


def shape_word(word):
    cps = [ord(c) for c in word if ord(c) not in HARAKAT]
    out, i = [], 0
    while i < len(cps):
        cp = cps[i]
        prev = cps[i - 1] if i > 0 else None
        link_prev = prev is not None and joins_next(prev) and joins_prev(cp)
        if cp == 0x0644 and i + 1 < len(cps) and cps[i + 1] in LAM_ALEF:  # lam + alef ligature
            iso, fin = LAM_ALEF[cps[i + 1]]
            out.append(fin if link_prev else iso)
            i += 2
            continue
        forms = FORMS.get(cp)
        if not forms:
            out.append(cp)
            i += 1
            continue
        nxt = cps[i + 1] if i + 1 < len(cps) else None
        link_next = nxt is not None and joins_next(cp) and joins_prev(nxt)
        if len(forms) == 1:
            out.append(forms[0])
        elif len(forms) == 2:
            out.append(forms[1] if link_prev else forms[0])
        else:
            if link_prev and link_next:
                out.append(forms[3])
            elif link_prev:
                out.append(forms[1])
            elif link_next:
                out.append(forms[2])
            else:
                out.append(forms[0])
        i += 1
    return "".join(chr(c) for c in out)


TOKEN = re.compile(
    r"(\|c[0-9a-fA-F]{8}[^|]*\|r)"          # colour code (Latin inside)
    r"|(\|T[^|]*\|t)"                       # texture
    r"|(%[-+ #0]*\d*(?:\.\d+)?[sdfiqxX%])"  # format placeholder
    r"|([\u0600-\u06FF\uFB50-\uFDFF\uFE70-\uFEFF]+)"  # Arabic word
    r"|([A-Za-z0-9\u00C0-\u024F_'./:+\-]+)"  # Latin word / number
    r"|(.)", re.S)


def visual_line(line):
    units = []  # (text, dir) dir: R, L, N
    for m in TOKEN.finditer(line):
        colour, tex, ph, ar, lat, other = m.groups()
        if ar:
            units.append([shape_word(ar), "R"])
        elif colour or tex or ph or lat:
            units.append([m.group(0), "L"])
        else:
            units.append([other, "N"])
    # neutrals between two Latin units stay Latin, the rest follow the paragraph (RTL)
    for i, u in enumerate(units):
        if u[1] != "N":
            continue
        left = next((units[j][1] for j in range(i - 1, -1, -1) if units[j][1] != "N"), None)
        right = next((units[j][1] for j in range(i + 1, len(units)) if units[j][1] != "N"), None)
        u[1] = "L" if (left == "L" and right == "L") else "R"
    runs = []
    for text, d in units:
        if runs and runs[-1][0] == d:
            runs[-1][1].append(text)
        else:
            runs.append([d, [text]])
    out = []
    for d, texts in reversed(runs):
        if d == "L":
            out.append("".join(texts))
        else:
            out.append("".join("".join(MIRROR.get(c, c) for c in reversed(t)) for t in reversed(texts)))
    return "".join(out)


def wrap(text, width=WRAP):
    words, lines, cur = text.split(" "), [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w) if cur else w
    if cur:
        lines.append(cur)
    return lines


PLACEHOLDER = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdfiqxX]")


def convert(text):
    """Returns the visual string, or None when it can't be shown correctly."""
    if len(PLACEHOLDER.findall(text)) >= 2:
        return None  # Lua's format() can't reorder arguments for right-to-left
    return "\n".join(visual_line(l) for l in wrap(text))


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def build_lua():
    entries, skipped = [], []
    with open(SRC, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            key, _, text = line.partition(" = ")
            key, text = key.strip(), text.strip()
            if not re.fullmatch(r"[A-Z0-9_]+", key) or not text:
                sys.exit(f"bad line: {line}")
            vis = convert(text)
            if vis is None:
                skipped.append(key)
                continue
            entries.append((key, vis))
    body = "\n".join(f"    {k} = {lua_string(v)}," for k, v in entries)
    lua = f'''-- Hawary's Addon: Arabic (العربية). GENERATED by tools/build_arabic.py from locales/ar.txt –
-- edit the .txt file and rebuild. Texts are pre-shaped and in visual order because WoW
-- draws text left-to-right without joining Arabic letters.
local _, ns = ...

local AR = {{
{body}
}}

-- Called once the saved settings are loaded (language = "ar"). Swaps the strings in L and in
-- texts that modules already copied (titles, descriptions, option labels), and the fonts.
function ns.ApplyArabic()
    local L = ns.L
    local byText = {{}}
    for key, text in pairs(L) do
        if type(text) == "string" and AR[key] then byText[text] = AR[key] end
    end
    for key, text in pairs(AR) do L[key] = text end
    local function swap(t, field)
        local v = t[field]
        if type(v) == "string" and byText[v] then t[field] = byText[v] end
    end
    local function swapModule(m)
        swap(m, "title"); swap(m, "desc")
        for _, opt in ipairs(m.options or {{}}) do
            swap(opt, "label"); swap(opt, "desc"); swap(opt, "buttonText")
        end
    end
    for _, m in pairs(ns.modules) do swapModule(m) end
    if ns.General then swapModule(ns.General) end
    for _, item in ipairs(ns.roadmap or {{}}) do swap(item, "title"); swap(item, "desc") end
    if ns.Theme and ns.Theme.UseArabicFonts then ns.Theme.UseArabicFonts() end
    ns.arabic = true
end
'''
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(lua)
    print(f"arAR.lua: {len(entries)} strings" + (f", skipped (2+ placeholders): {', '.join(skipped)}" if skipped else ""))


def build_font():
    from fontTools import subset
    from fontTools.merge import Merger
    from fontTools.ttLib import TTFont
    import tempfile
    tmp = tempfile.mkdtemp()
    parts = [
        ("/usr/share/fonts/noto/NotoSans-Medium.ttf", "U+0020-007E,U+00A0-024F,U+2010-2027,U+2030-205E,U+20AC,U+2122,U+2190-2193,U+2605,U+2606,U+2713"),
        ("/usr/share/fonts/noto/NotoSansArabic-Medium.ttf", "U+0600-06FF,U+FB50-FDFF,U+FE70-FEFF"),
    ]
    files = []
    for i, (src, uni) in enumerate(parts):
        out = os.path.join(tmp, f"p{i}.ttf")
        args = [src, f"--unicodes={uni}", f"--output-file={out}", "--layout-features=", "--no-hinting",
                "--drop-tables+=GSUB,GPOS,GDEF,DSIG,MATH,STAT,fvar,gvar,avar,HVAR,MVAR"]
        subset.main(args)
        files.append(out)
    merged = Merger().merge(files)
    merged["name"].setName("Hawarys Arabic", 1, 3, 1, 0x409)
    merged["name"].setName("Hawarys Arabic", 4, 3, 1, 0x409)
    merged.save(FONT_OUT)
    print(f"font: {FONT_OUT} ({os.path.getsize(FONT_OUT) // 1024} KB)")


if __name__ == "__main__":
    build_lua()
    if "--font" in sys.argv:
        build_font()
