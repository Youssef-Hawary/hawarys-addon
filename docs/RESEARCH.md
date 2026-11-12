# What we learned from other Forever addons (2026-11-12)

We read changelogs, release notes and update notes from the main WoW Forever addons, plus Blizzard's Forever dev notes. No code was copied; these are lessons and ideas only.

## Platform (Blizzard)
- **Forever = Midnight 12.1.5 APIs.** "WoW Forever shares Mainline WoW's UI architecture, including the vast majority of APIs available in 12.1.5", and the Midnight addon rules (secrets) apply ([Warcraft Wiki: Patch 1.60.1/API changes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes)).
- TOC suffix `_Forever.toc` is an alias of `_Camelot`. The project ID is `WOW_PROJECT_CAMELOT` (18).
- Beta changes:
  - Creature GUIDs were obfuscated **to stop layer detection**.
  - `SendChatMessage("EMOTE")` needs a hardware event.
  - Unit frames and the minimap were reskinned.
  - Bags no longer auto-equip into bag slots.
  - The Cooldown Manager is off by default.
  - The Auction House changes moved to Nov 17.
- New APIs worth using later:
  - `C_GameRules.IsHardcoreActive`, `C_GameRules.IsSelfFoundAllowed`
  - `C_QuestLog.GetQuestTimers / GetTrivialRange / IsEliteQuest`
  - `C_SkillInfo.*`, `C_SwingTimer.*`, `C_CVar.SetTempCVar`

## Lessons we applied
| Lesson | From | In Hawary's Addon |
|---|---|---|
| Stop a module after repeated errors instead of spamming | ClassicUI Forever | Init: 5 errors in a session pauses the module |
| Secrets can appear in tooltips, chat names and GUIDs. Check before using | Questie, Leatrix, Naowh, Bagnon | `ns.IsSecret` on every link, name, GUID, XP and position |
| Never run addon code inside Blizzard's update passes in combat | ClassicUI, SkillUp | Display-only `hooksecurefunc`. Protected work waits for `ns:RunOutOfCombat` |
| Don't re-apply CVars on every reload | ClassicUI | Camera CVar saves the old value and restores it once |
| Quest auto accept/turn-in: separate toggles, a modifier to override | Questie, Polestar, Leatrix | Off by default, Shift pauses, never in combat, never with several rewards or a gold cost |
| Never auto-equip, buy or craft for the player | GearQuest, ForeverProfit | Gear only shows. The reward pick is a mark, and pre-select is optional |
| Load big data per class or on demand | GearQuest (1.3 GB → 200–400 MB) | Planned for the Dungeons and Discovery data |
| Forever has its own frames (Social, LegacySystem). Mover lists need per-flavor names | BlizzMove, ClassicUI | QoL only moves frames that exist and aren't protected |
| Trainers in Forever use training points | Leatrix (1.60.05) | Talents & Training will account for it |
| Reading minimap herb/ore dots is blocked | NaowhForever 1.2.16 | Discovery will record nodes **when you gather them** instead |

## Avoid list (from these changelogs)
- Layer detection by GUIDs. Blizzard obfuscated GUIDs specifically to stop it.
- Raid marks, chat or emote sends, or crafting from addon code without a click.
- Auto-confirming enchant-replace popups.
- Telemetry that's on by default.
- Any "premium" or paid-only feature.
- In-game ads.

## Overwolf (desktop overlay apps)
The Overwolf WoW Forever apps (for example the WoW Forever Companion) show interactive maps, an item database, a dungeon browser, profession lookups, an adventure planner and a character snapshot. They run outside the game with ads. What fits safely inside an addon:
- **Session stats**: XP/hour and time to level, now in the Journey window and on Home.
- **Item compare** and "who can use it": Gear.
- **Character snapshot**: Bags (professions come later).
- **Adventure planner** (dungeons for your level): planned in Dungeons.
- **Own map layer** (rares, herbs, ore you found): planned in Discovery.

## Sources
- Warcraft Wiki: Patch 1.60.1/API changes. Blizzard forums: Forever beta development notes. wowforeverinfo patch notes.
- Changelogs: Leatrix Plus 1.60.x and Leatrix Maps 1.60.x (CurseForge); Questie releases (GitHub); ClassicUI Forever CHANGELOG; NaowhForever CHANGELOG; SkillUp Forever CHANGELOG; BlizzMove and MoveAny releases; Baganator and Bagnon files; GearQuest Forever, Polestar Guides, ForeverProfit, Auctionator and Pawn pages.
- Overwolf: WoW Forever Companion app page.
- Some items were seen only in search results (Zygor, RestedXP, Journey, Attune, Talents Forever, What's Training, RareScanner, GatherMate2). Those are marked unverified in our notes.
