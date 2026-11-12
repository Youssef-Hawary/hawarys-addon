-- Hawary's Addon: Bag Categories + Junk List.
-- Categories: your bags grouped (gear, consumables, trade goods, quest items, junk…), read only.
-- Junk list: items YOU mark as junk. At a merchant, each click on "Sell junk" sells ONE
-- stack (one action per click, like right-clicking it yourself). Never automatic.
local _, ns = ...
local L, U, T, W = ns.L, ns.Util, ns.Theme, ns.W

local BP = ns:NewModule("bagsplus", {
    title = L.MOD_BAGSPLUS,
    desc = L.MOD_BAGSPLUS_DESC,
    order = 16,
    defaults = { tooltip = true, merchantButton = true },
})

BP.options = {
    { type = "toggle", key = "tooltip", label = L.JUNK_TOOLTIP, desc = L.JUNK_TOOLTIP_DESC },
    { type = "toggle", key = "merchantButton", label = L.JUNK_MERCHANT, desc = L.JUNK_MERCHANT_DESC },
}

local IC = Enum.ItemClass or {}
-- category id -> test(classID, quality, itemID); first match wins (order matters)
BP.CATEGORIES = {
    { id = "JUNKLIST", test = function(_, _, id) return ns.db.junk[id] == true end },
    { id = "POOR", test = function(_, q) return q == 0 end },
    { id = "QUEST", test = function(c) return c == IC.Questitem end },
    { id = "GEAR", test = function(c) return c == IC.Weapon or c == IC.Armor end },
    { id = "CONSUMABLE", test = function(c) return c == IC.Consumable end },
    { id = "TRADE", test = function(c) return c == IC.Tradegoods or c == IC.Reagent or c == IC.Gem or c == IC.ItemEnhancement end },
    { id = "RECIPE", test = function(c) return c == IC.Recipe end },
    { id = "AMMO", test = function(c) return c == IC.Projectile or c == IC.Quiver end },
    { id = "CONTAINER", test = function(c) return c == IC.Container end },
    { id = "OTHER", test = function() return true end },
}

-- Pure: which category an item belongs to. Unit-tested.
function BP.Categorize(classID, quality, itemID)
    for _, cat in ipairs(BP.CATEGORIES) do
        if cat.test(classID, quality, itemID) then return cat.id end
    end
    return "OTHER"
end

function BP:Scan()
    local groups = {}
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag or Enum.BagIndex.Bag_4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local _, _, _, _, icon, classID = C_Item.GetItemInfoInstant(info.itemID)
                local cat = BP.Categorize(classID, info.quality, info.itemID)
                groups[cat] = groups[cat] or {}
                table.insert(groups[cat], { bag = bag, slot = slot, id = info.itemID, icon = info.iconFileID or icon,
                                             count = info.stackCount or 1, link = info.hyperlink })
            end
        end
    end
    return groups
end

---------------------------------------------------------------------------
-- Junk list
---------------------------------------------------------------------------
function BP:AddJunk(itemID)
    if not itemID then return end
    ns.db.junk[itemID] = true
    ns:Print(L.JUNK_ADDED:format(C_Item.GetItemNameByID(itemID) or itemID))
    ns:Fire("JUNK_CHANGED")
end

function BP:RemoveJunk(itemID)
    ns.db.junk[itemID] = nil
    ns:Fire("JUNK_CHANGED")
end

-- Next junk-list stack in your bags, or nil
function BP:NextJunk()
    local n, first = 0, nil
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and ns.db.junk[info.itemID] and not info.isLocked then
                n = n + 1
                first = first or { bag = bag, slot = slot }
            end
        end
    end
    return first, n
end

-- One click = one stack sold (the same as right-clicking it at the merchant)
function BP:SellOne()
    if ns.InCombat() or not self.merchantOpen then return end
    local nextItem = self:NextJunk()
    if nextItem then C_Container.UseContainerItem(nextItem.bag, nextItem.slot) end
end

local sellButton
function BP:UpdateSellButton()
    local show = self.enabled and self.merchantOpen and self:Get("merchantButton")
    if not show then
        if sellButton then sellButton:Hide() end
        return
    end
    local _, n = self:NextJunk()
    if not sellButton then
        sellButton = W.Button(UIParent, "", "primary", 170, 26)
        sellButton:SetFrameStrata("HIGH")
        sellButton:SetScript("OnClick", function() BP:SellOne() end)
        W.Tooltip(sellButton, L.JUNK_SELL_TITLE, L.JUNK_SELL_TIP)
    end
    sellButton:ClearAllPoints()
    if MerchantFrame and MerchantFrame:IsShown() then
        sellButton:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 60, 4)
    else
        sellButton:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    sellButton:SetLabel(L.JUNK_SELL:format(n))
    sellButton:SetShown(n > 0)
end

local function OnTooltipItem(tooltip)
    if not (BP.enabled and BP:Get("tooltip")) or tooltip ~= GameTooltip then return end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link or ns.IsSecret(link) then return end
    local id = C_Item.GetItemInfoInstant(link)
    if id and ns.db.junk[id] then
        tooltip:AddLine("|cff38c6f4Hawary's|r |cffff7070" .. L.JUNK_MARKED .. "|r")
        tooltip:Show()
    end
end

---------------------------------------------------------------------------
-- Page: categories + junk list with a drop slot
---------------------------------------------------------------------------
function BP:BuildPage(content, width, y)
    local cats = W.Card(content)
    cats:SetPoint("TOPLEFT", 0, y)
    cats:SetWidth(width)
    local head = W.Label(cats, L.BAGCAT_TITLE, "h2", "text")
    head:SetPoint("TOPLEFT", 16, -14)
    local pool = {}
    local labels = {}
    local function icon(i)
        local b = pool[i]
        if b then return b end
        b = CreateFrame("Button", nil, cats)
        b:SetSize(30, 30)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.count = W.Label(b, "", "small", "text", "RIGHT")
        b.count:SetPoint("BOTTOMRIGHT", -1, 1)
        b:SetScript("OnEnter", function(self)
            if not self.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pool[i] = b
        return b
    end
    local perRow = math.floor((width - 32) / 33)

    -- Junk list card
    local junk = W.Card(content)
    junk:SetWidth(width)
    local jh = W.Label(junk, L.JUNK_TITLE, "h2", "text")
    jh:SetPoint("TOPLEFT", 16, -14)
    local drop = CreateFrame("Button", nil, junk)
    drop:SetSize(width - 32, 40)
    drop:SetPoint("TOPLEFT", 16, -40)
    drop.bg = T.Shape(drop, "round_sm_line", "accent2", "BACKGROUND")
    drop.text = W.Label(drop, L.JUNK_DROP, "body", "text2", "CENTER")
    drop.text:SetPoint("CENTER")
    local function take()
        local kind, itemID = GetCursorInfo()
        if kind == "item" and itemID then
            BP:AddJunk(itemID)
            ClearCursor()
        end
    end
    drop:SetScript("OnReceiveDrag", take)
    drop:SetScript("OnClick", take)
    local junkRows = {}

    local function fill()
        for _, b in ipairs(pool) do b:Hide() end
        for _, l in ipairs(labels) do l:Hide() end
        local groups = BP:Scan()
        local yy, n, li = -40, 0, 0
        for _, cat in ipairs(BP.CATEGORIES) do
            local items = groups[cat.id]
            if items and #items > 0 then
                li = li + 1
                local lab = labels[li] or W.Label(cats, "", "small", "accent")
                labels[li] = lab
                lab:ClearAllPoints()
                lab:SetPoint("TOPLEFT", 16, yy)
                lab:SetText(L["BAGCAT_" .. cat.id] .. "  |cff" .. T.hex("text3") .. #items .. "|r")
                lab:Show()
                yy = yy - 18
                for i, it in ipairs(items) do
                    n = n + 1
                    local b = icon(n)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 16 + ((i - 1) % perRow) * 33, yy - math.floor((i - 1) / perRow) * 33)
                    b.tex:SetTexture(it.icon)
                    b.count:SetText(it.count > 1 and it.count or "")
                    b.link = it.link
                    b:Show()
                end
                yy = yy - math.ceil(#items / perRow) * 33 - 8
            end
        end
        if n == 0 then
            li = li + 1
            local lab = labels[li] or W.Label(cats, "", "small", "text3")
            labels[li] = lab
            lab:ClearAllPoints(); lab:SetPoint("TOPLEFT", 16, yy); lab:SetText(L.BAGCAT_EMPTY); lab:Show()
            yy = yy - 20
        end
        cats:SetHeight(-yy + 8)

        -- junk list rows
        for _, r in ipairs(junkRows) do r:Hide() end
        local jy, i = -92, 0
        for _, id in ipairs(U.sortedKeys(ns.db.junk)) do
            i = i + 1
            local r = junkRows[i]
            if not r then
                r = CreateFrame("Frame", nil, junk)
                r:SetHeight(24)
                r.name = W.Label(r, "", "body", "text")
                r.name:SetPoint("LEFT", 0, 0)
                r.del = W.Button(r, L.DELETE, "secondary", 70, 20)
                r.del:SetPoint("RIGHT", 0, 0)
                junkRows[i] = r
            end
            r:SetPoint("TOPLEFT", 16, jy); r:SetPoint("RIGHT", junk, "RIGHT", -16, 0)
            local _, link = C_Item.GetItemInfo(id)
            r.name:SetText(link or C_Item.GetItemNameByID(id) or ("item " .. id))
            r.del:SetScript("OnClick", function() BP:RemoveJunk(id) end)
            r:Show()
            jy = jy - 26
        end
        if i == 0 then
            junkRows.empty = junkRows.empty or W.Label(junk, L.JUNK_EMPTY, "small", "text3")
            junkRows.empty:SetPoint("TOPLEFT", 16, jy)
            junkRows.empty:Show()
            jy = jy - 20
        elseif junkRows.empty then junkRows.empty:Hide() end
        junk:SetHeight(-jy + 10)
        junk:ClearAllPoints()
        junk:SetPoint("TOPLEFT", cats, "BOTTOMLEFT", 0, -16)
        content:SetHeight(-y + cats:GetHeight() + junk:GetHeight() + 60)
    end
    BP.pageFill = fill
    fill()
    return y - cats:GetHeight() - junk:GetHeight() - 40
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function BP:OnInitialize()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) ns.Safe(OnTooltipItem, tooltip) end)
    end
end

function BP:OnEnable()
    self:RegisterEvent("MERCHANT_SHOW", function() BP.merchantOpen = true; BP:UpdateSellButton() end)
    self:RegisterEvent("MERCHANT_CLOSED", function() BP.merchantOpen = false; BP:UpdateSellButton() end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        BP:UpdateSellButton()
        if BP.pageFill and ns.window and ns.window:IsShown() then BP.pageFill() end
    end)
end

function BP:OnDisable() self:UpdateSellButton() end

ns:On("JUNK_CHANGED", function()
    BP:UpdateSellButton()
    if BP.pageFill then BP.pageFill() end
end)
