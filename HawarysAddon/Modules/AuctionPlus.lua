-- Hawary's Addon: Auction House+ (Auctionator style)
-- A panel next to the auction house with three tabs:
--   Shopping   – shopping lists, search history, crafting needs; click a result to see listings and buy
--   Selling    – your sellable items with a suggested undercut price, a price floor, deposit and Post
--   Cancelling – your auctions, an undercut check and one-click Cancel
-- Rule (Blizzard's add-on policy): every buy, post and cancel happens only when YOU click the
-- button, one action per click. Nothing runs on its own, nothing loops purchases.
local _, ns = ...
local L, T, W, U = ns.L, ns.Theme, ns.W, ns.Util

local AH = ns:NewModule("ahplus", {
    title = L.MOD_AHPLUS,
    desc = L.MOD_AHPLUS_DESC,
    order = 23,
    defaults = { open = true, undercut = 1, undercutPct = 0, floorPct = 50, duration = 2,
        lists = { { name = "Shopping", items = {} } }, history = {}, list = 1 },
})

AH.options = {
    { type = "toggle", key = "open", label = L.AHP_OPEN, desc = L.AHP_OPEN_DESC },
    { type = "slider", key = "undercut", label = L.AHP_UNDERCUT, desc = L.AHP_UNDERCUT_DESC, min = 0, max = 100, step = 1 },
    { type = "slider", key = "undercutPct", label = L.AHP_UNDERCUT_PCT, desc = L.AHP_UNDERCUT_PCT_DESC, min = 0, max = 20, step = 1 },
    { type = "slider", key = "floorPct", label = L.AHP_FLOOR, desc = L.AHP_FLOOR_DESC, min = 0, max = 100, step = 5 },
    { type = "dropdown", key = "duration", label = L.AHP_DURATION, desc = L.AHP_DURATION_DESC, values = function()
        return { { value = 1, text = L.AHP_12H }, { value = 2, text = L.AHP_24H }, { value = 3, text = L.AHP_48H } }
    end },
}

local SORT_PRICE = { { sortOrder = 0, reverseSort = false } } -- Enum.AuctionHouseSortOrder.Price
local panel
local tabs, pages = {}, {}
AH.pages = pages -- for the test suite

---------------------------------------------------------------------------
-- Pure helpers (unit-tested)
---------------------------------------------------------------------------
-- Suggested price: lowest minus a copper undercut and/or a percent, never below the floor.
-- Returns price, wasFloored.
function AH.Undercut(lowest, undercutCopper, undercutPct, floor)
    if not lowest or lowest <= 0 then
        if floor and floor > 0 then return floor, false end
        return nil, false
    end
    local p = lowest - (undercutCopper or 0)
    if undercutPct and undercutPct > 0 then p = math.min(p, math.floor(lowest * (100 - undercutPct) / 100)) end
    if p < 1 then p = 1 end
    if floor and p < floor then return floor, true end
    return p, false
end

-- The game may only allow whole silver: round DOWN to 100 copper (never above what you typed).
function AH.RoundPrice(copper, copperAllowed)
    copper = math.floor(copper or 0)
    if copperAllowed then return copper end
    local p = math.floor(copper / 100) * 100
    if p < 100 and copper > 0 then p = 100 end
    return p
end

-- "12g 50s 3c", "12.5", "12,5", "50s", "7c", "1200" (= gold) -> copper (or nil)
function AH.ParseMoney(text)
    if type(text) ~= "string" then return nil end
    text = text:lower():gsub(",", "."):gsub("%s+", " ")
    if text:match("^%s*$") then return nil end
    local g, s, c = text:match("([%d%.]+)%s*g"), text:match("([%d%.]+)%s*s"), text:match("([%d%.]+)%s*c")
    if g or s or c then
        local total = (tonumber(g) or 0) * 10000 + (tonumber(s) or 0) * 100 + (tonumber(c) or 0)
        return math.floor(total + 0.5)
    end
    local n = tonumber(text:match("^%s*([%d%.]+)%s*$"))
    if n then return math.floor(n * 10000 + 0.5) end
    return nil
end

-- Shopping term: '"Linen Cloth"' means exact name; anything else is a part of the name.
function AH.ParseTerm(term)
    term = U.trim(term or "")
    local exact = term:match('^"(.+)"$')
    if exact then return exact, true end
    return term, false
end

-- Add a term to the front of the history (no duplicates, max n). Returns the list.
function AH.PushHistory(list, term, n)
    for i = #list, 1, -1 do if list[i] == term then table.remove(list, i) end end
    table.insert(list, 1, term)
    while #list > (n or 15) do table.remove(list) end
    return list
end

local function LinkName(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

---------------------------------------------------------------------------
-- Small list widget: fixed rows, mouse wheel scrolling
---------------------------------------------------------------------------
local function MakeList(parent, n, rowH, onClick)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.data, list.offset = {}, {}, 0
    for i = 1, n do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(rowH)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 2))
        r:SetPoint("RIGHT", 0, 0)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0.03)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(rowH - 4, rowH - 4)
        r.icon:SetPoint("LEFT", 2, 0)
        r.left = W.Label(r, "", "small", "text")
        r.left:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.left:SetWordWrap(false)
        r.right = W.Label(r, "", "small", "text2", "RIGHT")
        r.right:SetPoint("RIGHT", -6, 0)
        r.left:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        r:SetScript("OnClick", function(self, btn) if self.item then onClick(self.item, btn, self) end end)
        r:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(1, 1, 1, 0.09)
            if self.item and self.item.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.item.link)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(1, 1, 1, self.item and self.item.selected and 0.14 or 0.03)
            GameTooltip:Hide()
        end)
        list.rows[i] = r
    end
    list:SetHeight(n * (rowH + 2))
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, d)
        self.offset = math.max(0, math.min(#self.data - #self.rows, self.offset - d))
        self:Paint()
    end)
    function list:Set(data) self.data = data or {}; self.offset = 0; self:Paint() end
    function list:Paint()
        for i, r in ipairs(self.rows) do
            local item = self.data[self.offset + i]
            r.item = item
            if item then
                r.icon:SetTexture(item.icon)
                r.left:SetText(item.left or "")
                r.right:SetText(item.right or "")
                r.bg:SetColorTexture(1, 1, 1, item.selected and 0.14 or 0.03)
                r:Show()
            else
                r:Hide()
            end
        end
    end
    return list
end

local function NameAndIcon(itemKey)
    local info = itemKey and C_AuctionHouse.GetItemKeyInfo(itemKey, false)
    if info and info.itemName then return info.itemName, info.iconFileID, info.isCommodity, info.quality end
    local id = itemKey and itemKey.itemID
    local name = id and C_Item.GetItemInfo(id)
    return name or ("item:" .. tostring(id)), id and C_Item.GetItemIconByID(id), nil, nil
end

local function Colored(name, quality)
    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name) end
    end
    return name
end

local function Money(c) return c and U.money(c) or "–" end

---------------------------------------------------------------------------
-- One query at a time: the auction house throttles searches
---------------------------------------------------------------------------
local queue = {}
local function RunQueue()
    if #queue == 0 or AH.waiting then return end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    local job = table.remove(queue, 1)
    AH.waiting = job
    job.send()
end
local function Enqueue(job)
    queue[#queue + 1] = job
    RunQueue()
end
local function Done(kind)
    local job = AH.waiting
    if job and job.kind == kind then
        AH.waiting = nil
        ns.Safe(job.done)
    end
    C_Timer.After(0.05, RunQueue)
end

---------------------------------------------------------------------------
-- Shopping tab
---------------------------------------------------------------------------
local shop = { results = {}, detail = nil }

local function CurrentList()
    local lists = AH:DB().lists
    if #lists == 0 then lists[1] = { name = "Shopping", items = {} } end
    local i = math.min(AH:Get("list") or 1, #lists)
    return lists[i], i
end

local function AddResults(term, exact)
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local name, icon, _, quality = NameAndIcon(r.itemKey)
        if not exact or (name and name:lower() == term:lower()) then
            shop.results[#shop.results + 1] = {
                itemKey = r.itemKey, icon = icon, name = name, price = r.minPrice,
                left = Colored(name or "?", quality),
                right = Money(r.minPrice) .. "  |cff77808fx" .. tostring(r.totalQuantity or 0) .. "|r",
            }
        end
    end
end

function AH:Search(terms)
    if #terms == 0 then return end
    wipe(shop.results)
    shop.detail = nil
    pages.shop.results:Set(shop.results)
    pages.shop.status:SetText(L.AHP_SEARCHING)
    for _, raw in ipairs(terms) do
        local term, exact = AH.ParseTerm(raw)
        Enqueue({ kind = "browse",
            send = function()
                C_AuctionHouse.SendBrowseQuery({ searchString = term, sorts = SORT_PRICE, filters = {}, itemClassFilters = {} })
            end,
            done = function()
                AddResults(term, exact)
                table.sort(shop.results, function(a, b) return (a.name or "") < (b.name or "") end)
                pages.shop.results:Set(shop.results)
                pages.shop.status:SetText(L.AHP_RESULTS:format(#shop.results))
            end })
    end
end

function AH:SearchItemIDs(ids)
    if #ids == 0 then return end
    wipe(shop.results)
    local keys = {}
    for _, id in ipairs(ids) do keys[#keys + 1] = C_AuctionHouse.MakeItemKey(id, 0, 0, 0) end
    pages.shop.status:SetText(L.AHP_SEARCHING)
    Enqueue({ kind = "browse",
        send = function() C_AuctionHouse.SearchForItemKeys(keys, SORT_PRICE) end,
        done = function()
            AddResults("", false)
            pages.shop.results:Set(shop.results)
            pages.shop.status:SetText(L.AHP_RESULTS:format(#shop.results))
        end })
end

-- Listings for one item (cheapest first) with a Buy button
function AH:OpenDetail(entry)
    shop.detail = { itemKey = entry.itemKey, name = entry.name, title = entry.left or entry.name, rows = {} }
    shop.buy, shop.selected = nil, nil
    local p = pages.shop
    p.detailTitle:SetText(shop.detail.title or "")
    p.listings:Set({})
    p.buy:Disable()
    p.buy:SetLabel(L.AHP_BUY)
    Enqueue({ kind = "sell",
        send = function() C_AuctionHouse.SendSellSearchQuery(entry.itemKey, SORT_PRICE, true) end,
        done = function() AH:FillDetail() end })
end

function AH:FillDetail()
    local d = shop.detail
    if not d then return end
    local rows = {}
    local _, _, isCommodity = NameAndIcon(d.itemKey)
    local id = d.itemKey.itemID
    if isCommodity then
        d.commodity = true
        for i = 1, math.min(C_AuctionHouse.GetNumCommoditySearchResults(id), 50) do
            local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
            if r then
                rows[#rows + 1] = { unit = r.unitPrice, qty = r.quantity, mine = r.containsOwnerItem,
                    left = Money(r.unitPrice) .. (r.containsOwnerItem and ("  |cff38c6f4" .. L.AHP_YOURS .. "|r") or ""),
                    right = "x" .. tostring(r.quantity) }
            end
        end
    else
        d.commodity = false
        for i = 1, math.min(C_AuctionHouse.GetNumItemSearchResults(d.itemKey), 50) do
            local r = C_AuctionHouse.GetItemSearchResultInfo(d.itemKey, i)
            if r and r.buyoutAmount then
                rows[#rows + 1] = { auctionID = r.auctionID, buyout = r.buyoutAmount, link = r.itemLink, mine = r.containsOwnerItem,
                    left = Money(r.buyoutAmount) .. (r.containsOwnerItem and ("  |cff38c6f4" .. L.AHP_YOURS .. "|r") or ""),
                    right = (r.quantity and r.quantity > 1) and ("x" .. r.quantity) or "" }
            end
        end
    end
    d.rows = rows
    local p = pages.shop
    p.listings:Set(rows)
    p.qty:SetShown(d.commodity)
    p.qtyLabel:SetShown(d.commodity)
    p.buy:SetEnabled(d.commodity and #rows > 0)
    p.status:SetText(#rows == 0 and L.AHP_NONE_LISTED or "")
    -- remember the lowest price for tooltips (Market module)
    local market = ns.modules.market
    if market and #rows > 0 then
        local low = rows[1].unit or rows[1].buyout
        if low then ns.MarketData.StorePrices(market:Store(), { [id] = low }, time()) end
    end
end

-- Buy button: the first click asks the server for the price (commodities) or arms the selected
-- auction; the second click confirms. One purchase per two clicks, never automatic.
function AH:BuyClick()
    local d = shop.detail
    if not d then return end
    local p = pages.shop
    if d.commodity then
        local qty = math.floor(tonumber(p.qty:GetText()) or 1) -- empty box = 1
        if qty < 1 then return end
        if shop.buy and shop.buy.ready then
            C_AuctionHouse.ConfirmCommoditiesPurchase(d.itemKey.itemID, shop.buy.qty)
            shop.buy = nil
            p.buy:SetLabel(L.AHP_BUYING)
            p.buy:Disable()
        else
            shop.buy = { qty = qty }
            C_AuctionHouse.StartCommoditiesPurchase(d.itemKey.itemID, qty)
            p.buy:SetLabel(L.AHP_PRICE_CHECK)
        end
    else
        local sel = shop.selected
        if not sel then return end
        if shop.buy and shop.buy.auctionID == sel.auctionID then
            C_AuctionHouse.PlaceBid(sel.auctionID, sel.buyout)
            shop.buy = nil
            p.buy:SetLabel(L.AHP_BUYING)
            p.buy:Disable()
        else
            shop.buy = { auctionID = sel.auctionID }
            p.buy:SetLabel(L.AHP_CONFIRM_BUY:format(Money(sel.buyout)))
        end
    end
end

local function BuildShop(page)
    local p = {}
    p.listDrop = W.Dropdown(page, 140, function()
        local out = {}
        for i, l in ipairs(AH:DB().lists) do out[#out + 1] = { value = i, text = l.name } end
        return out
    end, function() return AH:Get("list") end, function(v) AH:Set("list", v); AH:PaintTerms() end)
    p.listDrop:SetPoint("TOPLEFT", 0, 0)
    local newList = W.Button(page, "+", "ghost", 26, 22)
    newList:SetPoint("LEFT", p.listDrop, "RIGHT", 4, 0)
    W.Tooltip(newList, L.AHP_NEW_LIST)
    newList:SetScript("OnClick", function()
        W.TextDialog(L.AHP_NEW_LIST, "", false, function(text)
            text = U.trim(text or "")
            if text == "" then return end
            table.insert(AH:DB().lists, { name = text, items = {} })
            AH:Set("list", #AH:DB().lists)
            p.listDrop:Refresh()
            AH:PaintTerms()
        end)
    end)
    local delList = W.Button(page, "-", "ghost", 26, 22)
    delList:SetPoint("LEFT", newList, "RIGHT", 2, 0)
    W.Tooltip(delList, L.AHP_DEL_LIST)
    delList:SetScript("OnClick", function()
        local lists = AH:DB().lists
        local _, i = CurrentList()
        if #lists > 1 then table.remove(lists, i); AH:Set("list", 1); p.listDrop:Refresh(); AH:PaintTerms() end
    end)

    p.term = W.EditBox(page, 200, 22)
    p.term:SetPoint("TOPLEFT", 0, -28)
    p.term.edit:SetScript("OnEnterPressed", function(self)
        local t = U.trim(self:GetText() or "")
        self:ClearFocus()
        if t == "" then return end
        AH.PushHistory(AH:DB().history, t, 15)
        AH:Search({ t })
    end)
    local add = W.Button(page, L.AHP_ADD, "secondary", 60, 22)
    add:SetPoint("LEFT", p.term, "RIGHT", 4, 0)
    W.Tooltip(add, L.AHP_ADD, L.AHP_ADD_DESC)
    add:SetScript("OnClick", function()
        local t = U.trim(p.term:GetText() or "")
        if t == "" then return end
        table.insert(CurrentList().items, t)
        p.term:SetText("")
        AH:PaintTerms()
    end)
    local go = W.Button(page, L.AHP_SEARCH, "primary", 70, 22)
    go:SetPoint("LEFT", add, "RIGHT", 4, 0)
    go:SetScript("OnClick", function()
        local t = U.trim(p.term:GetText() or "")
        if t ~= "" then AH.PushHistory(AH:DB().history, t, 15); AH:Search({ t }) end
    end)

    p.terms = MakeList(page, 5, 18, function(item, btn)
        if btn == "RightButton" then
            table.remove(CurrentList().items, item.index)
            AH:PaintTerms()
        else
            AH:Search({ item.term })
        end
    end)
    p.terms:SetPoint("TOPLEFT", 0, -56)
    p.terms:SetPoint("RIGHT", page, "RIGHT", -150, 0)

    local runList = W.Button(page, L.AHP_SEARCH_LIST, "primary", 140, 22)
    runList:SetPoint("TOPRIGHT", 0, -56)
    runList:SetScript("OnClick", function() AH:Search(CurrentList().items) end)
    local hist = W.Button(page, L.AHP_HISTORY, "secondary", 140, 22)
    hist:SetPoint("TOP", runList, "BOTTOM", 0, -6)
    hist:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(L.AHP_HISTORY)
            for _, t in ipairs(AH:DB().history) do
                root:CreateButton(t, function() AH:Search({ t }) end)
            end
        end)
    end)
    local craft = W.Button(page, L.AHP_CRAFT_NEEDS, "secondary", 140, 22)
    craft:SetPoint("TOP", hist, "BOTTOM", 0, -6)
    W.Tooltip(craft, L.AHP_CRAFT_NEEDS, L.AHP_CRAFT_NEEDS_DESC)
    craft:SetScript("OnClick", function()
        local prof = ns.modules.professions
        local ids = {}
        if prof and prof.ShoppingRows then
            for _, r in ipairs(prof:ShoppingRows()) do if r.missing > 0 then ids[#ids + 1] = r.itemID end end
        end
        if #ids == 0 then ns:Print(L.AHP_NO_NEEDS) else AH:SearchItemIDs(ids) end
    end)

    p.status = W.Label(page, "", "small", "text3")
    p.status:SetPoint("TOPLEFT", 0, -158)
    p.results = MakeList(page, 8, 20, function(item) AH:OpenDetail(item) end)
    p.results:SetPoint("TOPLEFT", 0, -176)
    p.results:SetPoint("RIGHT", 0, 0)

    p.detailTitle = W.Label(page, "", "h2", "text")
    p.detailTitle:SetPoint("TOPLEFT", 0, -358)
    p.listings = MakeList(page, 6, 18, function(item)
        if shop.detail and shop.detail.commodity then return end
        for _, r in ipairs(shop.detail and shop.detail.rows or {}) do r.selected = (r == item) end
        shop.selected = item
        shop.buy = nil
        p.listings:Paint()
        p.buy:SetLabel(L.AHP_BUY)
        p.buy:SetEnabled(not item.mine)
    end)
    p.listings:SetPoint("TOPLEFT", 0, -380)
    p.listings:SetPoint("RIGHT", 0, 0)
    p.qtyLabel = W.Label(page, L.AHP_QTY, "small", "text2")
    p.qtyLabel:SetPoint("BOTTOMLEFT", 0, 6)
    p.qty = W.EditBox(page, 60, 22)
    p.qty:SetPoint("LEFT", p.qtyLabel, "RIGHT", 6, 0)
    p.qty:SetText("1")
    p.qty.edit:SetScript("OnTextChanged", function()
        if shop.buy then shop.buy = nil; p.buy:SetLabel(L.AHP_BUY) end
    end)
    p.buy = W.Button(page, L.AHP_BUY, "primary", 190, 26)
    p.buy:SetPoint("BOTTOMRIGHT", 0, 0)
    p.buy:SetScript("OnClick", function() AH:BuyClick() end)
    W.Tooltip(p.buy, L.AHP_BUY, L.AHP_BUY_DESC)
    p.buy:Disable()
    return p
end

function AH:PaintTerms()
    if not pages.shop then return end
    local data = {}
    for i, t in ipairs(CurrentList().items) do
        data[#data + 1] = { term = t, index = i, left = t, right = "|cff77808f" .. L.AHP_RIGHT_REMOVE .. "|r", icon = 134400 }
    end
    pages.shop.terms:Set(data)
end

---------------------------------------------------------------------------
-- Selling tab
---------------------------------------------------------------------------
local sell = {}

local function SellableItems()
    local seen, out = {}, {}
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound and not seen[info.itemID] then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if C_AuctionHouse.IsSellItemValid(loc, false) then
                    seen[info.itemID] = true
                    local count = C_Item.GetItemCount(info.itemID, false, false, false, false)
                    out[#out + 1] = { loc = loc, itemID = info.itemID, link = info.hyperlink, icon = info.iconFileID,
                        count = count, left = info.hyperlink, right = "x" .. tostring(count) }
                end
            end
        end
    end
    table.sort(out, function(a, b) return (LinkName(a.link) or "") < (LinkName(b.link) or "") end)
    return out
end

function AH:PaintSell()
    if not pages.sell then return end
    sell.items = SellableItems()
    pages.sell.items:Set(sell.items)
end

-- Lowest price you allow: vendor price + 1 copper, and floorPct % of the price the Market module remembers
function AH:Floor(itemID)
    local floor = 0
    local vendor = select(11, C_Item.GetItemInfo(itemID))
    if vendor and vendor > 0 then floor = vendor + 1 end
    local market = ns.modules.market
    local pct = self:Get("floorPct") or 0
    if market and pct > 0 then
        local known = market:Price(itemID)
        if known then floor = math.max(floor, math.floor(known * pct / 100)) end
    end
    return floor
end

function AH:SelectSell(item)
    for _, it in ipairs(sell.items or {}) do it.selected = (it == item) end
    pages.sell.items:Paint()
    sell.item, sell.confirm = item, nil
    local p = pages.sell
    p.title:SetText(item.link or "")
    p.lowest:SetText(L.AHP_CHECKING)
    p.note:SetText("")
    p.post:SetLabel(L.AHP_POST)
    p.post:Disable()
    sell.commodity = C_AuctionHouse.GetItemCommodityStatus(item.loc) == 2 -- Enum.ItemCommodityStatus.Commodity
    p.qty:SetText(tostring(sell.commodity and item.count or 1))
    local key = C_AuctionHouse.GetItemKeyFromItem(item.loc)
    Enqueue({ kind = "sell",
        send = function() C_AuctionHouse.SendSellSearchQuery(key, SORT_PRICE, true) end,
        done = function() AH:FillSell(key) end })
end

function AH:FillSell(key)
    local item = sell.item
    if not item then return end
    local lowest, mineLowest
    if sell.commodity then
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(item.itemID, 1)
        if r then lowest, mineLowest = r.unitPrice, r.containsOwnerItem end
    else
        local r = C_AuctionHouse.GetItemSearchResultInfo(key, 1)
        if r then lowest, mineLowest = r.buyoutAmount, r.containsOwnerItem end
    end
    local floor = self:Floor(item.itemID)
    local price, floored
    if mineLowest then
        price, floored = lowest, false -- you already have the cheapest one: don't undercut yourself
    else
        price, floored = AH.Undercut(lowest, self:Get("undercut"), self:Get("undercutPct"), floor)
    end
    price = AH.RoundPrice(price or floor, C_AuctionHouse.SupportsCopperValues())
    local p = pages.sell
    p.lowest:SetText(lowest and L.AHP_LOWEST:format(Money(lowest)) or L.AHP_NONE_LISTED)
    p.price:SetText(U.money(price, true))
    p.note:SetText(floored and L.AHP_FLOORED:format(Money(floor)) or "")
    p.post:SetEnabled(price > 0)
    self:UpdateDeposit()
end

function AH:UpdateDeposit()
    local item = sell.item
    if not (item and pages.sell) then return end
    local qty = math.floor(tonumber(pages.sell.qty:GetText()) or 1)
    local dur = self:Get("duration")
    local dep
    if sell.commodity then dep = C_AuctionHouse.CalculateCommodityDeposit(item.itemID, dur, qty)
    else dep = C_AuctionHouse.CalculateItemDeposit(item.loc, dur, qty) end
    pages.sell.deposit:SetText(L.AHP_DEPOSIT:format(Money(dep)))
end

-- Post button: one post per click; if the game asks for confirmation, the next click confirms.
function AH:PostClick()
    local item = sell.item
    if not item then return end
    local p = pages.sell
    local price = AH.RoundPrice(AH.ParseMoney(p.price:GetText()) or 0, C_AuctionHouse.SupportsCopperValues())
    local qty = math.floor(tonumber(p.qty:GetText()) or 0)
    if price <= 0 or qty <= 0 then ns:Print(L.AHP_BAD_PRICE); return end
    local floor = self:Floor(item.itemID)
    if price < floor and not IsShiftKeyDown() then ns:Print(L.AHP_BELOW_FLOOR, U.money(floor)); return end
    local dur = self:Get("duration")
    if sell.confirm then
        if sell.commodity then C_AuctionHouse.ConfirmPostCommodity(item.loc, dur, qty, price)
        else C_AuctionHouse.ConfirmPostItem(item.loc, dur, qty, nil, price) end
        sell.confirm = nil
        p.post:SetLabel(L.AHP_POST)
        return
    end
    local needs
    if sell.commodity then needs = C_AuctionHouse.PostCommodity(item.loc, dur, qty, price)
    else needs = C_AuctionHouse.PostItem(item.loc, dur, qty, nil, price) end
    if needs then
        sell.confirm = true
        p.post:SetLabel(L.AHP_CONFIRM_POST)
    end
end

local function BuildSell(page)
    local p = {}
    p.items = MakeList(page, 10, 20, function(item) AH:SelectSell(item) end)
    p.items:SetPoint("TOPLEFT", 0, 0)
    p.items:SetPoint("RIGHT", 0, 0)
    local refresh = W.Button(page, L.AHP_REFRESH, "ghost", 80, 20)
    refresh:SetPoint("TOPRIGHT", p.items, "BOTTOMRIGHT", 0, -4)
    refresh:SetScript("OnClick", function() AH:PaintSell() end)
    p.title = W.Label(page, "", "h2", "text")
    p.title:SetPoint("TOPLEFT", 0, -250)
    p.lowest = W.Label(page, "", "body", "text2")
    p.lowest:SetPoint("TOPLEFT", 0, -276)
    local priceLabel = W.Label(page, L.AHP_PRICE, "small", "text2")
    priceLabel:SetPoint("TOPLEFT", 0, -306)
    p.price = W.EditBox(page, 150, 24)
    p.price:SetPoint("TOPLEFT", 0, -322)
    p.price.edit:SetScript("OnTextChanged", function()
        if sell.confirm then sell.confirm = nil; p.post:SetLabel(L.AHP_POST) end
    end)
    local qtyLabel = W.Label(page, L.AHP_QTY, "small", "text2")
    qtyLabel:SetPoint("TOPLEFT", 170, -306)
    p.qty = W.EditBox(page, 70, 24)
    p.qty:SetPoint("TOPLEFT", 170, -322)
    p.qty.edit:SetScript("OnTextChanged", function() ns.Safe(AH.UpdateDeposit, AH) end)
    local durDrop = W.Dropdown(page, 110, function()
        return { { value = 1, text = L.AHP_12H }, { value = 2, text = L.AHP_24H }, { value = 3, text = L.AHP_48H } }
    end, function() return AH:Get("duration") end, function(v) AH:Set("duration", v); AH:UpdateDeposit() end)
    durDrop:SetPoint("TOPLEFT", 256, -322)
    p.deposit = W.Label(page, "", "small", "text3")
    p.deposit:SetPoint("TOPLEFT", 0, -356)
    p.note = W.Label(page, "", "small", "warn")
    p.note:SetPoint("TOPLEFT", 0, -374)
    p.note:SetPoint("RIGHT", 0, 0)
    p.note:SetWordWrap(true)
    p.post = W.Button(page, L.AHP_POST, "primary", 190, 26)
    p.post:SetPoint("BOTTOMRIGHT", 0, 0)
    p.post:SetScript("OnClick", function() AH:PostClick() end)
    W.Tooltip(p.post, L.AHP_POST, L.AHP_POST_DESC)
    p.post:Disable()
    return p
end

---------------------------------------------------------------------------
-- Cancelling tab
---------------------------------------------------------------------------
local cancel = { rows = {} }

function AH:PaintOwned()
    if not pages.cancel then return end
    local rows = {}
    for _, a in ipairs(C_AuctionHouse.GetOwnedAuctions() or {}) do
        if a.status == 0 then -- Enum.AuctionStatus.Active
            local name, icon, _, quality = NameAndIcon(a.itemKey)
            local under = cancel.under and cancel.under[a.auctionID]
            rows[#rows + 1] = { auctionID = a.auctionID, itemKey = a.itemKey, link = a.itemLink, icon = icon,
                price = a.buyoutAmount, under = under,
                selected = cancel.selected and cancel.selected.auctionID == a.auctionID,
                left = (under and ("|cfff87171" .. L.AHP_UNDERCUT_TAG .. "|r  ") or "") .. Colored(name or "?", quality)
                    .. "  |cff77808fx" .. tostring(a.quantity) .. "|r",
                right = Money(a.buyoutAmount) }
        end
    end
    cancel.rows = rows
    pages.cancel.list:Set(rows)
    local n = 0
    for _, r in ipairs(rows) do if r.under then n = n + 1 end end
    pages.cancel.status:SetText(L.AHP_OWNED:format(#rows, n))
    pages.cancel.next:SetEnabled(n > 0)
end

-- Check every auction of yours against the cheapest listing (one search at a time)
function AH:ScanUndercuts()
    cancel.under = {}
    local seen = {}
    for _, r in ipairs(cancel.rows) do
        local id = r.itemKey and r.itemKey.itemID
        if id and not seen[id] then
            seen[id] = true
            local key = r.itemKey
            Enqueue({ kind = "sell",
                send = function() C_AuctionHouse.SendSellSearchQuery(key, SORT_PRICE, true) end,
                done = function()
                    local lowest, mine
                    local info = C_AuctionHouse.GetItemKeyInfo(key, false)
                    if info and info.isCommodity then
                        local c = C_AuctionHouse.GetCommoditySearchResultInfo(id, 1)
                        if c then lowest, mine = c.unitPrice, c.containsOwnerItem end
                    else
                        local c = C_AuctionHouse.GetItemSearchResultInfo(key, 1)
                        if c then lowest, mine = c.buyoutAmount, c.containsOwnerItem end
                    end
                    for _, row in ipairs(cancel.rows) do
                        if row.itemKey and row.itemKey.itemID == id and lowest and not mine and row.price and lowest < row.price then
                            cancel.under[row.auctionID] = true
                        end
                    end
                    AH:PaintOwned()
                end })
        end
    end
    pages.cancel.status:SetText(L.AHP_SCANNING)
end

function AH:CancelOne(row)
    if not row or not C_AuctionHouse.CanCancelAuction(row.auctionID) then return end
    C_AuctionHouse.CancelAuction(row.auctionID)
end

local function BuildCancel(page)
    local p = {}
    p.status = W.Label(page, "", "small", "text3")
    p.status:SetPoint("TOPLEFT", 0, 0)
    local scan = W.Button(page, L.AHP_SCAN_UNDERCUT, "primary", 160, 22)
    scan:SetPoint("TOPRIGHT", 0, 4)
    scan:SetScript("OnClick", function() AH:ScanUndercuts() end)
    p.list = MakeList(page, 18, 20, function(item)
        for _, r in ipairs(cancel.rows) do r.selected = (r == item) end
        cancel.selected = item
        p.list:Paint()
        p.cancel:Enable()
        p.cancel:SetLabel(L.AHP_CANCEL_COST:format(Money(C_AuctionHouse.GetCancelCost(item.auctionID))))
    end)
    p.list:SetPoint("TOPLEFT", 0, -28)
    p.list:SetPoint("RIGHT", 0, 0)
    p.cancel = W.Button(page, L.AHP_CANCEL, "danger", 190, 26)
    p.cancel:SetPoint("BOTTOMRIGHT", 0, 0)
    p.cancel:SetScript("OnClick", function() AH:CancelOne(cancel.selected) end)
    p.cancel:Disable()
    p.next = W.Button(page, L.AHP_CANCEL_NEXT, "secondary", 190, 26)
    p.next:SetPoint("RIGHT", p.cancel, "LEFT", -8, 0)
    W.Tooltip(p.next, L.AHP_CANCEL_NEXT, L.AHP_CANCEL_NEXT_DESC)
    p.next:SetScript("OnClick", function()
        for _, r in ipairs(cancel.rows) do
            if r.under then AH:CancelOne(r); return end
        end
    end)
    p.next:Disable()
    return p
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
function AH:ShowTab(id)
    for k, page in pairs(tabs) do
        page.frame:SetShown(k == id)
        page.button.kind = (k == id) and "primary" or "secondary"
        if page.button.Paint then page.button:Paint(false) end
    end
    self.tab = id
    if id == "sell" then
        self:PaintSell()
    elseif id == "cancel" then
        C_AuctionHouse.QueryOwnedAuctions(SORT_PRICE)
    end
end

function AH:Build()
    if panel or not AuctionHouseFrame then return panel end
    panel = CreateFrame("Frame", "HawarysAddonAuctionPanel", AuctionHouseFrame)
    panel:SetWidth(440)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 6, 0)
    panel:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 6, 0)
    panel:EnableMouse(true)
    panel.bg = T.Shape(panel, "round", "window", "BACKGROUND", 0)
    panel.border = T.Shape(panel, "round_line", "line", "BORDER", 0)
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.media .. "logo")
    logo:SetSize(22, 22)
    logo:SetPoint("TOPLEFT", 14, -12)
    local title = W.Label(panel, L.MOD_AHPLUS, "h2", "text")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)

    local x = 14
    for _, def in ipairs({ { "shop", L.AHP_TAB_SHOP, BuildShop }, { "sell", L.AHP_TAB_SELL, BuildSell },
        { "cancel", L.AHP_TAB_CANCEL, BuildCancel } }) do
        local id, label, builder = def[1], def[2], def[3]
        local btn = W.Button(panel, label, "secondary", 120, 24)
        btn:SetPoint("TOPLEFT", x, -44)
        btn:SetScript("OnClick", function() AH:ShowTab(id) end)
        x = x + 126
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", 14, -80)
        page:SetPoint("BOTTOMRIGHT", -14, 14)
        page:Hide()
        pages[id] = builder(page)
        tabs[id] = { frame = page, button = btn }
    end

    -- Toggle button on the auction house itself
    local toggle = W.Button(AuctionHouseFrame, "Hawary+", "primary", 90, 22)
    toggle:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -172, 4)
    toggle:SetScript("OnClick", function() panel:SetShown(not panel:IsShown()) end)
    W.Tooltip(toggle, L.MOD_AHPLUS, L.AHP_TOGGLE_DESC)
    self.toggle = toggle

    self:PaintTerms()
    self:ShowTab("shop")
    return panel
end

local function ReopenDetail()
    if shop.detail then
        AH:OpenDetail({ itemKey = shop.detail.itemKey, name = shop.detail.name, left = shop.detail.title })
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function AH:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW", function()
        self:Build()
        if panel then panel:SetShown(self:Get("open")); self.toggle:Show() end
    end)
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
        wipe(queue)
        self.waiting = nil
        if shop.buy and shop.detail and shop.detail.commodity then C_AuctionHouse.CancelCommoditiesPurchase() end
        shop.buy, sell.confirm = nil, nil
    end)
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() Done("browse") end)
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", function() Done("sell") end)
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", function() Done("sell") end)
    self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() RunQueue() end)
    self:RegisterEvent("COMMODITY_PRICE_UPDATED", function(_, _, _, total)
        if not (shop.buy and pages.shop) then return end
        shop.buy.ready = true
        pages.shop.buy:SetLabel(L.AHP_CONFIRM_BUY:format(Money(total)))
    end)
    self:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
        ns:Print(L.AHP_BOUGHT)
        shop.buy = nil
        ReopenDetail()
    end)
    self:RegisterEvent("COMMODITY_PURCHASE_FAILED", function()
        shop.buy = nil
        if pages.shop then pages.shop.buy:SetLabel(L.AHP_BUY); pages.shop.buy:Enable() end
    end)
    self:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function()
        ns:Print(L.AHP_BOUGHT)
        shop.selected = nil
        ReopenDetail()
    end)
    self:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED", function()
        sell.confirm = nil
        C_Timer.After(0.3, function() ns.Safe(AH.PaintSell, AH) end)
    end)
    self:RegisterEvent("OWNED_AUCTIONS_UPDATED", function() self:PaintOwned() end)
    self:RegisterEvent("AUCTION_CANCELED", function()
        if pages.cancel then pages.cancel.cancel:Disable(); pages.cancel.cancel:SetLabel(L.AHP_CANCEL) end
        cancel.selected = nil
        C_AuctionHouse.QueryOwnedAuctions(SORT_PRICE)
    end)
end

function AH:OnDisable()
    if panel then panel:Hide() end
    if self.toggle then self.toggle:Hide() end
end
