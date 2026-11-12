#!/usr/bin/env python3
"""Build HawarysAddon_Guides (load-on-demand) from Polestar's WoW Forever guides.

Polestar (https://github.com/fitzforge/polestar) is GPLv3 ("Copyright (c) 2026 The Polestar
authors"). Its guide text stays under GPLv3 when copied (their LICENSE-EXCEPTION.md does not
cover guide text) - Hawary's Addon is GPLv3 too, and credits them in CREDITS.md.

Each .guide is converted to Hawary's guide format (docs/GUIDE-FORMAT.md) with these extras:
  header:  id
  steps:   section <title>, tip <text>, objective <quest>.<n> <verb>, getfp <name>, vendor,
           suffixes " only <tokens>" and " when <cond> <id>"
Zone names are resolved to uiMapIDs with QuestieDB's area table (comments name each area).

Usage: python3 tools/build_guides.py <polestar dir> <questiedb dir>
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "HawarysAddon_Guides")
HEADER_KEYS = ("guide", "title", "faction", "race", "class", "levels", "zone", "next", "category", "folder", "keywords")
QUOTED = re.compile(r'"([^"]*)"')


def zone_names(qdb):
    """name -> uiMapID from areaIdToUiMapId.lua comments ('-- Dun Morogh', '-- Longshore -> Westfall')."""
    names = {}
    for line in open(os.path.join(qdb, "support/Forever/Zones/areaIdToUiMapId.lua"), encoding="utf-8"):
        m = re.match(r"\s*\[\d+\]\s*=\s*(\d+),\s*--\s*(.+?)\s*$", line)
        if not m or m.group(1) == "0" or "Synthetic" in m.group(2) or "alias" in m.group(2):
            continue
        ui, label = int(m.group(1)), m.group(2)
        left = label.split("->")[0].strip()
        if "->" not in label:
            names[left] = ui
        else:
            names.setdefault(left, ui)
    return names


def convert(text, zones):
    """Returns (header dict, list of Hawary-format lines)."""
    header, out = {}, []
    in_header, zone_map, when = True, None, None
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        word, _, rest = s.partition(" ")
        if word not in ("tip", "note"):
            rest = rest.split("--")[0]
        rest = rest.strip()
        if in_header and word in HEADER_KEYS:
            header[word] = rest
            if word == "zone":
                zone_map = zones.get(rest)
            continue
        if word == "reward" and in_header:
            continue
        if word == "step":
            in_header, when = False, None
            out.append(f"section {rest}")
            continue
        in_header = False
        if word == "zone":
            zone_map = zones.get(rest, zone_map)
            continue
        if word == "when":
            when = rest
            continue
        only = None
        m = re.search(r"\s+only\s+(!?[A-Za-z]+(?:,!?[A-Za-z]+)*)\s*$", rest)
        if m and word not in ("tip", "note"):
            only, rest = m.group(1), rest[:m.start()].strip()
        suffix = (f" only {only}" if only else "") + (f" when {when}" if when else "")
        cm = re.search(r"@\s*([\d.]+)\s*,\s*([\d.]+)", rest)
        mm = re.search(r"\bmap\s+(\d+)", rest)
        mapid = int(mm.group(1)) if mm else zone_map
        coord = ""
        if cm:
            coord = f" @ {cm.group(1)} {cm.group(2)}" + (f" map={mapid}" if mapid else "")
            rest = (rest[:cm.start()] + rest[cm.end():]).strip()
        rest = re.sub(r"\bmap\s+\d+", "", rest).strip()
        qo = re.search(r"\bquest\s+(\d+)(?:\.(\d+))?", rest)
        if word in ("accept", "turnin", "complete"):
            qid = re.match(r"(\d+)", rest)
            if qid:
                out.append(f"{word} {qid.group(1)}{coord}{suffix}")
        elif word in ("kill", "collect", "use", "interact", "talk") and qo:
            out.append(f"objective {qo.group(1)}.{qo.group(2) or '0'} {word}{coord}{suffix}")
        elif word == "goto":
            g = re.match(r"([\d.]+)\s*,\s*([\d.]+)\s*(.*)", rest)
            if g:
                label = QUOTED.search(g.group(3))
                out.append(f"goto {g.group(1)} {g.group(2)} {label.group(1) if label else ''}".rstrip()
                           + (f" map={mapid}" if mapid else "") + suffix)
        elif word == "level":
            lv = re.match(r"([\d.]+)", rest)
            if lv:
                out.append(f"level {lv.group(1)}{suffix}")
        elif word == "train":
            out.append(f"train{suffix}")
        elif word in ("fly", "sethome", "getfp"):
            q = QUOTED.search(rest)
            name = q.group(1) if q else rest
            out.append(f"{ {'fly': 'fly', 'sethome': 'hearth', 'getfp': 'getfp'}[word] } {name}{suffix}")
        elif word in ("vendor", "buy"):
            out.append(f"vendor{suffix}")
        elif word == "tip":
            out.append(f"tip {rest}")
        elif word == "note":
            out.append(f"note {QUOTED.sub(lambda x: x.group(1), rest)}{coord}{suffix}")
        elif word == "die" and cm:
            q = QUOTED.search(rest)
            out.append(f"note {q.group(1) if q else 'Spirit healer'}{coord}{suffix}")
    return header, out


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    polestar, qdb = sys.argv[1], sys.argv[2]
    zones = zone_names(qdb)
    entries = []
    for dirpath, _, files in os.walk(os.path.join(polestar, "guides", "forever")):
        for f in sorted(files):
            if not f.endswith(".guide"):
                continue
            header, lines = convert(open(os.path.join(dirpath, f), encoding="utf-8").read(), zones)
            if not header.get("guide") or not lines:
                continue
            gid = header["guide"]
            body = [f"guide: {header.get('title', gid)}", f"id: {gid}"]
            if header.get("levels"):
                body.append(f"level: {header['levels']}")
            if zones.get(header.get("zone", "")):
                body.append(f"map: {zones[header['zone']]}")
            entries.append((gid, header, "\n".join(body + lines)))
    entries.sort(key=lambda e: e[0])
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "Guides.lua"), "w", encoding="utf-8") as fh:
        fh.write("-- Generated by tools/build_guides.py from Polestar's guides (GPLv3). Do not edit.\n")
        fh.write("HawarysGuides = { list = {}, text = {} }\n")
        for gid, h, body in entries:
            fields = ", ".join(f"{k} = {lua_str(h[k])}" for k in ("title", "faction", "race", "class", "levels", "zone", "next", "category") if h.get(k))
            if "]==]" in body:
                raise SystemExit(f"{gid}: contains ]==]")
            fh.write(f"HawarysGuides.list[#HawarysGuides.list + 1] = {{ id = {lua_str(gid)}, {fields} }}\n")
            fh.write(f"HawarysGuides.text[{lua_str(gid)}] = [==[{body}]==]\n")
    with open(os.path.join(OUT, "HawarysAddon_Guides.toc"), "w", encoding="utf-8") as fh:
        fh.write("## Interface: 16001\n## Title: |cff38c6f4Hawary's|r Addon – Leveling Guides\n")
        fh.write("## Notes: 1-60 Alliance and Horde routes and class quests for Hawary's Addon (from Polestar, GPLv3). Loaded only when needed.\n")
        fh.write("## Author: Hawary\n## Version: 1.0.0\n## LoadOnDemand: 1\n## Dependencies: HawarysAddon\n")
        fh.write("## IconTexture: Interface\\AddOns\\HawarysAddon\\Media\\logo\n## X-License: GPL-3.0-or-later\n\nGuides.lua\n")
    with open(os.path.join(OUT, "CREDITS.md"), "w", encoding="utf-8") as fh:
        fh.write("# Guide credits\n\nThe leveling routes and class guides in this folder are converted from **Polestar**\n")
        fh.write("(https://github.com/fitzforge/polestar), Copyright (c) 2026 The Polestar authors, licensed under\n")
        fh.write("the GNU GPL v3. They were converted to Hawary's guide format; the routes and tips are theirs.\n")
        fh.write("Hawary's Addon (GPL-3.0-or-later) is not affiliated with or endorsed by Polestar.\n\nThank you to the Polestar authors.\n")
    with open(os.path.join(ROOT, "LICENSE"), encoding="utf-8") as a, open(os.path.join(OUT, "LICENSE"), "w", encoding="utf-8") as b:
        b.write(a.read())
    print(f"guides built: {len(entries)} (zone names known: {len(zones)})")


if __name__ == "__main__":
    main()
