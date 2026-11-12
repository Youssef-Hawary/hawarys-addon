#!/usr/bin/env python3
"""Build Hawary's Addon brand assets from the Hawary's Bot logo.

Outputs:
  HawarysAddon/Media/logo.tga      128x128 icon (navy tile + cyan hex H)  -> TOC IconTexture, window header
  HawarysAddon/Media/mark.tga      64x64 hex H on a navy disc             -> minimap button
  HawarysAddon/Media/glow.tga      64x64 soft cyan glow                   -> upgrade / highlight effects
  HawarysAddon/Media/ChakraPetch-Bold.ttf  brand display font (OFL)
  brand/logo.png, brand/banner.png  for the GitHub README

Run: python3 tools/make_brand.py   (needs rsvg-convert + Pillow)
"""
import io
import os
import struct
import subprocess
import zlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "HawarysAddon", "Media")
BRAND = os.path.join(ROOT, "brand")
FONT_SRC = os.path.expanduser("~/Projects/hawary-botV2/web/public/fonts")

NAVY = "#11151C"
CYAN = "#38C6F4"

GRAD = ('<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#7FE3FF"/><stop offset="1" stop-color="#0E9AC9"/>'
        '</linearGradient></defs>')
HEX = ('<path d="M32 7 53.6 19.5v25L32 57 10.4 44.5v-25Z" fill="none" stroke="url(#g)" '
       'stroke-width="3.2" stroke-linejoin="round"/>'
       '<path d="M23 21v22M41 21v22M23 32h18" stroke="url(#g)" stroke-width="5" stroke-linecap="round"/>')

LOGO_SVG = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' + GRAD +
            f'<rect width="64" height="64" rx="16" fill="{NAVY}"/>' + HEX + '</svg>')
MARK_SVG = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' + GRAD +
            f'<circle cx="32" cy="32" r="31" fill="{NAVY}"/>' + HEX + '</svg>')


def render_svg(svg: str, size: int) -> Image.Image:
    png = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size)],
                         input=svg.encode(), capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def save_tga(img: Image.Image, path: str) -> None:
    # WoW reads 32-bit uncompressed TGA; sizes must be powers of two.
    img.convert("RGBA").save(path, format="TGA", compression=None)


def woff_to_ttf(src: str, dst: str) -> None:
    """Decode a WOFF 1.0 file (zlib tables) back into a plain TrueType file."""
    data = open(src, "rb").read()
    sig, flavor, _length, num_tables = struct.unpack(">4sIIH", data[:14])
    assert sig == b"wOFF", "not a WOFF 1.0 file"
    entries = []
    for i in range(num_tables):
        tag, off, comp_len, orig_len, checksum = struct.unpack(">4sIIII", data[44 + i * 20: 64 + i * 20])
        raw = data[off:off + comp_len]
        table = zlib.decompress(raw) if comp_len < orig_len else raw
        entries.append((tag, checksum, table))
    entries.sort(key=lambda e: e[0])
    search = 1
    while search * 2 <= num_tables:
        search *= 2
    entry_selector = search.bit_length() - 1
    out = bytearray(struct.pack(">IHHHH", flavor, num_tables, search * 16, entry_selector,
                                num_tables * 16 - search * 16))
    offset = 12 + 16 * num_tables
    body = bytearray()
    for tag, checksum, table in entries:
        out += struct.pack(">4sIII", tag, checksum, offset + len(body), len(table))
        body += table + b"\0" * ((4 - len(table) % 4) % 4)
    open(dst, "wb").write(bytes(out + body))


def glow(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = size // 6
    d.ellipse([pad, pad, size - pad, size - pad], fill=(56, 198, 244, 255))
    return img.filter(ImageFilter.GaussianBlur(size / 8))


def aa_shape(size, draw_fn, scale=4) -> Image.Image:
    """Draw a white shape at 4x size, then downsample for smooth (anti-aliased) edges."""
    w, h = size
    big = Image.new("RGBA", (w * scale, h * scale), (255, 255, 255, 0))
    draw_fn(ImageDraw.Draw(big), scale)
    return big.resize((w, h), Image.LANCZOS)


def ui_shapes() -> dict:
    """White UI shapes; the addon tints them with SetVertexColor. Rounded ones are 9-slice ready."""
    shapes = {}
    # 64x64 rounded panel, radius 12 -> slice margins 16
    shapes["round"] = aa_shape((64, 64), lambda d, s: d.rounded_rectangle(
        [0, 0, 64 * s - 1, 64 * s - 1], radius=12 * s, fill=(255, 255, 255, 255)))
    # matching 1.5px outline
    shapes["round_line"] = aa_shape((64, 64), lambda d, s: d.rounded_rectangle(
        [0, 0, 64 * s - 1, 64 * s - 1], radius=12 * s, outline=(255, 255, 255, 255), width=int(1.5 * s)))
    # small radius (6) for buttons/inputs -> slice margins 8
    shapes["round_sm"] = aa_shape((32, 32), lambda d, s: d.rounded_rectangle(
        [0, 0, 32 * s - 1, 32 * s - 1], radius=6 * s, fill=(255, 255, 255, 255)))
    shapes["round_sm_line"] = aa_shape((32, 32), lambda d, s: d.rounded_rectangle(
        [0, 0, 32 * s - 1, 32 * s - 1], radius=6 * s, outline=(255, 255, 255, 255), width=int(1.25 * s)))
    # pill for toggles/tags
    shapes["pill"] = aa_shape((64, 32), lambda d, s: d.rounded_rectangle(
        [0, 0, 64 * s - 1, 32 * s - 1], radius=16 * s, fill=(255, 255, 255, 255)))
    shapes["circle"] = aa_shape((32, 32), lambda d, s: d.ellipse(
        [0, 0, 32 * s - 1, 32 * s - 1], fill=(255, 255, 255, 255)))
    # close X
    def x(d, s):
        p, q, wdt = 9 * s, 23 * s, int(2.6 * s)
        d.line([p, p, q, q], fill=(255, 255, 255, 255), width=wdt)
        d.line([p, q, q, p], fill=(255, 255, 255, 255), width=wdt)
    shapes["x"] = aa_shape((32, 32), x)
    # upgrade arrow (filled, with dark outline baked in for readability on any icon)
    def arrow(d, s):
        pts = [(16, 3), (29, 16), (21, 16), (21, 29), (11, 29), (11, 16), (3, 16)]
        d.polygon([(px * s, py * s) for px, py in pts], fill=(255, 255, 255, 255),
                  outline=(0, 0, 0, 255), width=int(1.6 * s))
    shapes["arrow"] = aa_shape((32, 32), arrow)
    # check mark
    def check(d, s):
        d.line([(7 * s, 17 * s), (13 * s, 23 * s), (25 * s, 9 * s)], fill=(255, 255, 255, 255),
               width=int(3.2 * s), joint="curve")
    shapes["check"] = aa_shape((32, 32), check)
    # chevron right (nav)
    def chev(d, s):
        d.line([(12 * s, 8 * s), (20 * s, 16 * s), (12 * s, 24 * s)], fill=(255, 255, 255, 255),
               width=int(2.6 * s), joint="curve")
    shapes["chevron"] = aa_shape((32, 32), chev)
    # soft drop shadow, 9-slice with margins 24
    sh = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([20, 20, 75, 75], radius=14, fill=(0, 0, 0, 255))
    shapes["shadow"] = sh.filter(ImageFilter.GaussianBlur(9)).resize((128, 128), Image.LANCZOS)
    return shapes


def banner(font_path: str) -> Image.Image:
    w, h = 1280, 400
    img = Image.new("RGBA", (w, h), NAVY)
    g = glow(512).resize((560, 560))
    g.putalpha(g.getchannel("A").point(lambda a: a // 3))
    img.alpha_composite(g, (-60, -80))
    img.alpha_composite(render_svg(LOGO_SVG, 240), (90, 80))
    d = ImageDraw.Draw(img)
    big = ImageFont.truetype(font_path, 96)
    small = ImageFont.truetype(font_path, 34)
    d.text((380, 105), "HAWARY'S", font=big, fill="#F2F5F9")
    d.text((380, 200), "ADDON", font=big, fill=CYAN)
    d.text((384, 312), "All-in-one addon for World of Warcraft: Forever", font=small, fill="#AEB7C7")
    return img.convert("RGB")


def main() -> None:
    os.makedirs(MEDIA, exist_ok=True)
    os.makedirs(BRAND, exist_ok=True)
    save_tga(render_svg(LOGO_SVG, 128), os.path.join(MEDIA, "logo.tga"))
    save_tga(render_svg(MARK_SVG, 64), os.path.join(MEDIA, "mark.tga"))
    save_tga(glow(64), os.path.join(MEDIA, "glow.tga"))
    for name, img in ui_shapes().items():
        save_tga(img, os.path.join(MEDIA, name + ".tga"))
    ttf = os.path.join(MEDIA, "ChakraPetch-Bold.ttf")
    woff_to_ttf(os.path.join(FONT_SRC, "chakra-petch-bold.woff"), ttf)
    with open(os.path.join(FONT_SRC, "OFL-ChakraPetch.txt")) as f:
        open(os.path.join(MEDIA, "OFL-ChakraPetch.txt"), "w").write(f.read())
    render_svg(LOGO_SVG, 512).save(os.path.join(BRAND, "logo.png"))
    open(os.path.join(BRAND, "logo.svg"), "w").write(LOGO_SVG)
    banner(ttf).save(os.path.join(BRAND, "banner.png"))
    print("brand assets written")


if __name__ == "__main__":
    main()
