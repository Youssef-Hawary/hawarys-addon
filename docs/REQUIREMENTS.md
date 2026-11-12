# Requirements & progress

Target: **WoW Forever** only (Interface 16001). Owner: Hawary. Testing: in game on the Windows PC (BugSack for errors). Mock-up choice: "implement directly" (2026-11-12). Theme choice: both themes, switchable, Neon by default.

Status: ✅ done (static checks + mocked tests pass; **in-game check not run yet**) · 🔜 planned · ❌ dropped

| ID | Requirement | Status | Where | Acceptance |
|---|---|---|---|---|
| R1 | One addon, branded **Hawary's Addon**, with the Hawary's Bot hex-H logo | ✅ | TOC, Media/logo.tga, Theme header | Logo in the AddOns list and minimap menu; window header shows HAWARY'S ADDON |
| R2 | Two themes: Hawary Neon and Blizzard + Hawary | ✅ | Core/Theme.lua | Switch in General → reload → every page renders in the chosen theme |
| R3 | Options in Blizzard's AddOns menu plus our own window | ✅ | Core/UI.lua | Options → AddOns → Hawary's Addon has every setting; a change in one place shows in the other |
| R4 | All text localizable (English base) | ✅ | Locales/enUS.lua | No hardcoded UI text outside the catalog (except proper names) |
| R5 | Nothing bannable | ✅ | docs/SAFETY.md | Checklist passes for every feature |
| R6 | Gear upgrades in tooltips + bag arrows + item level/ID | ✅ | Modules/Gear*.lua | Hover gear: % vs equipped; bag upgrades get a green arrow |
| R7 | Best quest reward marked (optional pre-select) | ✅ | Modules/Gear.lua | Quest with 2+ choices: one is marked "HAWARY PICK" |
| R8 | Item counts across characters + total gold | ✅ | Modules/Bags.lua | Log in on 2 characters; tooltip lists both |
| R9 | QoL: repair, junk, loot, invites, duels, camera, coords, move windows | ✅ | Modules/QoL.lua | Each toggle does its job and does nothing when off |
| R10 | Home dashboard (character, gold, ilvl, upgrades, modules, roadmap) | ✅ | Core/UI.lua | `/ha` opens Home with live numbers |
| R11 | Journey & Guide (Zygor/RestedXP/Questie/NAG style) | 🔜 Phase 2 | | |
| R12 | Talents & Training | 🔜 Phase 2 | | |
| R13 | Professions, Market, Alts | 🔜 Phase 3 | | |
| R14 | Dungeons, Discovery, "What now?", Journey Diary | 🔜 Phase 4 | | |
| R15 | Macro Helper (normal Blizzard macros only) | 🔜 | | |
| R16 | GSE-style sequence macros | ❌ dropped for safety | docs/SAFETY.md | |
| R17 | Controller support for the window | 🔜 | | Not assessed yet. Mouse and keyboard only for now |

## Checkpoint (2026-11-12)

- Phase 1 code complete: Core (Util, Init, Theme, UI) and modules Gear, Bags, QoL.
- `luajit tests/run.lua` → 16 passed. `python3 tools/check.py` → PASS (every global exists in Forever).
- **Not run:** in-game load, visual check of both themes, real item stat keys (`/ha stats`).
- Next: in-game test round on the PC → fix → Phase 2 (Journey & Guide).
