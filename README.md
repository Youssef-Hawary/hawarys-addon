<p align="center"><img src="brand/banner.png" alt="Hawary's Addon" width="820"></p>

# Hawary's Addon

**One addon for World of Warcraft: Forever** that brings together what the most popular addons do, with one clean Hawary look and one settings window.

- **Game:** World of Warcraft: Forever, client 1.60.1, `## Interface: 16001`
- **Version:** 1.2.0 (12 new features, a **For Fun** category with 10 fun extras, Arabic, controller support)
- **License:** GPL-3.0-or-later. Free forever, code fully visible, as Blizzard's add-on policy requires.

## What's in it

| Module | Like | What it does |
|---|---|---|
| **Leveling routes 1-60** | Zygor, RestedXP, Polestar | Pick **Alliance or Horde, your race and class** and press *Start my route*. 146 step-by-step guides (every race's start zone, then 30-40 / 40-50 / 50-60, plus class quests) with **11,433 steps**. Steps you already did are **skipped**, race/class-only steps only show for you, and the next zone loads by itself. |
| **Quests** | Questie | **4,244 quests, 10,119 NPCs, 6,645 objects, 14,889 items** for WoW Forever. Quest givers (!), turn-ins (?) and **every objective spot** (mobs, eggs, crates, drops, places) and **hidden objectives** on your world map and minimap; quest lines in mob/object/item tooltips; prerequisite chains respected. Uses an installed QuestieDB if you have it. |
| **Trainer Planner** | What's Training | What you can learn now and at the next levels, with the gold you'll need. |
| **Macro Helper** | (new) | A **macro generator**: template + spell → preview → *Create macro*. Normal Blizzard macros only. |
| **Journey & Guide** | Zygor, RestedXP, Questie, NAG Journey, Overwolf stats | A floating **step-by-step guide window** with the current step, its objectives and the next steps. A big **direction arrow** with distance. **Blizzard's own map pin and in-world marker** for the current step. **Auto Journey** builds your route from your own quest log (finished quests first, then the nearest objectives). **Import step guides** ([format](docs/GUIDE-FORMAT.md)). **Session stats** (XP/hour, time to level). Level-up notice. Optional quest automation: off by default, Shift pauses it, never in combat. |
| **Gear & Upgrades** | Pawn, GearQuest, NAG Journey | Stat weights for your class and spec. Tooltip shows `+12% upgrade` or `-5% vs equipped`, plus the exact item level and item ID. Green arrows on upgrades in your bags. **Marks the best quest reward** (your biggest upgrade, or what sells for the most) and can pre-select it. You still click Complete. Notices when you loot an upgrade. |
| **Bags** | Baganator, Altoholic | Remembers every character's bags, bank and gear. Item tooltips show who has how many (bags / bank / worn). Total gold across characters on the Home page. |
| **Professions** | SkillUp, Profession Shopping List, ForeverProfit | Profession ranks with progress bars. The recipes you know, **ranked by profit** with auction prices (unknown prices stay "?", never free). A **shopping list** that checks reagents against every character's bags and bank, with the cost of what's missing. Reagent tooltips show "have / need". |
| **Market** | Auctionator | Remembers **auction house prices** from your normal browsing and searches, plus a **Hawary Scan** button for a full scan (once per 15 min, read in chunks so the game doesn't freeze). Tooltips show the AH price and its age. Prices are kept per auction house. It **never buys, bids or posts**. |
| **Alts & Gold** | Altoholic, Overwolf character snapshot | Every character's level, item level, gold, professions and last login. A **gold chart** (7–90 days) and an **item search across all your characters**. |
| **Dungeons** | Dungeon Journal, Overwolf adventure planner | An **Adventure Planner** from Blizzard's own Group Finder list (Forever has no Encounter Journal), showing what fits your level now and what's coming in the next 5 levels. A **dungeon log** with runs, time, bosses and your best time. |
| **Discovery** | RareScanner, GatherMate2, Overwolf map | Your **own world-map layer** using Blizzard's map pin system. **Rare alerts** when you target, mouse over or see one on the minimap. Herbs, ore and chests are recorded **when you gather or open them**, because Forever blocks reading minimap dots. |
| **What now?** | (new) | A Home card and `/ha now` with your best next move: repair, full bags, an upgrade to equip, turn-ins, trainer, a dungeon for your level, shopping list, rested XP. Click to open the right page. |
| **Journey Diary** | Overwolf clips, Journey Forever | A **timeline** of your road to 60 (levels, dungeon clears, epics, rares, gold and quest milestones) with **optional screenshots**. |
| **Quality of Life** | Leatrix Plus, Leatrix Maps, BlizzMove | Auto repair (guild funds optional), sell junk, instant loot, accept invites from friends & guild, decline duels, max camera distance, coordinates on the minimap and world map, drag Blizzard windows. |

### New in 1.2.0

| Module | Like | What it does |
|---|---|---|
| **Quest Tracker+** | Questie, Zygor | Compact tracker with the **distance** to each quest, **party members on the same quest**, and **click to point the arrow**. **Quest icons over NPC nameplates** (`!` pick up, `?` turn in, `*` needed). |
| **BiS & Sets** | Pawn, Zygor gear finder | **Best-in-slot finder** for your level and the next 5 levels, from your bags, your alts, the auction house and quest rewards. **Equipment sets** with one-click swaps (out of combat). |
| **Bag Categories & Junk** | Baganator, Scrap | Bags grouped into categories. **Your own junk list**: drag items in, and at a merchant each click on *Sell junk* sells one stack. |
| **Auction Watch** | Auctionator | Tells you which of your auctions has been **undercut**. It never cancels or reposts. |
| **Flight Paths** | Zygor travel | The nearest known flight master (`/ha fly`), the ones you still need on this continent, and map pins. |
| **Minimap Button Bag** | MinimapButtonButton | Other addons' minimap buttons in one drawer (middle-click or Shift-click the Hawary button). |
| **Profiles** | Ace profiles | Save settings by name, load on any character, auto-load per character. |
| **Controller & key bindings** | ConsolePort-lite | Hawary's buttons work with Forever's gamepad navigation. Key bindings for the window, the guide and the tracker. |
| **Arabic (العربية)** | – | General → Language. Text is pre-shaped and bundled with an Arabic font, because WoW doesn't join Arabic letters itself. First version: some texts are still English. |

### For Fun

| Page | What it does |
|---|---|
| **Skins** | 11 looks for Hawary's Addon: Neon, Blizzard, Tactical Red, Arcane Gold, Fel Green, Frostbite, Void Purple, Sunset Pop, Bubblegum, Hacker Terminal, Banana Mode. |
| **Fashion Studio** | Random outfits (from your items, or **wild** from any item) on a preview of your character. |
| **Fun Stats & Badges** | Jumps, deaths, yards walked, quests, gold and hearthstones. 21 silly badges and **3 daily challenges** with a streak. |
| **Hex Hop** | A 30-second click mini-game with combos and golden hexes. |
| **Fun Moments** | Fortune of the day (`/ha fortune`), confetti when you level up, a death roast, and an AFK screen with your character turning slowly. |

Game-file skin changers, like the ones for Valorant or LoL, are **not** in here and never will be: they get accounts banned. See [docs/SAFETY.md](docs/SAFETY.md).

The **Home** dashboard shows your character, gold across all characters, average item level, upgrades waiting in your bags, every module's on/off switch and what's coming next.

**Two themes**, switchable in General:
- **Hawary Neon** (default): dark navy, neon cyan, the hex-H logo, rounded cards and a glow, like the Hawary's Bot dashboard.
- **Blizzard + Hawary**: Forever's own gold-trim dialog windows and buttons with Hawary accents.

Everything is also in Blizzard's own **Options → AddOns → Hawary's Addon** menu.

## Coming next

More Arabic texts · more languages · ideas from you.

What we learned from the changelogs of Leatrix, Questie, ClassicUI Forever, NaowhForever, SkillUp, BlizzMove and the Overwolf apps is in [docs/RESEARCH.md](docs/RESEARCH.md).

## Safe to use: no bannable features

Hawary's Addon follows [Blizzard's UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534) and the Midnight/Forever combat rules. See [docs/SAFETY.md](docs/SAFETY.md).
- No combat automation and no reading of hidden combat data. No one-button rotation or sequence macros.
- No advertising, no links to shops or services in-game, no donation requests. Free, open code.
- Only Blizzard's own addon API, the same calls Blizzard's UI makes. Nothing outside the game client.

## Install

1. Download this repository (green **Code** button → **Download ZIP**), or grab a release.
2. Copy the **three** folders **`HawarysAddon`**, **`HawarysAddon_QuestData`** and **`HawarysAddon_Guides`** into
   `World of Warcraft\_forever_\Interface\AddOns\`
3. Start the game (or `/reload`). Make sure **Hawary's Addon** is ticked in the AddOns list.

## Use

| Command | What it does |
|---|---|
| `/ha` | open or close the window (also `/hawary`) |
| `/ha guide` | show or hide the guide window |
| `/ha now` | what should I do next? |
| `/ha options` | Blizzard's options menu for the addon |
| `/ha journey` · `/ha gear` · `/ha bags` · `/ha qol` · `/ha general` | open a page |
| `/ha tracker` | show or hide the quest tracker |
| `/ha fly` | map pin to the nearest flight master you know |
| `/ha bis` | best-in-slot finder |
| `/ha fortune` | today's fortune |
| `/ha session` · `/ha sort` | session report · sort bags |
| `/ha stats` | print the raw stats of the item under your mouse (helps tune stat weights) |
| `/ha version` | show the version |

Minimap button: **left-click** opens the window, **right-click** opens the options, **middle-click / Shift-click** opens the button bag, **drag** moves it. Key bindings: Options → Keybindings → AddOns → Hawary's Addon.

## For developers

```
HawarysAddon/          the addon folder that goes into Interface\AddOns
  HawarysAddon.toc     load order, Interface 16001
  Locales/enUS.lua     every visible string (English base, others fall back to it)
  Core/                Util (pure helpers), Init (modules/events/saved vars), Theme (themes + widgets), UI (window, menus, minimap, toasts)
  Modules/             JourneyData (pure guide/route logic), Journey, JourneyUI, GearData (pure scoring), Gear, Bags, QoL
  Media/               logo, mark, UI shape textures, Chakra Petch font (OFL)
brand/                 logo + banner (source in tools/make_brand.py)
docs/                  API notes, safety rules, requirements
tests/run.lua          unit tests + smoke test with a mocked WoW API
tools/check.py         syntax check + "every global exists in the Forever API" check
```

```bash
luajit tests/run.lua          # unit + smoke tests
python3 tools/check.py        # Lua 5.1 syntax + Forever API globals
python3 tools/make_brand.py   # rebuild logo, textures, font and banner
python3 tools/build_arabic.py --font   # Arabic strings (locales/ar.txt) + Arabic font (needs fontTools)
```

APIs were checked against Blizzard's Forever UI source (`Gethe/wow-ui-source`, branch `forever`, build 1.60.1.70888) and the Forever API reference for build 1.60.1.70755. See [docs/API-NOTES.md](docs/API-NOTES.md).

## Credits

- **Leveling routes** converted from [Polestar](https://github.com/fitzforge/polestar) (GPLv3, © The Polestar authors) – see `HawarysAddon_Guides/CREDITS.md`.
- **Quest data** from [QuestieDB](https://github.com/Questie/QuestieDB) (copying under GPLv3 allowed by the Questie team) – see `HawarysAddon_QuestData/CREDITS.md`. Not affiliated with Questie or Polestar.

- Chakra Petch font: SIL Open Font License (`HawarysAddon/Media/OFL-ChakraPetch.txt`).
- Arabic font `HawarysArabic.ttf`: built from Noto Sans Arabic + Noto Sans (SIL Open Font License, © Google / the Noto authors), `HawarysAddon/Media/OFL-Noto.txt`.
- Feature ideas from the addons listed above. No code was copied from them.
