# Hawary's Addon guide format

Guides are plain text: one step per line. Paste one in game with **/ha journey → Import guide**. Steps tick themselves off as you play (quest accepted, finished or turned in; level reached; place reached). Steps that can't be detected (`train`, `hearth`, `fly`, `note`) are ticked off with **Next**.

> The example below only shows the **format**. Its quest IDs and coordinates are placeholders and haven't been checked against WoW Forever.

```text
# Lines starting with # are comments.
guide: Example Valley 1-10     # the guide's name (shown in the window)
level: 1-10                    # optional level range
map: 1429                      # optional default map ID for coordinates

accept 1234 Wolves at the Farm @ 48.2 42.9
complete 1234
turnin 1234
goto 52.1 45.0 The abbey
goto 41.6 65.5 The inn map=1429
level 6 Grind wolves to level 6
train
hearth The inn
fly The capital
note Buy bigger bags from the vendor
```

| Step | Written as | Done when |
|---|---|---|
| `accept` | `accept <questID> [name] [@ x y]` | the quest is in your log (or already turned in) |
| `complete` | `complete <questID> [text]` | the quest's objectives are finished |
| `turnin` | `turnin <questID> [name] [@ x y]` | the quest is turned in |
| `goto` | `goto <x> <y> [label] [map=ID]` | you are within 12 yards |
| `level` | `level <n> [text]` | you reach level n |
| `train` / `hearth` / `fly` / `note` | `<step> [text]` | you click **Next** |

- Coordinates are map percentages (0–100), like the ones under your minimap. They can be written `48.2 42.9` or `48.2,42.9`.
- `@ x y` and `map=ID` work on any step. The map ID defaults to the guide's `map:`, otherwise your current map. `/dump C_Map.GetBestMapForUnit("player")` shows the ID of the map you're on.
- Quest names are optional. Without one, the window shows the quest's real name from the game.
- **Quest IDs and coordinates must be real.** Check them in game before sharing a guide.

**Auto Journey** needs no guide at all. It builds the route from your own quest log with Blizzard's quest positions: finished quests first, then the nearest objectives.
