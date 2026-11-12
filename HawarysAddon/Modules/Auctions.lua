-- Hawary's Addon: Auction Watch – warns when one of YOUR auctions has been undercut,
-- using the lowest prices the Market module has seen. Information only: it never
-- cancels, reposts, bids or buys anything.
local _, ns = ...
local L, U, T, W = ns.L, ns.Util, ns.Theme, ns.W

local AW = ns:NewModule("auctions", {
    title = L.MOD_AUCTIONS,
    desc = L.MOD_AUCTIONS_DESC,
    order = 17,
    defaults = { toast = true, chat = true },
})

AW.options = {
    { type = "toggle", key = "toast", label = L.AW_TOAST, desc = L.AW_TOAST_DESC },
    { type = "toggle", key = "chat", label = L.AW_CHAT, desc = L.AW_CHAT_DESC },
}

-- Pure: which owned auctions are undercut. owned = { {itemID, unit, link} }, priceOf(id) -> lowest, seenAt
-- Unit-tested.
function AW.Undercuts(owned, priceOf)
    local out = {}
    for _, a in ipairs(owned) do
        local low, seen = priceOf(a.itemID)
        if low and a.unit and low < a.unit then
            out[#out + 1] = { itemID = a.itemID, link = a.link, mine = a.unit, lowest = low, seen = seen }
        end
    end
    table.sort(out, function(x, y) return (x.mine - x.lowest) > (y.mine - y.lowest) end)
    return out
end

function AW:Owned()
    local out = {}
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if a and a.status == Enum.AuctionStatus.Active and a.itemKey and a.buyoutAmount then
            -- Blizzard's Auctions tab shows buyoutAmount as the price per unit
            local unit = a.buyoutAmount
            out[#out + 1] = { itemID = a.itemKey.itemID, unit = unit, link = a.itemLink }
        end
    end
    return out
end

function AW:Check()
    local market = ns.modules.market
    if not (market and market.enabled) then return end
    local list = AW.Undercuts(self:Owned(), function(id) return market:Price(id) end)
    self.last = { time = time(), list = list }
    if #list > 0 then
        if self:Get("toast") then ns:Toast(L.AW_TITLE, L.AW_TOAST_TEXT:format(#list), "Interface\\Icons\\INV_Misc_Coin_02") end
        if self:Get("chat") then
            for i = 1, math.min(#list, 8) do
                local u = list[i]
                ns:Print(L.AW_LINE:format(u.link or u.itemID, U.money(u.mine), U.money(u.lowest)))
            end
        end
    end
    ns:Fire("AUCTIONS_CHECKED")
end

function AW:OnShow()
    -- the same request Blizzard's own "Auctions" tab makes
    C_AuctionHouse.QueryOwnedAuctions({ { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false } })
end

function AW:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetWidth(width)
    local head = W.Label(card, L.AW_TITLE, "h2", "text")
    head:SetPoint("TOPLEFT", 16, -14)
    local body = W.Label(card, "", "body", "text2")
    body:SetPoint("TOPLEFT", 16, -40)
    body:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    local function fill()
        local r = AW.last
        if not r then
            body:SetText(L.AW_NONE_YET)
        elseif #r.list == 0 then
            body:SetText(L.AW_ALL_GOOD)
        else
            local lines = {}
            for _, u in ipairs(r.list) do
                lines[#lines + 1] = L.AW_LINE:format(u.link or u.itemID, U.money(u.mine), U.money(u.lowest))
            end
            body:SetText(table.concat(lines, "\n"))
        end
        card:SetHeight(math.max(80, body:GetStringHeight() + 60))
    end
    ns:On("AUCTIONS_CHECKED", fill)
    fill()
    return y - 260
end

function AW:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnShow")
    self:RegisterEvent("OWNED_AUCTIONS_UPDATED", function() C_Timer.After(0.5, function() ns.Safe(AW.Check, AW) end) end)
end
