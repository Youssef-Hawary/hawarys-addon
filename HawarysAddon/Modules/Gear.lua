-- Hawary's Addon: Gear & Upgrades (Pawn + GearQuest + NAG-style reward pick)
-- Read-only: it only reads item data and adds tooltip text / icons. It never equips,
-- uses or moves items by itself.
local _, ns = ...
local L, T, D = ns.L, ns.Theme, ns.GearData

local Gear = ns:NewModule("gear", {
    title = L.MOD_GEAR,
    desc = L.MOD_GEAR_DESC,
    order = 1,
    defaults = { tooltip = true, ilvl = true, bags = true, quest = true, questSelect = false, toast = true,
        rawScore = false, custom = {} },
    charDefaults = { profile = "auto" },
})

Gear.options = {
    { type = "dropdown", key = "profile", label = L.GEAR_PROFILE, desc = L.GEAR_PROFILE_DESC, values = function()
        local out = { { value = "auto", text = L.GEAR_AUTO } }
        local _, classFile = UnitClass("player")
        for _, p in ipairs(D.profiles[classFile] or {}) do out[#out + 1] = { value = p.id, text = p.label } end
        out[#out + 1] = { value = D.GENERIC.id, text = D.GENERIC.label }
        for _, id in ipairs(ns.Util.sortedKeys(D.custom)) do
            out[#out + 1] = { value = id, text = "|cff38c6f4" .. D.custom[id].label .. "|r" }
        end
        return out
    end },
    { type = "button", label = L.GEAR_PAWN_IMPORT, desc = L.GEAR_PAWN_IMPORT_DESC, buttonText = L.IMPORT,
      onClick = function() Gear:ImportScaleDialog() end },
    { type = "button", label = L.GEAR_PAWN_EXPORT, desc = L.GEAR_PAWN_EXPORT_DESC, buttonText = L.EXPORT,
      onClick = function() Gear:ExportScaleDialog() end },
    { type = "button", label = L.GEAR_PAWN_DELETE, desc = L.GEAR_PAWN_DELETE_DESC, buttonText = L.DELETE, kind = "danger",
      onClick = function() Gear:DeleteCurrentScale() end },
    { type = "toggle", key = "rawScore", label = L.GEAR_RAW, desc = L.GEAR_RAW_DESC },
    { type = "toggle", key = "tooltip", label = L.GEAR_TOOLTIP, desc = L.GEAR_TOOLTIP_DESC },
    { type = "toggle", key = "ilvl", label = L.GEAR_ILVL, desc = L.GEAR_ILVL_DESC },
    { type = "toggle", key = "bags", label = L.GEAR_BAGS, desc = L.GEAR_BAGS_DESC },
    { type = "toggle", key = "quest", label = L.GEAR_QUEST, desc = L.GEAR_QUEST_DESC },
    { type = "toggle", key = "questSelect", label = L.GEAR_QUEST_SELECT, desc = L.GEAR_QUEST_SELECT_DESC, parent = "quest" },
    { type = "toggle", key = "toast", label = L.GEAR_TOAST, desc = L.GEAR_TOAST_DESC },
}

local cache = {}       -- itemLink -> score with the current profile
local MARK = "|T" .. ns.media .. "mark:14:14|t"

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
function Gear:Profile()
    if self.profile then return self.profile end
    local _, classFile = UnitClass("player")
    local role, primary
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local ok, idx = pcall(C_SpecializationInfo.GetSpecialization)
        if ok and idx and idx > 0 then
            local ok2, _, _, _, _, r, p = pcall(C_SpecializationInfo.GetSpecializationInfo, idx, false, false)
            if ok2 then role, primary = r, p end
        end
    end
    self.profile = D.PickProfile(classFile, role, primary, self:Get("profile"))
    return self.profile
end

function Gear:ResetScores()
    wipe(cache)
    self.profile = nil
end

function Gear:ScoreLink(link)
    local s = cache[link]
    if s ~= nil then return s end
    local stats = C_Item.GetItemStats(link)
    if not stats then return nil end -- item not loaded yet
    s = D.Score(stats, self:Profile())
    cache[link] = s
    return s
end

-- Score of what's in an inventory slot; false when the slot is empty.
function Gear:SlotScore(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return false end
    return self:ScoreLink(link) or 0
end

local function IsEquipped(link, slots)
    for _, slot in ipairs(slots) do
        if GetInventoryItemLink("player", slot) == link then return true end
    end
    return false
end

-- Returns { kind = "upgrade"|"empty"|"same"|"downgrade"|"cantuse"|"equipped", pct, minLevel } or nil
function Gear:Evaluate(link)
    if not link or ns.IsSecret(link) then return nil end
    local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil end
    local slots = D.SLOTS[equipLoc]
    if not slots or equipLoc == "INVTYPE_BODY" then return nil end
    if IsEquipped(link, slots) then return { kind = "equipped" } end

    local _, classFile = UnitClass("player")
    if not D.CanWear(classFile, UnitLevel("player"), classID, subclassID) then return { kind = "cantuse" } end

    local score = self:ScoreLink(link)
    if not score then return nil end

    local equipped = {}
    if equipLoc == "INVTYPE_2HWEAPON" then
        local mh, oh = self:SlotScore(16), self:SlotScore(17)
        equipped[1] = (mh == false and oh == false) and false or ((mh or 0) + (oh or 0))
    elseif equipLoc == "INVTYPE_WEAPON" then
        equipped[1] = self:SlotScore(16)
        local ohLink = GetInventoryItemLink("player", 17)
        if ohLink and select(4, C_Item.GetItemInfoInstant(ohLink)) == "INVTYPE_WEAPON" then
            equipped[2] = self:SlotScore(17)
        end
    elseif slots[1] == 17 then
        local mhLink = GetInventoryItemLink("player", 16)
        if mhLink and select(4, C_Item.GetItemInfoInstant(mhLink)) == "INVTYPE_2HWEAPON" then return nil end
        equipped[1] = self:SlotScore(17)
    else
        for i, slot in ipairs(slots) do equipped[i] = self:SlotScore(slot) end
    end

    local kind, pct = D.Compare(score, equipped)
    local _, _, _, _, minLevel = C_Item.GetItemInfo(link)
    return { kind = kind, pct = pct, minLevel = minLevel }
end

local function IsUpgrade(r) return r and (r.kind == "upgrade" or r.kind == "empty") end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local function ResultText(r)
    if r.kind == "upgrade" then
        return "|cff4ade80" .. L.GEAR_UPGRADE:format(r.pct) .. "|r"
    elseif r.kind == "empty" then
        return "|cff4ade80" .. L.GEAR_EMPTY_SLOT .. "|r"
    elseif r.kind == "downgrade" then
        return "|cfff87171" .. L.GEAR_DOWNGRADE:format(r.pct) .. "|r"
    elseif r.kind == "same" then
        return "|cffaeb7c7" .. L.GEAR_SAME .. "|r"
    elseif r.kind == "cantuse" then
        return "|cff77808f" .. L.GEAR_CANT_USE .. "|r"
    end
end

local function OnTooltipItem(tooltip)
    if not Gear.enabled then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link or ns.IsSecret(link) then return end

    local added = false
    if Gear:Get("tooltip") then
        local r = Gear:Evaluate(link)
        local text = r and ResultText(r)
        if text then
            tooltip:AddLine(" ")
            tooltip:AddDoubleLine(MARK .. " |cff38c6f4Hawary's|r  " .. L.GEAR_PROFILE_LINE:format(Gear:Profile().label), text)
            added = true
            local score = Gear:Get("rawScore") and Gear:ScoreLink(link)
            if score then tooltip:AddDoubleLine(L.GEAR_RAW_LINE, string.format("%.1f", score), 0.47, 0.50, 0.56, 0.68, 0.72, 0.78) end
        end
    end
    if Gear:Get("ilvl") then
        local ilvl = C_Item.GetDetailedItemLevelInfo(link)
        local itemID = C_Item.GetItemInfoInstant(link)
        if ilvl and itemID then
            if not added then tooltip:AddLine(" ") end
            tooltip:AddLine(L.GEAR_ILVL_LINE:format(ilvl, itemID), 0.47, 0.50, 0.56)
            added = true
        end
    end
    if added then tooltip:Show() end
end

---------------------------------------------------------------------------
-- Bag arrows (our own texture on top of Blizzard's bag buttons; display only)
---------------------------------------------------------------------------
local bagFrames = {}

local function Arrow(button)
    local a = button.HawarysUpgrade
    if not a then
        a = button:CreateTexture(nil, "OVERLAY", nil, 7)
        a:SetTexture(ns.media .. "arrow")
        a:SetSize(15, 15)
        a:SetPoint("TOPLEFT", 1, -1)
        a:SetVertexColor(0.29, 0.87, 0.5)
        button.HawarysUpgrade = a
    end
    return a
end

function Gear:RefreshContainer(frame)
    if not frame.EnumerateValidItems then return end
    local show = self.enabled and self:Get("bags")
    for _, button in frame:EnumerateValidItems() do
        local up = false
        if show then
            local link = C_Container.GetContainerItemLink(button:GetBagID(), button:GetID())
            up = link and IsUpgrade(self:Evaluate(link)) or false
        end
        if up then Arrow(button):Show() elseif button.HawarysUpgrade then button.HawarysUpgrade:Hide() end
    end
end

function Gear:RefreshOpenBags()
    for _, frame in ipairs(bagFrames) do
        if frame:IsShown() then ns.Safe(self.RefreshContainer, self, frame) end
    end
end

function Gear:HookBags()
    if self.bagsHooked then return end
    self.bagsHooked = true
    local function hook(frame)
        if not frame or not frame.UpdateItems then return end
        table.insert(bagFrames, frame)
        hooksecurefunc(frame, "UpdateItems", function(f)
            if Gear.enabled then ns.Safe(Gear.RefreshContainer, Gear, f) end
        end)
    end
    hook(ContainerFrameCombinedBags)
    for i = 1, 20 do hook(_G["ContainerFrame" .. i]) end
end

---------------------------------------------------------------------------
-- Quest reward pick (marks the reward; optional pre-select, you still click Complete)
---------------------------------------------------------------------------
local function PickMark(button)
    local m = button.HawarysPick
    if not m then
        m = CreateFrame("Frame", nil, button)
        m:SetPoint("TOPLEFT", -3, 3)
        m:SetPoint("BOTTOMRIGHT", 3, -3)
        m:SetFrameLevel(button:GetFrameLevel() + 5)
        m.glow = T.Shape(m, "round_sm", { 0.22, 0.78, 0.96, 0.10 }, "BACKGROUND")
        m.border = T.Shape(m, "round_sm_line", { 0.22, 0.78, 0.96, 1 }, "OVERLAY")
        m.icon = m:CreateTexture(nil, "OVERLAY", nil, 2)
        m.icon:SetSize(16, 16)
        m.icon:SetPoint("TOPRIGHT", -2, -2)
        m.label = m:CreateFontString(nil, "OVERLAY")
        m.label:SetFontObject(T.font("tag"))
        m.label:SetTextColor(0.22, 0.78, 0.96)
        m.label:SetPoint("BOTTOMRIGHT", m, "TOPRIGHT", -4, 1)
        m:EnableMouse(false)
        button.HawarysPick = m
    end
    return m
end

local function HideMarks()
    local rf = QuestInfoFrame and QuestInfoFrame.rewardsFrame
    if not (rf and rf.RewardButtons) then return end
    for _, b in ipairs(rf.RewardButtons) do if b.HawarysPick then b.HawarysPick:Hide() end end
end

function Gear:MarkQuestRewards()
    HideMarks()
    if not (self.enabled and self:Get("quest")) then return end
    if not QuestInfoFrame or QuestInfoFrame.questLog then return end
    local rf = QuestInfoFrame.rewardsFrame
    if not (rf and rf.RewardButtons) then return end
    local n = GetNumQuestChoices() or 0
    if n < 2 then return end

    local choices, pending = {}, false
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        if not link then
            pending = true
        else
            local _, _, count = GetQuestItemInfo("choice", i)
            local r = self:Evaluate(link)
            local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
            if r == nil and D.SLOTS[equipLoc] and cache[link] == nil then pending = true end
            local sell = select(11, C_Item.GetItemInfo(link)) or 0
            choices[#choices + 1] = { index = i, kind = r and r.kind, pct = r and r.pct or 0, value = sell * (count or 1) }
        end
    end
    if pending and (self.rewardTries or 0) < 6 then
        self.rewardTries = (self.rewardTries or 0) + 1
        C_Timer.After(0.35, function() ns.Safe(Gear.MarkQuestRewards, Gear) end)
        return
    end

    local best, reason = D.BestReward(choices)
    if not best then return end
    for _, button in ipairs(rf.RewardButtons) do
        if button:IsShown() and button.type == "choice" and button:GetID() == best then
            local m = PickMark(button)
            m.label:SetText(reason == "upgrade" and L.GEAR_BEST_REWARD:upper() or L.GEAR_BEST_VALUE:upper())
            if reason == "upgrade" then
                m.icon:SetTexture(ns.media .. "arrow")
                m.icon:SetVertexColor(0.29, 0.87, 0.5)
            else
                m.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
                m.icon:SetVertexColor(1, 1, 1)
            end
            m:Show()
            if self:Get("questSelect") and QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() and QuestInfoItem_OnClick then
                QuestInfoItem_OnClick(button)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Bag scan: upgrade count + "upgrade looted" notices
---------------------------------------------------------------------------
function Gear:ScanBags(initial)
    local seen = self.seen or {}
    local count = 0
    local links = {}
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link and not ns.IsSecret(link) then
                local r = self:Evaluate(link)
                if IsUpgrade(r) then
                    count = count + 1
                    links[#links + 1] = { link = link, pct = r.pct or 100 }
                    if not initial and not seen[link] and self:Get("toast") then
                        ns:Toast(L.MOD_GEAR, L.GEAR_NEW_UPGRADE:format(link, r.pct or 100), C_Item.GetItemIconByID(link))
                    end
                end
                if r ~= nil or not D.SLOTS[select(4, C_Item.GetItemInfoInstant(link)) or ""] then seen[link] = true end
            end
        end
    end
    self.seen = seen
    self.upgradeCount = count
    table.sort(links, function(a, b) return a.pct > b.pct end)
    self.upgradeLinks = links
end

function Gear:AverageItemLevel()
    local total, n = 0, 0
    for slot = 1, 18 do
        if slot ~= 4 then
            local link = GetInventoryItemLink("player", slot)
            if link then
                local ilvl = C_Item.GetDetailedItemLevelInfo(link)
                if ilvl then total, n = total + ilvl, n + 1 end
            end
        end
    end
    if n == 0 then return nil end
    return string.format("%.1f", total / n)
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Your own scales (Pawn-style): import / export / delete
---------------------------------------------------------------------------
function Gear:LoadCustomScales()
    wipe(D.custom)
    for id, sc in pairs(self:DB().custom or {}) do
        if type(sc) == "table" and type(sc.w) == "table" then
            D.custom[id] = { id = id, label = sc.label or id, role = "DAMAGER", w = sc.w }
        end
    end
end

function Gear:ImportScaleDialog()
    ns.W.TextDialog(L.GEAR_PAWN_PASTE, "", false, function(text)
        local scale, why = D.ParsePawnScale(text)
        if not scale then ns:Print(L.GEAR_PAWN_BAD, why or "?"); return end
        local store = self:DB().custom
        local n = 1
        while store["CUSTOM_" .. n] do n = n + 1 end
        local id = "CUSTOM_" .. n
        store[id] = { label = scale.label, w = scale.w }
        self:LoadCustomScales()
        self:Set("profile", id)
        ns:Print(L.GEAR_PAWN_OK, scale.label)
    end)
end

function Gear:ExportScaleDialog()
    local p = self:Profile()
    ns.W.TextDialog(L.GEAR_PAWN_EXPORT, D.ExportPawnScale(p.label, p.w), true)
end

function Gear:DeleteCurrentScale()
    local id = self:Get("profile")
    if not (id and D.custom[id]) then ns:Print(L.GEAR_PAWN_NOT_CUSTOM); return end
    local label = D.custom[id].label
    self:DB().custom[id] = nil
    self:LoadCustomScales()
    self:Set("profile", "auto")
    ns:Print(L.GEAR_PAWN_DELETED, label)
end

function Gear:OnInitialize()
    self:LoadCustomScales()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        ns.Safe(OnTooltipItem, tooltip)
    end)
    ns:RegisterStat("ilvl", L.HOME_ILVL, function() return Gear:AverageItemLevel() or "–" end, 20)
    ns:RegisterStat("upgrades", L.HOME_UPGRADES, function()
        if not Gear.enabled then return "–" end
        return Gear.upgradeCount or 0
    end, 30)
    ns:On("DEBUG_STATS", function()
        local _, link = TooltipUtil.GetDisplayedItem(GameTooltip)
        if not link then ns:Print("Hover an item first."); return end
        ns:Print(link)
        for k, v in pairs(C_Item.GetItemStats(link) or {}) do ns:Print("  %s = %s", k, tostring(v)) end
        local r = Gear:Evaluate(link)
        if r then ns:Print("  -> %s %s (%s)", r.kind, tostring(r.pct), Gear:Profile().id) end
    end)
end

function Gear:OnEnable()
    self:HookBags()
    if not self.questHooked and QuestInfo_ShowRewards then
        self.questHooked = true
        hooksecurefunc("QuestInfo_ShowRewards", function() ns.Safe(Gear.MarkQuestRewards, Gear) end)
    end
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
        self:RefreshOpenBags()
        self:ScanBags(true)
    end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        self:ScanBags(false)
        self:RefreshOpenBags()
    end)
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, _, unit)
        if unit == "player" then self:ResetScores(); self:RefreshOpenBags() end
    end)
    self:RegisterEvent("QUEST_DETAIL", function() self.rewardTries = 0 end)
    self:RegisterEvent("QUEST_COMPLETE", function() self.rewardTries = 0 end)
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if self.pendingRefresh then return end
        self.pendingRefresh = true
        C_Timer.After(0.5, function()
            self.pendingRefresh = false
            if self.enabled then self:RefreshOpenBags() end
        end)
    end)
    C_Timer.After(2, function() if self.enabled then ns.Safe(self.ScanBags, self, true) end end)
    self:RefreshOpenBags()
end

function Gear:OnDisable()
    self:RefreshOpenBags()
    HideMarks()
end

function Gear:OnSettingChanged(key)
    if key == "profile" then self:ResetScores() end
    if key == "rawScore" then return end
    if key == "profile" or key == "bags" then self:RefreshOpenBags() end
    if key == "quest" and not self:Get("quest") then HideMarks() end
end
