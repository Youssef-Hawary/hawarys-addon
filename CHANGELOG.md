# Changelog

## 1.0.0 (2026-11-12)

- **Leveling routes 1-60** for Alliance and Horde (146 guides, 11,433 steps, converted from Polestar, GPLv3): pick faction, race and class → *Start my route*; finished steps are skipped, race/class steps filtered, next zone chains in automatically; sections and tips shown in the guide window.
- **Quests** (Questie-style, data from QuestieDB): quest givers, turn-ins, every objective spot and hidden objectives on the world map and minimap; quest lines in mob, object and item tooltips; prerequisites, race/class, profession and level rules; uses an installed QuestieDB when present.
- **Smart Route**: Auto Journey adds the nearest quests you can pick up and points the arrow at the nearest objective spot.
- **Trainer Planner** and **Macro Helper** with a macro generator (Blizzard macros only).
- **Scrolling fixed**: the menu scrolls (mouse wheel) and every page has a reliable mouse-wheel handler; window slightly larger.
- Two new load-on-demand folders: `HawarysAddon_QuestData`, `HawarysAddon_Guides`.
- Tests: 38.

## 0.4.0 (2026-11-12) – Phase 4: Dungeons, Discovery, What now?, Journey Diary

- **Dungeons:**
  - An **Adventure Planner** built from Blizzard's own Group Finder activities (name, minimum and suggested levels, group size), grouped into "Right for your level", "Coming up" and optionally "Below your level". Forever has no Encounter Journal, so this is the real data source.
  - A **dungeon log** of runs, time, bosses killed and your best time per dungeon.
- **Discovery:**
  - Your own **world-map layer**, using Blizzard's map data provider and pin system.
  - **Rare alerts** with an optional sound, when you target, mouse over (out of combat) or see a rare on the minimap.
  - **Herbs, ore and chests** are remembered when you gather or open them, with nearby repeats merged. Forever blocks reading minimap dots, so we don't.
- **What now?** A Home card and `/ha now` rank your next move: repair, bag space, an upgrade to equip, turn-ins, trainer, a dungeon for your level, the shopping list, rested XP.
- **Journey Diary:** a timeline of level-ups, dungeon clears, epics, rares, gold milestones and every 100 quests. **Optional screenshots** (off by default).
- Tests: 33 (planner, sightings, What-now priorities, gold milestones, plus a smoke run of dungeon, rare, gathering, What-now and diary).

## 0.3.0 (2026-11-12) – Phase 3: Professions, Market, Alts & Gold

- **Professions:**
  - Profession ranks with bars.
  - A recipe snapshot read while your own profession window is open (never NPC, guild or linked windows).
  - **Most profitable recipes** using Market prices. Unknown prices show "?", never free.
  - A **shopping list** checked against every character's bags and bank, with the cost of what's still missing, and reagent tooltips showing have / need.
- **Market:**
  - Remembers auction house prices from browsing, commodity searches and item searches.
  - **Hawary Scan** button for a full scan (once per 15 minutes, read in chunks).
  - The AH price and its age appear in tooltips.
  - Prices are kept per auction house.
  - Never buys, bids, posts or cancels.
- **Alts & Gold:**
  - All characters with level, item level, gold, professions and last login. Shift-click to forget a deleted character.
  - Gold chart (7–90 days, hover for each day).
  - **Item search across all characters.**
- Tests: 28 (price math, unknown-price rule, shopping list, gold series, search, plus auction house, profession and alts smoke tests).

## 0.2.0 (2026-11-12) – Phase 2: Journey & Guide

- **Journey & Guide** module (Zygor / RestedXP / Questie / NAG Journey style):
  - Floating **guide window**: the current step with its objectives (✓ when done), the next 2 steps, a progress bar, and Back and Next/Skip buttons. It can be collapsed and dragged, and supports both themes.
  - Big **direction arrow** with distance, which turns green when you're close.
  - **Blizzard's own map pin and in-world marker** for the current step (super-tracking and user waypoint).
  - **Auto Journey**: a route from your own quest log with Blizzard's quest positions. Turn-ins come first, then the nearest objectives, and too-hard quests go last.
  - **Step guides**: import, use, restart and delete. Steps finish by themselves (accept, complete, turn in, level, arrive). See docs/GUIDE-FORMAT.md.
  - **Session stats** (an Overwolf idea): XP/hour and time to level in the window, plus an XP/hour tile on Home.
  - Level-up notice with a trainer reminder.
  - Optional quest automation: off by default, Shift pauses it, never in combat, never with several rewards or a gold cost.
- `/ha guide` shows or hides the guide window.
- A module that errors 5 times in a session pauses itself (a lesson from ClassicUI Forever).
- docs/RESEARCH.md: what we learned from other Forever addons' changelogs and Overwolf. docs/GUIDE-FORMAT.md.
- Tests: 23 (guide parser, step rules, route order, arrow math, session rates, journey smoke and automation guards).

## 0.1.0 (2026-11-12) – Phase 1

First version for WoW Forever (Interface 16001).

- **Hawary's Addon** branding: hex-H logo (from Hawary's Bot), Chakra Petch titles, minimap button, addon-compartment entry, welcome card.
- **Two themes:** Hawary Neon (rounded navy cards, cyan glow, animated switches) and Blizzard + Hawary (Forever's native dialog frames and buttons).
- **Main window** (`/ha`): Home dashboard (character, gold across characters, average item level, upgrades in bags, module switches, roadmap) plus a page per module.
- **Blizzard options menu:** Options → AddOns → Hawary's Addon, with a sub-page per module.
- **Gear & Upgrades:** class/spec stat weights, upgrade % in tooltips, item level and ID, green arrows on bag upgrades, best quest reward marked (optional pre-select), upgrade-looted notices, `/ha stats`.
- **Bags:** item counts per character (bags / bank / worn) in tooltips, gold total.
- **Quality of Life:** auto repair (guild funds optional), sell junk, instant loot, accept invites from friends/guild, decline duels, max camera distance, coordinates, movable Blizzard windows.
- **Safety:** GSE-style sequence macros were researched and **dropped**, since they're not clearly allowed. See docs/SAFETY.md.
- Dev: unit and smoke tests (`luajit tests/run.lua`), Forever API global check (`tools/check.py`).
