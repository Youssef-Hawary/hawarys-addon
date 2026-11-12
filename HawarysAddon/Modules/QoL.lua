-- Hawary's Addon: Quality of Life (Leatrix Plus / Leatrix Maps / BlizzMove style helpers)
-- Rules kept here: nothing runs in combat, nothing sends chat to other players, nothing
-- automates gameplay. Every action is one Blizzard's own UI performs with a button.
local _, ns = ...
local L, U, T = ns.L, ns.Util, ns.Theme

local QoL = ns:NewModule("qol", {
    title = L.MOD_QOL,
    desc = L.MOD_QOL_DESC,
    order = 3,
    defaults = {
        repair = true, repairGuild = false, sellJunk = true, fastLoot = false,
        invites = false, duels = false, camera = false, coords = true, move = true,
        cameraOld = "",
    },
})

QoL.options = {
    { type = "toggle", key = "repair", label = L.QOL_REPAIR, desc = L.QOL_REPAIR_DESC },
    { type = "toggle", key = "repairGuild", label = L.QOL_REPAIR_GUILD, desc = L.QOL_REPAIR_GUILD_DESC, parent = "repair" },
    { type = "toggle", key = "sellJunk", label = L.QOL_SELLJUNK, desc = L.QOL_SELLJUNK_DESC },
    { type = "toggle", key = "fastLoot", label = L.QOL_FASTLOOT, desc = L.QOL_FASTLOOT_DESC },
    { type = "toggle", key = "invites", label = L.QOL_INVITES, desc = L.QOL_INVITES_DESC },
    { type = "toggle", key = "duels", label = L.QOL_DUELS, desc = L.QOL_DUELS_DESC },
    { type = "toggle", key = "camera", label = L.QOL_CAMERA, desc = L.QOL_CAMERA_DESC },
    { type = "toggle", key = "coords", label = L.QOL_COORDS, desc = L.QOL_COORDS_DESC },
    { type = "toggle", key = "move", label = L.QOL_MOVE, desc = L.QOL_MOVE_DESC },
}

---------------------------------------------------------------------------
-- Vendor: repair + sell junk
---------------------------------------------------------------------------
local REPAIR_ICON = "Interface\\Icons\\Trade_BlackSmithing"

function QoL:Repair()
    if not (CanMerchantRepair and CanMerchantRepair()) then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end
    if self:Get("repairGuild") and CanGuildBankRepair and CanGuildBankRepair() then
        RepairAllItems(true)
        C_Timer.After(0.4, function()
            local left = GetRepairAllCost()
            if left and left > 0 then
                if GetMoney() >= left then
                    RepairAllItems(false)
                    ns:Toast(L.MOD_QOL, L.QOL_REPAIRED:format(U.money(left)), REPAIR_ICON)
                end
            else
                ns:Toast(L.MOD_QOL, L.QOL_REPAIRED_GUILD:format(U.money(cost)), REPAIR_ICON)
            end
        end)
    elseif GetMoney() >= cost then
        RepairAllItems(false)
        ns:Toast(L.MOD_QOL, L.QOL_REPAIRED:format(U.money(cost)), REPAIR_ICON)
    end
end

function QoL:SellJunk()
    if not (C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and C_MerchantFrame.GetNumJunkItems) then return end
    if C_MerchantFrame.GetNumJunkItems() == 0 then return end
    local count, value = 0, 0
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                local sell = select(11, C_Item.GetItemInfo(info.itemID)) or 0
                count = count + 1
                value = value + sell * (info.stackCount or 1)
            end
        end
    end
    C_MerchantFrame.SellAllJunkItems() -- the same call as Blizzard's own "Sell all junk" button
    if count > 0 then
        ns:Toast(L.MOD_QOL, L.QOL_SOLD:format(count, U.money(value)), "Interface\\Icons\\INV_Misc_Coin_02")
    end
end

---------------------------------------------------------------------------
-- Loot, invites, duels
---------------------------------------------------------------------------
function QoL:FastLoot(_, autoloot)
    -- Only when the game itself decided this loot is auto-looted (auto loot setting / modifier).
    if not autoloot then return end
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end

local function IsTrustedInviter(guid)
    if not guid or ns.IsSecret(guid) then return false end
    if C_FriendList.IsFriend(guid) then return true end
    if IsGuildMember and IsGuildMember(guid) then return true end
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid) then return true end
    return false
end

function QoL:OnInvite(_, name, _, _, _, _, _, inviterGUID)
    if ns.InCombat() then return end
    if not IsTrustedInviter(inviterGUID) then return end
    AcceptGroup()
    StaticPopup_Hide("PARTY_INVITE")
    if name and not ns.IsSecret(name) then ns:Print(L.QOL_INVITE_ACCEPTED, name) end
end

function QoL:OnDuel(_, name)
    if CancelDuel then CancelDuel() end
    StaticPopup_Hide("DUEL_REQUESTED")
    if name and not ns.IsSecret(name) then ns:Print(L.QOL_DUEL_DECLINED, name) end
end

---------------------------------------------------------------------------
-- Camera distance (a normal client setting; the old value is restored when turned off)
---------------------------------------------------------------------------
local CAMERA_CVAR = "cameraDistanceMaxZoomFactor"

function QoL:ApplyCamera()
    local current = C_CVar.GetCVar(CAMERA_CVAR)
    if not current then return end
    if self.enabled and self:Get("camera") then
        if self:Get("cameraOld") == "" then self:DB().cameraOld = current end
        C_CVar.SetCVar(CAMERA_CVAR, "2.6")
    elseif self:Get("cameraOld") ~= "" then
        C_CVar.SetCVar(CAMERA_CVAR, self:Get("cameraOld"))
        self:DB().cameraOld = ""
    end
end

---------------------------------------------------------------------------
-- Coordinates (minimap + world map). Hidden where the game gives no position.
---------------------------------------------------------------------------
local coordsMini, coordsMap, ticker

local function PlayerXY()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or ns.IsSecret(x) or (x == 0 and y == 0) then return nil end
    return x * 100, y * 100
end

local function Pill(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 18)
    f.bg = T.Shape(f, "pill", { 0.067, 0.082, 0.11, 0.85 }, "BACKGROUND")
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFontObject(T.font("h2"))
    f.text:SetPoint("CENTER", 0, 0)
    f.text:SetTextColor(0.22, 0.78, 0.96)
    return f
end

function QoL:UpdateCoords()
    local x, y = PlayerXY()
    local text = x and string.format("%.1f, %.1f", x, y) or nil
    if coordsMini then
        coordsMini:SetShown(text ~= nil)
        if text then coordsMini.text:SetText(text) end
    end
    if coordsMap and WorldMapFrame and WorldMapFrame:IsShown() then
        local parts = {}
        if text then parts[#parts + 1] = "|cff38c6f4" .. (UnitName("player") or "") .. "|r  " .. text end
        local sc = WorldMapFrame.ScrollContainer
        if sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver() then
            local cx, cy = sc:GetNormalizedCursorPosition()
            if cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                parts[#parts + 1] = "|cffaeb7c7Cursor|r  " .. string.format("%.1f, %.1f", cx * 100, cy * 100)
            end
        end
        coordsMap.text:SetText(table.concat(parts, "     "))
        coordsMap:SetShown(#parts > 0)
    end
end

function QoL:ApplyCoords()
    local on = self.enabled and self:Get("coords")
    if on then
        if not coordsMini then
            coordsMini = Pill(Minimap, 86)
            coordsMini:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
        end
        if not coordsMap and WorldMapFrame then
            local anchor = WorldMapFrame.ScrollContainer or WorldMapFrame
            coordsMap = Pill(anchor, 360)
            coordsMap:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 6)
            coordsMap:SetFrameLevel(anchor:GetFrameLevel() + 20)
        end
        if not ticker then
            ticker = C_Timer.NewTicker(0.2, function() ns.Safe(QoL.UpdateCoords, QoL) end)
        end
    else
        if ticker then ticker:Cancel(); ticker = nil end
        if coordsMini then coordsMini:Hide() end
        if coordsMap then coordsMap:Hide() end
    end
end

---------------------------------------------------------------------------
-- Move Blizzard windows (only frames that aren't protected, never in combat)
---------------------------------------------------------------------------
local MOVABLE = {
    "CharacterFrame", "QuestFrame", "GossipFrame", "MerchantFrame", "MailFrame", "FriendsFrame",
    "SpellBookFrame", "PlayerSpellsFrame", "TradeFrame", "BankFrame", "DressUpFrame", "TaxiFrame",
    "PVEFrame", "QuestLogFrame", "ItemTextFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame",
    -- load-on-demand windows (hooked when their addon loads)
    "ClassTrainerFrame", "AuctionHouseFrame", "ProfessionsFrame", "TradeSkillFrame", "MacroFrame",
    "AchievementFrame", "InspectFrame", "CommunitiesFrame", "CollectionsJournal", "EncounterJournal",
    "ClassTalentFrame", "TalentFrame", "ItemSocketingFrame", "ItemUpgradeFrame",
}

local function MakeMovable(frame)
    if not frame or frame.HawarysMovable or frame:IsProtected() then return end
    frame.HawarysMovable = true
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and QoL.enabled and QoL:Get("move") and not ns.InCombat() then
            self.hawarysMoving = true
            self:StartMoving()
        end
    end)
    frame:HookScript("OnMouseUp", function(self)
        if self.hawarysMoving then
            self.hawarysMoving = false
            self:StopMovingOrSizing()
            self:SetUserPlaced(false) -- don't save into Blizzard's layout cache
        end
    end)
end

function QoL:HookMovables()
    for _, name in ipairs(MOVABLE) do
        local f = _G[name]
        if f then ns.Safe(MakeMovable, f) end
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function QoL:OnMerchant()
    if self:Get("sellJunk") then ns.Safe(self.SellJunk, self) end
    if self:Get("repair") then ns.Safe(self.Repair, self) end
end

function QoL:ApplyEvents()
    self:UnregisterAllEvents()
    self:RegisterEvent("MERCHANT_SHOW", "OnMerchant")
    if self:Get("fastLoot") then self:RegisterEvent("LOOT_READY", "FastLoot") end
    if self:Get("invites") then self:RegisterEvent("PARTY_INVITE_REQUEST", "OnInvite") end
    if self:Get("duels") then self:RegisterEvent("DUEL_REQUESTED", "OnDuel") end
    self:RegisterEvent("ADDON_LOADED", function()
        ns:RunOutOfCombat("qol-move", function() QoL:HookMovables() end)
    end)
end

function QoL:OnEnable()
    self:ApplyEvents()
    self:ApplyCamera()
    self:ApplyCoords()
    ns:RunOutOfCombat("qol-move", function() QoL:HookMovables() end)
end

function QoL:OnDisable()
    self:ApplyCamera()
    self:ApplyCoords()
end

function QoL:OnSettingChanged(key)
    if key == "camera" then self:ApplyCamera()
    elseif key == "coords" then self:ApplyCoords()
    elseif key == "fastLoot" or key == "invites" or key == "duels" then self:ApplyEvents() end
end
