# Changelog

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
