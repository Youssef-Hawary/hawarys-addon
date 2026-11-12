# Forever API notes (verified 2026-11-12)

## Target

| Item | Value | Evidence |
|---|---|---|
| Client | WoW Forever 1.60.1 ("Camelot" in Blizzard's code) | CurseForge game version, Blizzard UI source `version.txt` |
| TOC | `## Interface: 16001` | Community guides and the NAG Journey README. **Confirm in game:** `/dump select(4, GetBuildInfo())` |
| AddOns folder | `World of Warcraft\_forever_\Interface\AddOns` | wowforeverinfo addon guide |
| UI source pin | `Gethe/wow-ui-source` branch `forever`, commit `4cd0ab752a77164f654ccbca9d0c1fe8dafceebe`, build **1.60.1.70888** | `git clone --sparse -b forever` |
| API reference | `wow-addon-api-wowf` skill, generated from client build **1.60.1.70755** | skill `SKILL.md` |

Forever loads **Mainline** UI code with small Camelot overrides. It uses the modern bags (`ContainerFrameCombinedBags`), modern quest info (`QuestInfo_ShowRewards`, `rewardsFrame.RewardButtons`), and modern Settings. It has its own character frame **with a ranged slot** (`INVSLOT_RANGED` = 18).

## Restrictions (same client as Midnight 12.x)

- **Secret values:** in combat and restricted instances, many unit, aura, cooldown and threat values are "secret". Addons can show them but can't compare or calculate with them. Test with `issecretvalue(v)`, which the addon wraps as `ns.IsSecret`.
- **The combat log is closed** (`COMBAT_LOG_EVENT_UNFILTERED` can't be registered). Use Blizzard's damage meter, cooldown manager and encounter timeline instead.
- **Chat lockdown** applies in instances and encounters.
- Protected frames and actions are still blocked in combat. The addon defers protected work with `ns:RunOutOfCombat`.

## APIs used and how they were verified

Checked in the Forever API reference (`signatures.txt`):
`C_AddOns.GetAddOnMetadata`, `C_Container.GetContainerNumSlots / GetContainerItemInfo / GetContainerItemLink`, `C_MerchantFrame.SellAllJunkItems / GetNumJunkItems` (no restriction flags), `C_CVar.GetCVar / SetCVar`, `C_Item.GetItemInfo / GetItemInfoInstant / GetItemStats / GetDetailedItemLevelInfo / GetItemIconByID`, `C_Map.GetBestMapForUnit / GetPlayerMapPosition`, `C_SpecializationInfo.GetSpecialization / GetSpecializationInfo` (returns `specId, name, description, icon, role, primaryStat, ...`), `C_FriendList.IsFriend`, `C_BattleNet.GetAccountInfoByGUID`, `C_ClassColor.GetClassColor`, `C_Timer.After / NewTicker`, `C_UI.Reload`, `UnitClass`, `UnitLevel`, `UnitName`, `GetRealmName`, `GetMoney`, `GetCursorPosition`, `issecretvalue`, and the events `MERCHANT_SHOW, LOOT_READY(autoloot), PARTY_INVITE_REQUEST(... inviterGUID), DUEL_REQUESTED, QUEST_DETAIL, QUEST_COMPLETE, BAG_UPDATE_DELAYED, BANKFRAME_OPENED/CLOSED, PLAYERBANKSLOTS_CHANGED, PLAYER_EQUIPMENT_CHANGED, PLAYER_MONEY, PLAYER_LEVEL_UP, PLAYER_SPECIALIZATION_CHANGED, GET_ITEM_INFO_RECEIVED`.

Legacy globals not in the generated docs, verified because Blizzard's own Forever UI code calls them:
`RepairAllItems`, `GetRepairAllCost`, `CanMerchantRepair`, `CanGuildBankRepair` (StaticPopup/Merchant), `LootSlot`, `GetNumLootItems` (LootFrame), `GetNumQuestChoices`, `GetQuestItemLink`, `GetQuestItemInfo` (QuestInfo), `GetInventoryItemLink`, `GetInventoryItemID` (PaperDoll), `AcceptGroup`, `IsGuildMember`, `CancelDuel` (GameDialogDefs).

FrameXML (Forever source):
- `TooltipDataProcessor.AddTooltipPostCall` (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua) and `TooltipUtil.GetDisplayedItem`.
- `Settings.RegisterVerticalLayoutCategory / RegisterVerticalLayoutSubcategory / RegisterProxySetting / CreateCheckbox / CreateSlider / CreateDropdown / CreateControlTextContainer / RegisterAddOnCategory / OpenToCategory`, `Settings.VarType = {Boolean, String, Number}`, `CreateSettingsButtonInitializer`, `CreateSettingsListSectionHeaderInitializer`.
- `MinimalSliderWithSteppersMixin:Init(value, min, max, steps, formatters)` with `.Event.OnValueChanged` and `.Label.Right`.
- `DropdownButton` + `WowStyle1DropdownTemplate`, `:SetupMenu(fn(owner, root))` and `root:CreateRadio(text, isSelected, setSelected, data)`.
- `ScrollFrameTemplate` creates `self.ScrollBar` itself.
- `DialogBorderTranslucentTemplate`, `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `UIPanelCloseButton` (the native theme).
- `ContainerFrameMixin:UpdateItems`, `:EnumerateValidItems()`, `itemButton:GetBagID()`. These are hooked with `hooksecurefunc` (display only; Blizzard's code is never called).
- `QuestInfo_ShowRewards`, `QuestInfoFrame.rewardsFrame.RewardButtons[i]` (`.type == "choice"`, `:GetID()`), `QuestInfoItem_OnClick`.
- Texture `SetTextureSliceMargins` + `Enum.UITextureSliceMode.Stretched` (9-slice rounded shapes), `SetGradient`, `SetRotation`.
- `Enum.BagIndex`: Backpack 0, Bag_1..4, ReagentBag 5, CharacterBankTab_1..9 = 6..14.

Secure handlers were looked at for the sequence-macro idea, but **aren't used**, because that idea was dropped for safety (see SAFETY.md).

## Still to confirm in game

- `select(4, GetBuildInfo())` prints `16001`.
- `C_Item.GetItemStats` key names on Forever items. Run `/ha stats` on a few items and adjust `Modules/GearData.lua`.
- Rounded 9-slice textures render as expected. Both themes, all pages.
