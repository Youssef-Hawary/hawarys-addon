# Safety rules: nothing bannable

Researched 2026-11-12. Hawary's Addon must never contain anything that could get a player banned or break Blizzard's rules. **Every new feature is checked against this page before it's added.**

## Blizzard's rules we follow

**[UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534)** (8 rules):

| # | Rule | How we comply |
|---|---|---|
| 1 | Add-ons must be free of charge | Free, GPL-3. No premium version, no paid features or services. |
| 2 | Code must be completely visible, not obfuscated | Plain Lua on GitHub. No minifying or encoding. |
| 3 | No negative impact on realms or other players (chat spam, disk loading, FPS) | Messages print only to **your own** chat frame. Nothing is sent to other players. Bag scans run on Blizzard's batched `BAG_UPDATE_DELAYED`, and the coordinates timer runs only while that feature is on. |
| 4 | **No advertisements of any goods or services** | The Hawary name and logo appear as the addon's identity only. **No store, phone, boosting, sales or service text or links in-game.** The only URL is the source-code link in the TOC. |
| 5 | No donation requests in-game | None. |
| 6 | Nothing offensive (ESRB T) | Fine. |
| 7 | Follow the Terms of Use and EULA | See below. |
| 8 | Blizzard can disable any add-on function | We use only the official API and handle missing APIs gracefully. |

**[Blizzard EULA](https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/)**, the "Cheating" section, forbids bots ("automated control of a Game"), hacks and exploits.
→ The addon runs only inside the game's own addon sandbox. It doesn't press keys, move the character, read memory or run outside the client.

**Midnight / Forever combat rules** ([Blizzard: "Combat Philosophy and Addon Disarmament in Midnight"](https://news.blizzard.com/en-us/article/24246290), [how Midnight changes affect combat addons](https://worldofwarcraft.blizzard.com/news/24244638)): "Addons should not be able to automate combat decisions for the player."
→ No module reads combat state (secret values) to decide anything. QoL actions never run in combat.

## Removed or never-built features

| Feature | Decision | Why |
|---|---|---|
| GSE-style sequence macros (each press casts the next spell) | **Removed** (2026-11-12) | No official Blizzard ruling. Forum opinions conflict and some players report bans. It sits on the "no combat automation" line. Blizzard ships its own One-Button Rotation and Assisted Highlight instead. Replaced on the roadmap by a **Macro Helper** that only edits normal Blizzard macros. |
| Damage meter / combat-log boss mods / WeakAuras-style combat math | Not built | The combat log is closed to addons in Forever, and Blizzard has its own meter, cooldown manager and boss warnings. |
| Anything that sends chat or whispers to other players automatically | Not built | Policy rule 3 (spam), plus chat lockdown in instances. |
| In-game ads for Hawary's store, services or socials | Never | Policy rule 4. |

## Features kept (long-standing, allowed patterns)

These are the same things Leatrix Plus, Questie and Baganator have done for years with Blizzard's own API. Each one is a single action that Blizzard's UI also performs from a button. None of them run in combat.

- Auto repair, sell junk (Blizzard's own "sell all junk" call), instant loot (only when the game already decided to auto-loot)
- Accept group invites from friends and guild only, decline duels
- Max camera distance (a normal client setting, restored when turned off)
- Coordinates (hidden where the game doesn't share your position), drag Blizzard windows (only frames that aren't protected, never in combat)
- Tooltip lines, bag arrows, quest reward marking (read-only display). Pre-selecting a reward is optional and off by default, and **you still click Complete yourself**.
- Journey guide window, arrow and Blizzard map pin: display only. It uses Blizzard's own super-tracking and user waypoint, which the map UI itself offers.
- **Quest auto accept / turn-in** (Journey): the same feature Questie, Polestar Guides and Leatrix Plus ship. It's **off by default**, works only after **you** talk to the NPC, is paused while **Shift** is held, never runs in combat, never picks between several rewards and never pays gold for you.

- Market reads auction results you already see (browse and search), plus one full scan when **you** click Scan (Blizzard's own limit is once per 15 minutes). It **never buys, bids, posts or cancels**. Professions only reads your own recipe list while you have it open and **never crafts**.

- Discovery only reads what **you** see: your target or mouseover (never in combat), rares Blizzard already shows on your minimap, and your own gathering casts. It never scans nameplates and never reads minimap herb or ore dots, which Forever blocks. Map pins use Blizzard's official data provider and pin system.
- Journey Diary's screenshots are **off by default**, and they're only taken at milestones.

## Never-build list (lessons from other addons' changelogs, see RESEARCH.md)
Layer detection (Blizzard obfuscated GUIDs to stop it), reading minimap herb or ore dots (blocked in Forever), raid marks, chat or emote sends or crafting from code without a click, auto-confirming enchant-replace popups, telemetry that's on by default, paid or premium features.

## Checklist for every new feature

1. Does it make a decision in combat, or read combat data? → **Don't build it.**
2. Does it do more than one game action per hardware key press, or act without you? → **Don't build it.**
3. Does it send anything to other players or to chat channels? → Only if the player clicks to send it, and never automatically.
4. Does it show a shop, service, social link or donation request? → **Never.**
5. Does it use only APIs listed in the Forever API reference or used by Blizzard's own UI? → `python3 tools/check.py` must pass.
