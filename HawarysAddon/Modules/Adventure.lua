-- Hawary's Addon: "What now?" (one card that tells you the best next thing to do) and the
-- Journey Diary (a timeline of your milestones, with optional screenshots – Overwolf-clip style).
-- Both are read-only; the diary's only "action" is taking a screenshot when you allow it.
local _, ns = ...
local L, T, W, A, J = ns.L, ns.Theme, ns.W, ns.AdventureData, ns.JourneyData

---------------------------------------------------------------------------
-- What now?
---------------------------------------------------------------------------
local Now = ns:NewModule("whatnow", {
    title = L.MOD_WHATNOW,
    desc = L.MOD_WHATNOW_DESC,
    order = 9,
    defaults = { home = true },
    charDefaults = { lastTrainerLevel = 0 },
})

Now.options = {
    { type = "toggle", key = "home", label = L.NOW_HOME, desc = L.NOW_HOME_DESC },
}

local NOW_ICONS = {
    repair = "Interface\\Icons\\Trade_BlackSmithing", bags = "Interface\\Icons\\INV_Misc_Bag_08",
    turnin = "quest_done", trainer = "book", dungeon = "Interface\\Icons\\INV_Misc_Key_03",
    shopping = "Interface\\Icons\\INV_Misc_Coin_02", rested = "Interface\\Icons\\Spell_Nature_Sleep",
    quest = "quest_new",
}
local NOW_PAGES = { turnin = "journey", quest = "journey", dungeon = "dungeons", shopping = "professions", upgrade = "gear" }

function Now:State()
    local s = { level = UnitLevel("player") }
    local journey = ns.modules.journey
    if journey then
        local n = 0
        for _, q in ipairs(journey:Quests()) do if q.complete then n = n + 1 end end
        s.turnins = n
    end
    local gear = ns.modules.gear
    if gear and gear.enabled then s.upgrades = gear.upgradeLinks end
    local free = 0
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then free = free + (n or 0) end
    end
    s.freeSlots = free
    local worst
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local f = cur / max
            if not worst or f < worst then worst = f end
        end
    end
    s.durability = worst
    local last = self:Get("lastTrainerLevel")
    if last == 0 then self:CharDB().lastTrainerLevel = s.level; last = s.level end
    s.trainerDue = s.level > last
    local prof = ns.modules.professions
    if prof and prof.enabled and #ns.db.shopping > 0 then
        local missing = 0
        for _, r in ipairs(prof:ShoppingRows()) do if r.missing > 0 then missing = missing + 1 end end
        s.shoppingMissing = missing
    end
    local rested = GetXPExhaustion()
    s.rested = rested and not ns.IsSecret(rested) and rested > 0
    local dungeons = ns.modules.dungeons
    if dungeons and dungeons.enabled then
        local a = dungeons:Suggestion()
        s.dungeonNow = a and a.name
    end
    return s
end

function Now:Text(item)
    local k, d = item.key, item.data
    if k == "repair" then return L.NOW_REPAIR:format(math.floor((d or 0) * 100)) end
    if k == "bags" then return L.NOW_BAGS:format(d or 0) end
    if k == "upgrade" then return L.NOW_UPGRADE:format(d.link, d.pct) end
    if k == "turnin" then return L.NOW_TURNIN:format(d) end
    if k == "trainer" then return L.NOW_TRAINER end
    if k == "dungeon" then return L.NOW_DUNGEON:format(d) end
    if k == "shopping" then return L.NOW_SHOPPING:format(d) end
    if k == "rested" then return L.NOW_RESTED end
    return L.NOW_QUEST
end

function Now:Icon(item)
    if item.key == "upgrade" and item.data then return C_Item.GetItemIconByID(item.data.link) end
    return NOW_ICONS[item.key] or "dot"
end

function Now:List()
    return A.Suggestions(self:State())
end

-- Home card
table.insert(ns.homeSections, function(content, width, y)
    if not (Now.enabled and Now:Get("home")) then return y end
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 166)
    local glow = card:CreateTexture(nil, "ARTWORK", nil, -1)
    glow:SetTexture(ns.media .. "glow")
    glow:SetSize(160, 160)
    glow:SetPoint("CENTER", card, "TOPRIGHT", -40, -30)
    glow:SetVertexColor(0.22, 0.78, 0.96, 0.18)
    local title = W.Label(card, L.MOD_WHATNOW, "h1", "accent")
    title:SetPoint("TOPLEFT", 16, -14)
    local rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Button", nil, card)
        row:SetHeight(28)
        row:SetPoint("TOPLEFT", 12, -40 - (i - 1) * 30)
        row:SetPoint("TOPRIGHT", -12, -40 - (i - 1) * 30)
        row.bg = T.Shape(row, "round_sm", { 0, 0, 0, 0 }, "BACKGROUND")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 6, 0)
        row.text = W.Label(row, "", "body", "text")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -24, 0)
        row.text:SetWordWrap(false)
        row.go = W.Icon(row, "chevron", 14, "text3")
        row.go:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnEnter", function(self)
            T.Tint(self.bg, "hover")
            if self.item and self.item.key == "upgrade" and self.item.data then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.item.data.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self) T.Tint(self.bg, { 0, 0, 0, 0 }); GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local page = self.item and NOW_PAGES[self.item.key]
            if page then ns:OpenWindow(page) end
        end)
        rows[i] = row
    end
    local function refresh()
        local list = Now:List()
        for i, row in ipairs(rows) do
            local item = list[i]
            row.item = item
            if item then
                local icon = Now:Icon(item)
                if type(icon) == "string" and not icon:find("\\", 1, true) then
                    row.icon:SetTexture(ns.media .. icon)
                    T.Tint(row.icon, "accent")
                else
                    row.icon:SetTexture(icon)
                    row.icon:SetVertexColor(1, 1, 1)
                end
                row.text:SetText(Now:Text(item))
                row.go:SetShown(NOW_PAGES[item.key] ~= nil)
                row:Show()
            else
                row:Hide()
            end
        end
    end
    return y - 166 - 16, refresh
end)

ns:On("WHATNOW_PRINT", function()
    ns:Print(L.MOD_WHATNOW)
    for i, item in ipairs(Now:List()) do
        if i > 5 then break end
        ns:Print("  %d. %s", i, Now:Text(item))
    end
end)

function Now:OnEnable()
    self:RegisterEvent("TRAINER_SHOW", function() self:CharDB().lastTrainerLevel = UnitLevel("player") end)
end

---------------------------------------------------------------------------
-- Journey Diary
---------------------------------------------------------------------------
local Diary = ns:NewModule("diary", {
    title = L.MOD_DIARY,
    desc = L.MOD_DIARY_DESC,
    order = 10,
    defaults = { screenshots = false, toasts = true },
    charDefaults = { entries = {}, epics = {}, quests = 0, gold = 0, baseline = false },
})

Diary.options = {
    { type = "toggle", key = "screenshots", label = L.DIARY_SHOTS, desc = L.DIARY_SHOTS_DESC },
    { type = "toggle", key = "toasts", label = L.DIARY_TOASTS, desc = L.DIARY_TOASTS_DESC },
}

local DIARY_ICONS = {
    level = { "star", "accent" }, dungeon = { "Interface\\Icons\\INV_Misc_Key_03" }, epic = { "arrow", { 0.64, 0.21, 0.93, 1 } },
    rare = { "star", { 1, 0.35, 0.4, 1 } }, gold = { "Interface\\Icons\\INV_Misc_Coin_01" }, quests = { "quest_done", { 1, 0.82, 0.24, 1 } },
}

function Diary:Add(kind, text, shot)
    local entry = { t = time(), kind = kind, text = text, level = UnitLevel("player"), zone = GetZoneText() }
    if shot and self:Get("screenshots") then
        entry.shot = true
        C_Timer.After(1.2, function() Screenshot() end)
    end
    local entries = self:Get("entries")
    entries[#entries + 1] = entry
    A.Trim(entries, 500)
    if self:Get("toasts") and kind ~= "level" then ns:Toast(L.MOD_DIARY, text, "logo") end
    ns:Fire("DIARY_UPDATED")
end

function Diary:ScanEpics()
    local epics, first = self:Get("epics"), not self:Get("baseline")
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and info.quality and info.quality >= 4 and not epics[info.itemID] then
                epics[info.itemID] = true
                if not first and info.hyperlink then self:Add("epic", L.DIARY_EPIC:format(info.hyperlink), true) end
            end
        end
    end
    if first then self:CharDB().baseline = true end
end

function Diary:OnMoney()
    local money = GetMoney()
    local best = self:Get("gold")
    local g = A.GoldMilestone(best, money)
    if g and best > 0 then self:Add("gold", L.DIARY_GOLD:format(g)) end
    if money > best then self:CharDB().gold = money end
end

function Diary:OnInitialize()
    ns:On("MILESTONE", function(kind, data)
        if not Diary.enabled then return end
        if kind == "dungeon" and data then
            Diary:Add("dungeon", L.DIARY_DUNGEON:format(data.name, J.FormatDuration(data.duration), data.bosses), true)
        elseif kind == "rare" and data then
            Diary:Add("rare", L.DIARY_RARE:format(data))
        end
    end)
end

function Diary:OnEnable()
    self:RegisterEvent("PLAYER_LEVEL_UP", function(_, _, level)
        self:Add("level", L.DIARY_LEVEL:format(level or UnitLevel("player"), GetZoneText()), true)
    end)
    self:RegisterEvent("QUEST_TURNED_IN", function()
        local n = self:Get("quests") + 1
        self:CharDB().quests = n
        if n % 100 == 0 then self:Add("quests", L.DIARY_QUESTS:format(n)) end
    end)
    self:RegisterEvent("PLAYER_MONEY", "OnMoney")
    self:RegisterEvent("BAG_UPDATE_DELAYED", "ScanEpics")
    if self:Get("gold") == 0 then self:CharDB().gold = GetMoney() end
    C_Timer.After(3, function() if self.enabled then ns.Safe(self.ScanEpics, self) end end)
end

function Diary:BuildPage(content, width, y)
    y = ns:BuildOptions(self, content, width, y)
    local top = y
    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", 0, y)
    list:SetWidth(width)
    list.title = W.Label(list, L.DIARY_TIMELINE, "h2", "accent")
    list.title:SetPoint("TOPLEFT")
    list.line = list:CreateTexture(nil, "BACKGROUND")
    list.line:SetColorTexture(T.color("line"))
    list.line:SetWidth(2)
    list.rows = {}
    function list:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        local entries = Diary:Get("entries")
        local ly = -28
        if #entries == 0 then
            self.emptyLabel = self.emptyLabel or W.Label(self, L.DIARY_EMPTY, "small", "text3")
            self.emptyLabel:SetPoint("TOPLEFT", 0, ly)
            self.emptyLabel:SetWidth(width)
            self.emptyLabel:SetWordWrap(true)
            self.emptyLabel:Show()
            self.line:Hide()
            ly = ly - self.emptyLabel:GetStringHeight() - 6
        else
            if self.emptyLabel then self.emptyLabel:Hide() end
            local n = 0
            for i = #entries, math.max(1, #entries - 59), -1 do
                local e = entries[i]
                n = n + 1
                local row = self.rows[n]
                if not row then
                    row = CreateFrame("Frame", nil, self)
                    row:SetHeight(42)
                    row.dot = row:CreateTexture(nil, "ARTWORK")
                    row.dot:SetSize(22, 22)
                    row.dot:SetPoint("LEFT", 2, 0)
                    row.text = W.Label(row, "", "body", "text")
                    row.text:SetPoint("TOPLEFT", 36, -5)
                    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    row.text:SetWordWrap(false)
                    row.sub = W.Label(row, "", "small", "text3")
                    row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
                    self.rows[n] = row
                end
                local icon = DIARY_ICONS[e.kind] or { "dot", "accent" }
                local file = icon[1]
                if not file:find("\\", 1, true) then file = ns.media .. file end
                row.dot:SetTexture(file)
                if icon[2] then T.Tint(row.dot, icon[2]) else row.dot:SetVertexColor(1, 1, 1) end
                row.text:SetText(e.text)
                row.sub:SetText(L.DIARY_SUB:format(date("%b %d  %H:%M", e.t), e.level or 0, e.zone or "")
                    .. (e.shot and ("  ·  " .. L.DIARY_SHOT) or ""))
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, ly)
                row:SetPoint("TOPRIGHT", 0, ly)
                row:Show()
                ly = ly - 46
            end
            self.line:ClearAllPoints()
            self.line:SetPoint("TOP", self, "TOPLEFT", 13, -34)
            self.line:SetPoint("BOTTOM", self, "TOPLEFT", 13, ly + 10)
            self.line:Show()
        end
        self:SetHeight(-ly)
        content:SetHeight(-top - ly + 20)
        return ly
    end
    ns:On("DIARY_UPDATED", function() if content:IsVisible() then list:Refresh() end end)
    content:HookScript("OnShow", function() list:Refresh() end)
    return top + list:Refresh()
end
