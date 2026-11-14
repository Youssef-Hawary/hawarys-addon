#!/usr/bin/env python3
"""Static checks for Hawary's Addon.

1. Syntax: every .lua file must compile under LuaJIT (Lua 5.1, the same language as WoW).
2. Globals: every global the addon READS must exist in the WoW: Forever API reference
   (the wow-addon-api-wowf skill), Blizzard's Forever FrameXML function list, or the reviewed
   allow-list below. Every global the addon WRITES must be on the allowed-writes list.

Usage: python3 tools/check.py [--api-dir ~/.wow-api]
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "HawarysAddon")

# Globals we deliberately create (TOC-referenced handlers, slash commands, saved variables).
ALLOWED_WRITES = {
    "HawarysAddonDB", "HawarysAddonCharDB",
    "HawarysAddon_OnAddonCompartmentClick", "HawarysAddon_OnAddonCompartmentEnter",
    "HawarysAddon_OnAddonCompartmentLeave",
    "SLASH_HAWARYSADDON1", "SLASH_HAWARYSADDON2", "SLASH_HAWARYSADDON3",
    # key bindings (Bindings.xml)
    "BINDING_HEADER_HAWARYSADDON", "BINDING_NAME_HAWARYSADDON_TOGGLE", "BINDING_NAME_HAWARYSADDON_GUIDE",
    "BINDING_NAME_HAWARYSADDON_TRACKER", "HawarysAddon_Toggle", "HawarysAddon_ToggleGuide", "HawarysAddon_ToggleTracker",
    "HawarysDiscoveryPinMixin", "HawarysQuestPinMixin",  # referenced by Modules/Discovery.xml
}

# Lua 5.1 standard library + WoW Lua extensions that the API docs don't list as "fn".
LUA_GLOBALS = {
    "_G", "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawget", "rawset", "select",
    "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "math", "string",
    "table", "time", "date", "wipe", "tinsert", "tremove", "strsplit", "strjoin", "format", "floor",
    "geterrorhandler", "hooksecurefunc", "issecretvalue", "securecall",
}

# Blizzard frames, font objects and tables used by the addon (checked by hand against the
# Forever UI source pinned in docs/API-NOTES.md).
REVIEWED = {
    "UIParent", "GameTooltip", "ItemRefTooltip", "Minimap", "WorldMapFrame", "DEFAULT_CHAT_FRAME",
    "UISpecialFrames", "SlashCmdList", "StaticPopupDialogs", "SOUNDKIT", "STANDARD_TEXT_FONT",
    "SettingsPanel", "QuestInfoFrame", "QuestFrameRewardPanel", "ContainerFrameCombinedBags",
    "MinimalSliderWithSteppersMixin", "TooltipDataProcessor", "TooltipUtil", "Settings", "Enum",
    "GameFontNormalLarge", "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall",
    # legacy globals not in generated docs but called by Blizzard's own Forever UI code
    "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems", "CanGuildBankRepair", "GetNumLootItems",
    "LootSlot", "GetInventoryItemLink", "GetInventoryItemID", "GetNumQuestChoices", "GetQuestItemLink",
    "GetQuestItemInfo", "AcceptGroup", "IsGuildMember", "CancelDuel", "InCombatLockdown", "PlaySound",
    "CreateFrame", "CreateFont", "StaticPopup_Show", "StaticPopup_Hide", "HideUIPanel",
    "QuestInfo_ShowRewards", "QuestInfoItem_OnClick", "CreateSettingsButtonInitializer",
    "CreateSettingsListSectionHeaderInitializer", "GetCursorPosition",
    # quest dialog functions called by Blizzard's own Forever QuestFrame.lua (Mainline, build 70888)
    "AcceptQuest", "AcknowledgeAutoAcceptQuest", "CompleteQuest", "GetActiveTitle", "GetAvailableQuestInfo",
    "GetNumActiveQuests", "GetNumAvailableQuests", "GetQuestMoneyToGet", "GetQuestReward", "IsQuestCompletable",
    "QuestGetAutoAccept", "SelectActiveQuest", "SelectAvailableQuest",
    # FrameXML table (UiMapPoint.CreateFromCoordinates in framexml/mixins.md)
    "UiMapPoint",
    # 1.3.0 – checked in the Forever UI source (Gethe/wow-ui-source, branch forever):
    # ItemLocation = {} in Blizzard_ObjectAPI/Mainline/ItemLocation.lua; MenuUtil in framexml/mixins.md;
    # NUM_CONTAINER_FRAMES set in Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua
    "ItemLocation", "MenuUtil", "NUM_CONTAINER_FRAMES",
    # called by Blizzard's own Forever profession UI (Blizzard_Professions/Camelot) and
    # the Forever auction house window (Blizzard_AuctionHouseUI)
    "GetProfessions", "GetProfessionInfo", "AuctionHouseFrame",
    # durability (Blizzard's Forever PaperDoll/Durability code) and map canvas mixins (Blizzard_MapCanvas)
    "GetInventoryItemDurability", "MapCanvasPinMixin", "MapCanvasDataProviderMixin",
    # quest data: our load-on-demand data addon's global, and QuestieDB's public global (optional)
    "HawarysQuestData", "HawarysGuides", "LibQuestieDB", "bit", "loadstring", "load",
    # trainer + macro window functions used by Blizzard's own Forever TrainerUI / MacroUI
    # 1.2.0: merchant window (Blizzard_UIPanels_Game/Vanilla/MerchantFrame.xml), the jump binding
    # function (Blizzard_FrameXML/Bindings_Camelot.xml)
    "MerchantFrame", "JumpOrAscendStart",
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "CreateMacro", "GetNumMacros", "Constants",
}


def lua_files():
    for dirpath, _, files in os.walk(ADDON):
        for f in sorted(files):
            if f.endswith(".lua"):
                yield os.path.join(dirpath, f)


def known_names(api_dir):
    names = set()
    with open(os.path.join(api_dir, "signatures.txt"), encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^fn ([A-Za-z_]\w*)(?:\.|\()", line)
            if m:
                names.add(m.group(1))
            m = re.match(r"^(?:const|enum) ([A-Za-z_]\w*)", line)
            if m:
                names.add(m.group(1))
    funcs = os.path.join(api_dir, "framexml", "functions.md")
    if os.path.exists(funcs):
        with open(funcs, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^- `([A-Za-z_]\w*)[.(:]", line)
                if m:
                    names.add(m.group(1))
    return names


def globals_in(path):
    out = subprocess.run(["luac", "-l", "-l", "-p", path], capture_output=True, text=True)
    if out.returncode != 0:
        return None, None, out.stderr
    reads, writes = set(), set()
    for line in out.stdout.splitlines():
        m = re.search(r"\b(GETTABUP|SETTABUP)\b.*_ENV \"([^\"]+)\"", line)
        if m:
            (reads if m.group(1) == "GETTABUP" else writes).add(m.group(2))
    return reads, writes, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-dir", default=os.path.expanduser("~/.wow-api"))
    args = ap.parse_args()

    failures = 0
    files = list(lua_files())
    for path in files:
        r = subprocess.run(["luajit", "-b", path, "/dev/null"], capture_output=True, text=True)
        if r.returncode != 0:
            print(f"SYNTAX  {os.path.relpath(path, ROOT)}: {r.stderr.strip()}")
            failures += 1
    print(f"syntax: {len(files)} files checked with LuaJIT (Lua 5.1)")

    known = known_names(args.api_dir) | LUA_GLOBALS | REVIEWED | ALLOWED_WRITES
    unknown_reads = {}
    for path in files:
        reads, writes, err = globals_in(path)
        rel = os.path.relpath(path, ROOT)
        if err:
            print(f"LUAC    {rel}: {err.strip()}")
            failures += 1
            continue
        for w in sorted(writes - ALLOWED_WRITES):
            print(f"GLOBAL WRITE  {rel}: {w}")
            failures += 1
        for name in reads - known:
            unknown_reads.setdefault(name, []).append(rel)
    for name, where in sorted(unknown_reads.items()):
        print(f"UNKNOWN GLOBAL  {name}  ({', '.join(sorted(set(where)))})")
        failures += 1
    print(f"globals: checked against {len(known)} known Forever names")
    print("RESULT:", "FAIL" if failures else "PASS", f"({failures} problem(s))")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
