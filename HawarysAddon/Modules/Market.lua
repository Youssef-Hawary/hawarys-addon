-- Hawary's Addon: Market (Auctionator / ForeverProfit style price memory)
-- Remembers auction house prices from what YOU browse and search, plus an optional full scan
-- when you click the Scan button (Blizzard allows one every 15 minutes).
-- It never buys, bids, posts or cancels anything.
local _, ns = ...
local L, U, W, M = ns.L, ns.Util, ns.W, ns.MarketData

local Market = ns:NewModule("market", {
    title = L.MOD_MARKET,
    desc = L.MOD_MARKET_DESC,
    order = 5,
    defaults = { tooltip = true, scanButton = true, lastScan = 0 },
})

Market.options = {
    { type = "toggle", key = "tooltip", label = L.MARKET_TOOLTIP, desc = L.MARKET_TOOLTIP_DESC },
    { type = "toggle", key = "scanButton", label = L.MARKET_SCANBTN, desc = L.MARKET_SCANBTN_DESC },
}

local SCAN_COOLDOWN = 15 * 60
local CHUNK = 1500

-- Prices are kept per auction house (your faction's; Forever also has a neutral one).
function Market:Store()
    local faction = UnitFactionGroup("player") or "Neutral"
    ns.db.prices[faction] = ns.db.prices[faction] or {}
    return ns.db.prices[faction]
end

-- Returns copper per unit, time recorded (or nil)
function Market:Price(itemID)
    if not itemID then return nil end
    local e = self:Store()[itemID]
    if e then return e.p, e.t end
    return nil
end

function Market:Count()
    local n = 0
    for _ in pairs(self:Store()) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Capture prices from normal auction house use
---------------------------------------------------------------------------
function Market:OnBrowse()
    local best = {}
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local id = r.itemKey and r.itemKey.itemID
        if id and r.minPrice and r.minPrice > 0 and (not best[id] or r.minPrice < best[id]) then best[id] = r.minPrice end
    end
    M.StorePrices(self:Store(), best, time())
end

function Market:OnCommodity(_, itemID)
    local first = itemID and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if first and first.unitPrice and first.unitPrice > 0 then
        M.StorePrices(self:Store(), { [itemID] = first.unitPrice }, time())
    end
end

function Market:OnItemSearch(_, itemKey)
    if not itemKey then return end
    local best
    for i = 1, math.min(C_AuctionHouse.GetNumItemSearchResults(itemKey), 20) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and (not best or r.buyoutAmount < best) then best = r.buyoutAmount end
    end
    if best then M.StorePrices(self:Store(), { [itemKey.itemID] = best }, time()) end
end

---------------------------------------------------------------------------
-- Full scan (only when you click; read in chunks so the game doesn't freeze)
---------------------------------------------------------------------------
function Market:ScanReady()
    local wait = (self:Get("lastScan") or 0) + SCAN_COOLDOWN - time()
    return wait <= 0, wait
end

function Market:StartScan()
    local ready, wait = self:ScanReady()
    if not ready then
        ns:Print(L.MARKET_SCAN_WAIT, math.ceil(wait / 60))
        return
    end
    self.scanning = true
    self:DB().lastScan = time()
    C_AuctionHouse.ReplicateItems()
    ns:Toast(L.MOD_MARKET, L.MARKET_SCANNING, "Interface\\Icons\\INV_Misc_Coin_01")
    self:UpdateScanButton()
end

function Market:OnReplicate()
    if not self.scanning or self.reading then return end
    self.reading = true
    local total = C_AuctionHouse.GetNumReplicateItems()
    local rows, index = {}, 0
    local function step()
        local last = math.min(total - 1, index + CHUNK - 1)
        for i = index, last do -- replicate indexes start at 0
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
            if itemID and buyout and buyout > 0 then rows[#rows + 1] = { itemID = itemID, count = count, buyout = buyout } end
        end
        index = last + 1
        if index < total then
            C_Timer.After(0, function() ns.Safe(step) end)
        else
            local n = M.StorePrices(self:Store(), M.LowestUnitPrices(rows), time())
            self.scanning, self.reading = false, false
            self:UpdateScanButton()
            ns:Toast(L.MOD_MARKET, L.MARKET_SCANNED:format(n), "Interface\\Icons\\INV_Misc_Coin_01")
            ns:Fire("MARKET_UPDATED")
        end
    end
    step()
end

local scanButton
function Market:UpdateScanButton()
    if not scanButton then return end
    local ready, wait = self:ScanReady()
    scanButton:SetEnabled(ready and not self.scanning)
    scanButton:SetLabel(self.scanning and L.MARKET_SCAN_BUSY or (ready and L.MARKET_SCAN or L.MARKET_SCAN_IN:format(math.ceil(wait / 60))))
end

function Market:OnAuctionShow()
    if not AuctionHouseFrame then return end
    if not scanButton then
        scanButton = W.Button(AuctionHouseFrame, L.MARKET_SCAN, "primary", 160, 24)
        scanButton:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -6, 4)
        scanButton:SetScript("OnClick", function() Market:StartScan() end)
        W.Tooltip(scanButton, L.MARKET_SCAN, function()
            local last = Market:Get("lastScan") or 0
            return L.MARKET_SCAN_DESC:format(Market:Count(), last > 0 and M.Age(time() - last) or "–")
        end)
    end
    scanButton:SetShown(self:Get("scanButton"))
    self:UpdateScanButton()
end

---------------------------------------------------------------------------
-- Tooltip: "AH · 3h ago     1g 20s"
---------------------------------------------------------------------------
local function OnTooltipItem(tooltip)
    if not (Market.enabled and Market:Get("tooltip")) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link or ns.IsSecret(link) then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    local price, t = Market:Price(itemID)
    if not price then return end
    tooltip:AddDoubleLine("|cff38c6f4" .. L.MARKET_AH .. "|r  |cff77808f" .. M.Age(time() - t) .. "|r", U.money(price))
    tooltip:Show()
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Market:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 74)
    local items = W.Label(card, "", "number", "accent")
    items:SetPoint("TOPLEFT", 18, -14)
    local itemsLabel = W.Label(card, L.MARKET_ITEMS_PRICED, "small", "text3")
    itemsLabel:SetPoint("TOPLEFT", items, "BOTTOMLEFT", 0, -4)
    local scan = W.Label(card, "", "number", "text")
    scan:SetPoint("TOPLEFT", width / 2, -14)
    local scanLabel = W.Label(card, L.MARKET_LAST_SCAN, "small", "text3")
    scanLabel:SetPoint("TOPLEFT", scan, "BOTTOMLEFT", 0, -4)
    local function refresh()
        items:SetText(U.thousands(Market:Count()))
        local last = Market:Get("lastScan") or 0
        scan:SetText(last > 0 and M.Age(time() - last) or "–")
    end
    refresh()
    card:SetScript("OnShow", refresh)
    ns:On("MARKET_UPDATED", refresh)
    y = y - 74 - 12
    local note = W.Label(content, L.MARKET_NOTE, "small", "text2")
    note:SetPoint("TOPLEFT", 0, y)
    note:SetWidth(width)
    note:SetWordWrap(true)
    y = y - note:GetStringHeight() - 18
    return ns:BuildOptions(self, content, width, y)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Market:OnInitialize()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        ns.Safe(OnTooltipItem, tooltip)
    end)
end

function Market:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnAuctionShow")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", function() self.scanning = false end)
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "OnBrowse")
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "OnBrowse")
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "OnCommodity")
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", "OnItemSearch")
    self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", "OnReplicate")
end

function Market:OnDisable()
    if scanButton then scanButton:Hide() end
end

function Market:OnSettingChanged(key)
    if key == "scanButton" and scanButton then scanButton:SetShown(self:Get("scanButton")) end
end
