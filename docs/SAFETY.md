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
| Combat-log boss mods / WeakAuras-style combat math | Not built | The combat log is closed to addons in Forever, and Blizzard has its own cooldown manager and boss warnings. (The DPS Meter added in 1.3.0 does **not** read the combat log: see below.) |
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

- Quests, routes, Trainer Planner and Macro Helper are display/advice only. Macros are normal Blizzard macros created by your click; the trainer is never bought from automatically.

- **1.2.0 additions:**
  - Quest Tracker+, nameplate quest icons, party-on-quest, BiS finder, bag categories, flight-path finder and Auction Watch are **display only**.
    - Nameplate icons read only who an NPC is, and skip units the game hides (secret values, e.g. in instances).
    - Auction Watch **never cancels or reposts**. It only asks for your own auction list (the same request Blizzard's Auctions tab makes).
  - **Equipment sets:** one set per click (Blizzard's own equipment manager), never in combat.
  - **Junk list:** each click on "Sell junk" sells **one** stack at an open merchant (the same as right-clicking it yourself), never in combat, never automatic.
  - **Minimap Button Bag** only moves other *addons'* buttons. **Profiles** only change Hawary settings. **Controller support** only marks Hawary's own buttons for Blizzard's gamepad navigation and adds normal key bindings.
- **For Fun** (Skins, Fashion Studio, Fun Stats & Badges, Hex Hop, Fun Moments):
  - **Skins** recolor Hawary's own windows only.
  - **Fashion Studio** dresses a *preview model* (like Blizzard's dressing room). Your real gear and the game files never change.
  - The jump counter is a post-hook: it counts after the game handled the key and can't change or block anything.
  - The AFK show is our own screen: it doesn't spin the camera and hides in combat.
  - Death roasts and fortunes print only to **your** chat frame. Nothing is ever sent to other players.

## "Skin changers" for other games

Asked on 2026-11-12: a Valorant / League of Legends style **skin changer** will **never** be built. Those tools edit game files or memory behind the game's anti-cheat (Riot Vanguard) and get accounts banned. They're also impossible from inside a WoW addon. The safe alternatives are Hawary's own Skins and the Fashion Studio preview.

## Never-build list (lessons from other addons' changelogs, see RESEARCH.md)
Layer detection (Blizzard obfuscated GUIDs to stop it), skin changers or model swaps that modify game files, reading minimap herb or ore dots (blocked in Forever), raid marks, chat or emote sends or crafting from code without a click, auto-confirming enchant-replace popups, telemetry that's on by default, paid or premium features.

## Checklist for every new feature

1. Does it make a decision in combat, or read combat data? → **Don't build it.**
2. Does it do more than one game action per hardware key press, or act without you? → **Don't build it.**
3. Does it send anything to other players or to chat channels? → Only if the player clicks to send it, and never automatically.
4. Does it show a shop, service, social link or donation request? → **Never.**
5. Does it use only APIs listed in the Forever API reference or used by Blizzard's own UI? → `python3 tools/check.py` must pass.

- **1.3.0 additions** (Pawn, Bagnon, Auctionator, Details!/Skada and OpenMap-style features, written from scratch; their code is not copied):
  - **DPS Meter** shows only **Blizzard's own damage meter data** (`C_DamageMeter`, the numbers the built-in meter shows). It never reads the combat log and never decides anything. In combat those numbers are secret, so the code only passes them to the game's own text and bar functions and never compares them or does math on them. Spell breakdowns and **Report** work only out of combat. Report posts the top 5 to your group (or /say) **only when you click it**.
  - **Auction House+** buys, posts and cancels **only when you click**, one action per click, exactly like Auctionator, which Blizzard allows:
    - A commodity purchase takes two clicks: the first asks the server for the price, the second confirms.
    - An item purchase takes two clicks: select the auction, then confirm.
    - Searches run one at a time, the throttle Blizzard sets.
    - It never loops, never auto-buys and never reposts by itself.
    - A price floor (the vendor price and a percent of the market price) stops posts that are too cheap by mistake.
  - **Bag Window** uses Blizzard's own bag item buttons, so using, dragging and selling items is your own click. **Sort** runs Blizzard's own sort when you click it, never in combat. Hiding Blizzard's bag frames and moving our slots happens only out of combat.
  - **Map+** only moves, scales and fades Blizzard's world map (out of combat), adds a search and a "Find me" button, and adds mouse-wheel zoom to the minimap. When the OpenMap addon is loaded, Map+ leaves the world map alone.
  - **Pawn scales** are display only: imported stat weights change the upgrade arrows and tooltips, and nothing is equipped for you.

