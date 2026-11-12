-- Hawary's Addon: Professions (SkillUp / Profession Shopping List / ForeverProfit style)
-- Remembers your profession ranks and the recipes you know (read while YOUR profession
-- window is open), ranks recipes by profit with Market prices, and keeps a shopping list.
-- It never crafts, buys or sells anything.
local _, ns = ...
local L, U, T, W, M = ns.L, ns.Util, ns.Theme, ns.W, ns.MarketData

local Prof = ns:NewModule("professions", {
    title = L.MOD_PROFESSIONS,
    desc = L.MOD_PROFESSIONS_DESC,
    order = 4,
    defaults = { tooltip = true, rows = 25 },
})

Prof.options = {
    { type = "toggle", key = "tooltip", label = L.PROF_TOOLTIP, desc = L.PROF_TOOLTIP_DESC },
}

local function MyRecord() return ns.db.chars[ns:CharKey()] end

local function Contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

---------------------------------------------------------------------------
-- Profession ranks
---------------------------------------------------------------------------
function Prof:ScanRanks()
    local rec = MyRecord()
    if not (rec and GetProfessions) then return end
    local list = {}
    local a, b, c, d, e, f, g = GetProfessions()
    for _, idx in pairs({ a, b, c, d, e, f, g }) do
        local name, icon, rank, maxRank = GetProfessionInfo(idx)
        if name then list[#list + 1] = { name = name, icon = icon, rank = rank or 0, max = maxRank or 0 } end
    end
    table.sort(list, function(x, y) return x.name < y.name end)
    rec.profs = list
end

---------------------------------------------------------------------------
-- Recipe snapshot (only your own profession window, never an NPC/guild/linked one)
---------------------------------------------------------------------------
function Prof:ScanRecipes()
    local rec = MyRecord()
    if not rec or ns.InCombat() then return end
    if C_TradeSkillUI.IsNPCCrafting() then return end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local profName = base and base.professionName
    if not profName or profName == "" then return end
    rec.recipes = rec.recipes or {}
    local store = rec.recipes[profName] or {}
    local n = 0
    for _, recipeID in ipairs(C_TradeSkillUI.GetFilteredRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and info.learned then
            local s = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
            if s then
                local reagents = {}
                for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                    local r = slot.reagents and slot.reagents[1]
                    if slot.required and r and r.itemID then
                        reagents[#reagents + 1] = { id = r.itemID, n = slot.quantityRequired or 1 }
                    end
                end
                store[recipeID] = {
                    name = info.name, icon = info.icon, output = s.outputItemID,
                    qty = s.quantityMin or 1, reagents = reagents,
                }
                n = n + 1
            end
        end
    end
    if n > 0 then
        rec.recipes[profName] = store
        ns:Fire("PROFESSIONS_UPDATED")
    end
end

function Prof:QueueRecipeScan()
    if self.scanQueued then return end
    self.scanQueued = true
    C_Timer.After(1, function()
        self.scanQueued = false
        ns.Safe(self.ScanRecipes, self)
    end)
end

---------------------------------------------------------------------------
-- Lookups shared by the page and tooltips
---------------------------------------------------------------------------
function Prof:AllRecipes()
    local all = {}
    for _, rec in pairs(ns.db.chars) do
        for _, list in pairs(rec.recipes or {}) do
            for id, r in pairs(list) do all[id] = r end
        end
    end
    return all
end

-- Professions with known recipes, current character first
function Prof:KnownProfessions()
    local seen, out = {}, {}
    local function add(rec)
        for name in pairs(rec.recipes or {}) do
            if not seen[name] then seen[name] = true; out[#out + 1] = name end
        end
    end
    local me = MyRecord()
    if me then add(me) end
    for _, rec in pairs(ns.db.chars) do add(rec) end
    return out
end

function Prof:RecipesFor(profName)
    local me = MyRecord()
    if me and me.recipes and me.recipes[profName] then return me.recipes[profName] end
    for _, rec in pairs(ns.db.chars) do
        if rec.recipes and rec.recipes[profName] then return rec.recipes[profName] end
    end
    return {}
end

local function PriceOf(itemID)
    local market = ns.modules.market
    if market and market.enabled then return (market:Price(itemID)) end
    return nil
end

-- Item count across all your characters (bags + bank)
function Prof:Have(itemID)
    local n = 0
    for _, rec in pairs(ns.db.chars) do
        n = n + (rec.bags and rec.bags[itemID] or 0) + (rec.bank and rec.bank[itemID] or 0)
    end
    return n
end

function Prof:ShoppingRows()
    return M.ShoppingNeeds(ns.db.shopping, self:AllRecipes(), function(id) return self:Have(id) end)
end

function Prof:AddToList(recipeID, delta)
    for i, e in ipairs(ns.db.shopping) do
        if e.recipeID == recipeID then
            e.count = e.count + delta
            if e.count <= 0 then table.remove(ns.db.shopping, i) end
            ns:Fire("SHOPPING_UPDATED")
            return
        end
    end
    if delta > 0 then table.insert(ns.db.shopping, { recipeID = recipeID, count = delta }) end
    ns:Fire("SHOPPING_UPDATED")
end

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then C_Item.RequestLoadItemDataByID(itemID) end
    return name or ("#" .. itemID)
end

local function ProfitText(result)
    if result.profit then
        local color = result.profit >= 0 and "|cff4ade80+" or "|cfff87171-"
        return color .. U.money(math.abs(result.profit), true) .. "|r"
    end
    return "|cff77808f?|r"
end

---------------------------------------------------------------------------
-- Tooltip: shopping-list needs on reagents
---------------------------------------------------------------------------
local function OnTooltipItem(tooltip)
    if not (Prof.enabled and Prof:Get("tooltip")) or #ns.db.shopping == 0 then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link or ns.IsSecret(link) then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    for _, row in ipairs(Prof:ShoppingRows()) do
        if row.itemID == itemID then
            local color = row.missing > 0 and "f87171" or "4ade80"
            tooltip:AddDoubleLine("|cff38c6f4" .. L.PROF_LIST .. "|r", ("|cff%s%d / %d|r"):format(color, row.have, row.need))
            tooltip:Show()
            return
        end
    end
end

---------------------------------------------------------------------------
-- Page: ranks, profitable recipes, shopping list
---------------------------------------------------------------------------
local function SmallButton(parent, text, kind)
    return W.Button(parent, text, kind or "ghost", 26, 20)
end

function Prof:BuildPage(content, width, y)
    y = ns:BuildOptions(self, content, width, y)
    local sections = {}
    local top = y

    local function Relayout()
        local yy = top
        for _, sec in ipairs(sections) do
            sec:ClearAllPoints()
            sec:SetPoint("TOPLEFT", 0, yy)
            sec:SetWidth(width)
            local h = sec:Refresh()
            sec:SetHeight(math.max(1, h))
            yy = yy - h - 20
        end
        content:SetHeight(-yy + 20)
        return yy
    end

    -- 1) Your professions (ranks)
    local ranks = CreateFrame("Frame", nil, content)
    ranks.title = W.Label(ranks, L.PROF_YOURS, "h2", "accent")
    ranks.title:SetPoint("TOPLEFT")
    ranks.cards = {}
    function ranks:Refresh()
        local rec = MyRecord()
        local list = rec and rec.profs or {}
        for _, c in ipairs(self.cards) do c:Hide() end
        if #list == 0 then
            self.emptyLabel = self.emptyLabel or W.Label(self, L.PROF_NONE, "small", "text3")
            self.emptyLabel:SetPoint("TOPLEFT", 0, -24)
            self.emptyLabel:Show()
            return 44
        end
        if self.emptyLabel then self.emptyLabel:Hide() end
        local cols, gap = 2, 12
        local cw = (width - gap) / cols
        for i, p in ipairs(list) do
            local c = self.cards[i]
            if not c then
                c = W.Card(self)
                c:SetHeight(50)
                c.icon = c:CreateTexture(nil, "ARTWORK")
                c.icon:SetSize(28, 28)
                c.icon:SetPoint("LEFT", 12, 0)
                c.name = W.Label(c, "", "body", "text")
                c.name:SetPoint("TOPLEFT", 50, -9)
                c.rank = W.Label(c, "", "small", "text3", "RIGHT")
                c.rank:SetPoint("TOPRIGHT", -12, -10)
                c.barBg = T.Shape(c, "pill", "line", "ARTWORK", 0, true)
                c.barBg:SetHeight(5)
                c.barBg:SetPoint("BOTTOMLEFT", 50, 11)
                c.barBg:SetPoint("BOTTOMRIGHT", -12, 11)
                c.bar = T.Shape(c, "pill", "accent", "ARTWORK", 1, true)
                c.bar:SetHeight(5)
                c.bar:SetPoint("LEFT", c.barBg, "LEFT")
                self.cards[i] = c
            end
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", col * (cw + gap), -24 - row * 58)
            c:SetWidth(cw)
            if p.icon then c.icon:SetTexture(p.icon) end
            c.name:SetText(p.name)
            c.rank:SetText(("%d / %d"):format(p.rank, p.max))
            local frac = p.max > 0 and p.rank / p.max or 0
            c.bar:SetWidth(math.max(5, (cw - 62) * frac))
            c:Show()
        end
        return 24 + math.ceil(#list / cols) * 58
    end
    sections[#sections + 1] = ranks

    -- 2) Most profitable recipes
    local recipes = CreateFrame("Frame", nil, content)
    recipes.title = W.Label(recipes, L.PROF_PROFIT, "h2", "accent")
    recipes.title:SetPoint("TOPLEFT")
    recipes.rows = {}
    recipes.dropdown = W.Dropdown(recipes, 200, function()
        local out = {}
        for _, name in ipairs(Prof:KnownProfessions()) do out[#out + 1] = { value = name, text = name } end
        return out
    end, function() return recipes.selected end, function(v) recipes.selected = v; Relayout() end)
    recipes.dropdown:SetPoint("TOPRIGHT", 0, 4)
    function recipes:Refresh()
        local profs = Prof:KnownProfessions()
        if not self.selected or not Contains(profs, self.selected) then self.selected = profs[1] end
        self.dropdown:SetShown(#profs > 0)
        self.dropdown:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        if not self.selected then
            self.emptyLabel = self.emptyLabel or W.Label(self, L.PROF_NO_RECIPES, "small", "text3")
            self.emptyLabel:SetPoint("TOPLEFT", 0, -26)
            self.emptyLabel:SetWidth(width)
            self.emptyLabel:SetWordWrap(true)
            self.emptyLabel:Show()
            return 30 + self.emptyLabel:GetStringHeight()
        end
        if self.emptyLabel then self.emptyLabel:Hide() end
        local list = {}
        for id, r in pairs(Prof:RecipesFor(self.selected)) do
            list[#list + 1] = { id = id, name = r.name, recipe = r, result = M.RecipeProfit(r, PriceOf) }
        end
        M.RankByProfit(list)
        local ry = -30
        for i = 1, math.min(#list, Prof:Get("rows")) do
            local e = list[i]
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, self)
                row:SetHeight(26)
                row.bg = T.Shape(row, "round_sm", "card", "BACKGROUND")
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", 8, 0)
                row.name = W.Label(row, "", "body", "text")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
                row.name:SetWordWrap(false)
                row.profit = W.Label(row, "", "body", nil, "RIGHT")
                row.profit:SetPoint("RIGHT", -40, 0)
                row.add = SmallButton(row, "+", "secondary")
                row.add:SetPoint("RIGHT", -6, 0)
                row.add:SetScript("OnClick", function() if row.entry then Prof:AddToList(row.entry.id, 1) end end)
                W.Tooltip(row.add, L.PROF_ADD)
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(selfRow)
                    local res = selfRow.entry and selfRow.entry.result
                    if not res then return end
                    GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                    GameTooltip:SetText(selfRow.entry.name or "", T.color("accent"))
                    GameTooltip:AddDoubleLine(L.PROF_VALUE, res.value and U.money(res.value) or "?", 1, 1, 1, 1, 1, 1)
                    GameTooltip:AddDoubleLine(L.PROF_COST, res.cost and U.money(res.cost) or "?", 1, 1, 1, 1, 1, 1)
                    for _, id in ipairs(res.missing) do GameTooltip:AddLine(L.PROF_NO_PRICE:format(ItemName(id)), 0.6, 0.6, 0.6) end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                self.rows[i] = row
            end
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, ry)
            row:SetPoint("TOPRIGHT", 0, ry)
            row.icon:SetTexture(e.recipe.icon or (e.recipe.output and C_Item.GetItemIconByID(e.recipe.output)) or 134400)
            row.name:SetText(e.name or ("#" .. e.id))
            row.profit:SetText(ProfitText(e.result))
            row:Show()
            ry = ry - 30
        end
        return -ry
    end
    sections[#sections + 1] = recipes

    -- 3) Shopping list
    local shop = CreateFrame("Frame", nil, content)
    shop.title = W.Label(shop, L.PROF_SHOPPING, "h2", "accent")
    shop.title:SetPoint("TOPLEFT")
    shop.clear = W.Button(shop, L.PROF_CLEAR, "danger", 90, 22)
    shop.clear:SetPoint("TOPRIGHT", 0, 2)
    shop.clear:SetScript("OnClick", function() wipe(ns.db.shopping); ns:Fire("SHOPPING_UPDATED") end)
    shop.entries, shop.reagents = {}, {}
    function shop:Refresh()
        for _, r in ipairs(self.entries) do r:Hide() end
        for _, r in ipairs(self.reagents) do r:Hide() end
        if self.total then self.total:Hide() end
        local all = Prof:AllRecipes()
        local sy = -30
        if #ns.db.shopping == 0 then
            self.clear:Hide()
            self.emptyLabel = self.emptyLabel or W.Label(self, L.PROF_SHOPPING_EMPTY, "small", "text3")
            self.emptyLabel:SetPoint("TOPLEFT", 0, sy)
            self.emptyLabel:SetWidth(width)
            self.emptyLabel:SetWordWrap(true)
            self.emptyLabel:Show()
            return -sy + self.emptyLabel:GetStringHeight()
        end
        self.clear:Show()
        if self.emptyLabel then self.emptyLabel:Hide() end
        for i, entry in ipairs(ns.db.shopping) do
            local row = self.entries[i]
            if not row then
                row = CreateFrame("Frame", nil, self)
                row:SetHeight(24)
                row.name = W.Label(row, "", "body", "text")
                row.name:SetPoint("LEFT", 4, 0)
                row.del = SmallButton(row, "x", "danger")
                row.del:SetPoint("RIGHT", 0, 0)
                row.plus = SmallButton(row, "+")
                row.plus:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
                row.minus = SmallButton(row, "-")
                row.minus:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
                row.plus:SetScript("OnClick", function() Prof:AddToList(row.recipeID, 1) end)
                row.minus:SetScript("OnClick", function() Prof:AddToList(row.recipeID, -1) end)
                row.del:SetScript("OnClick", function() Prof:AddToList(row.recipeID, -9999) end)
                self.entries[i] = row
            end
            local r = all[entry.recipeID]
            row.recipeID = entry.recipeID
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, sy)
            row:SetPoint("TOPRIGHT", 0, sy)
            row.name:SetText(("%s  |cff38c6f4x%d|r"):format(r and r.name or ("#" .. entry.recipeID), entry.count))
            row:Show()
            sy = sy - 26
        end
        sy = sy - 8
        local totalCost, unknown = 0, false
        for i, need in ipairs(Prof:ShoppingRows()) do
            local row = self.reagents[i]
            if not row then
                row = CreateFrame("Frame", nil, self)
                row:SetHeight(22)
                row.bg = T.Shape(row, "round_sm", "card", "BACKGROUND")
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", 8, 0)
                row.name = W.Label(row, "", "small", "text")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.count = W.Label(row, "", "small", nil, "RIGHT")
                row.count:SetPoint("RIGHT", -120, 0)
                row.cost = W.Label(row, "", "small", "text2", "RIGHT")
                row.cost:SetPoint("RIGHT", -10, 0)
                self.reagents[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, sy)
            row:SetPoint("TOPRIGHT", 0, sy)
            row.icon:SetTexture(C_Item.GetItemIconByID(need.itemID) or 134400)
            row.name:SetText(ItemName(need.itemID))
            local color = need.missing > 0 and "f87171" or "4ade80"
            row.count:SetText(("|cff%s%d / %d|r"):format(color, need.have, need.need))
            if need.missing > 0 then
                local p = PriceOf(need.itemID)
                if p then
                    row.cost:SetText(U.money(p * need.missing, true))
                    totalCost = totalCost + p * need.missing
                else
                    row.cost:SetText("?")
                    unknown = true
                end
            else
                row.cost:SetText("")
            end
            row:Show()
            sy = sy - 24
        end
        self.total = self.total or W.Label(self, "", "body", "text")
        self.total:ClearAllPoints()
        self.total:SetPoint("TOPRIGHT", -10, sy - 4)
        self.total:SetText(L.PROF_TOTAL:format(U.money(totalCost)) .. (unknown and "  |cff77808f(+ ?)|r" or ""))
        self.total:Show()
        return -sy + 24
    end
    sections[#sections + 1] = shop

    local function maybeRelayout() if content:IsVisible() then Relayout() end end
    ns:On("PROFESSIONS_UPDATED", maybeRelayout)
    ns:On("SHOPPING_UPDATED", maybeRelayout)
    ns:On("MARKET_UPDATED", maybeRelayout)
    content:HookScript("OnShow", Relayout)
    return Relayout()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Prof:OnInitialize()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        ns.Safe(OnTooltipItem, tooltip)
    end)
end

function Prof:OnEnable()
    self:RegisterEvent("SKILL_LINES_CHANGED", "ScanRanks")
    self:RegisterEvent("TRADE_SKILL_SHOW", "QueueRecipeScan")
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "QueueRecipeScan")
    self:RegisterEvent("NEW_RECIPE_LEARNED", "QueueRecipeScan")
    C_Timer.After(3, function() if self.enabled then ns.Safe(self.ScanRanks, self) end end)
end
