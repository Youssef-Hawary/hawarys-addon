# Changelog

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
