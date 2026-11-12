-- Hawary's Addon: Market / Professions / Alts logic (no WoW API, so it is unit-tested)
-- Rules from other addons' changelogs: an item without a known price is UNKNOWN, never 0;
-- prices are kept per auction house; nothing here buys, sells, posts or crafts.
local _, ns = ...

local M = {}
ns.MarketData = M

-- Lowest unit price from a full-scan list of { itemID, count, buyout }
function M.LowestUnitPrices(rows)
    local best = {}
    for _, r in ipairs(rows) do
        if r.itemID and r.buyout and r.buyout > 0 and (r.count or 1) > 0 then
            local unit = math.floor(r.buyout / (r.count or 1))
            if not best[r.itemID] or unit < best[r.itemID] then best[r.itemID] = unit end
        end
    end
    return best
end

-- Merge prices into a store { [itemID] = { p = copper, t = time } }; returns how many were stored
function M.StorePrices(store, prices, now)
    local n = 0
    for itemID, price in pairs(prices) do
        store[itemID] = { p = price, t = now }
        n = n + 1
    end
    return n
end

-- recipe = { output = itemID, qty = n, reagents = { {id = itemID, n = count}, ... } }
-- priceOf(itemID) -> copper or nil. Returns { cost, value, profit, missing = {itemIDs} }
-- cost/profit are nil when any reagent price is unknown; value is nil when the output is unknown.
function M.RecipeProfit(recipe, priceOf)
    local cost, missing = 0, {}
    for _, r in ipairs(recipe.reagents or {}) do
        local p = priceOf(r.id)
        if p then cost = cost + p * (r.n or 1) else missing[#missing + 1] = r.id end
    end
    local value = recipe.output and priceOf(recipe.output)
    if value then value = value * (recipe.qty or 1) end
    local known = #missing == 0
    return {
        cost = known and cost or nil,
        partialCost = cost,
        value = value,
        profit = (known and value) and (value - cost) or nil,
        missing = missing,
    }
end

-- Sort { name=, result= } by profit (known first, highest first), then by name
function M.RankByProfit(list)
    table.sort(list, function(a, b)
        local pa, pb = a.result.profit, b.result.profit
        if pa and pb then
            if pa ~= pb then return pa > pb end
        elseif pa or pb then
            return pa ~= nil
        end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- shopping = { {recipeID=, count=} }, recipes[recipeID] = recipe, have(itemID) -> count
-- Returns rows { itemID, need, have, missing }, missing first
function M.ShoppingNeeds(shopping, recipes, have)
    local need = {}
    for _, entry in ipairs(shopping) do
        local recipe = recipes[entry.recipeID]
        if recipe then
            for _, r in ipairs(recipe.reagents or {}) do
                need[r.id] = (need[r.id] or 0) + (r.n or 1) * (entry.count or 1)
            end
        end
    end
    local rows = {}
    for itemID, n in pairs(need) do
        local h = have(itemID) or 0
        rows[#rows + 1] = { itemID = itemID, need = n, have = h, missing = math.max(0, n - h) }
    end
    table.sort(rows, function(a, b)
        if (a.missing > 0) ~= (b.missing > 0) then return a.missing > 0 end
        return a.itemID < b.itemID
    end)
    return rows
end

-- 45 -> "just now", 3600 -> "1h ago", 200000 -> "2d ago"
function M.Age(seconds)
    if not seconds or seconds < 0 then return "" end
    if seconds < 120 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
    return math.floor(seconds / 86400) .. "d ago"
end

-- history = { ["2026-11-12"] = copper }; days = list of day keys (oldest first).
-- Unknown days carry the previous known value forward. Returns values, max
function M.GoldSeries(history, days)
    local values, last, max = {}, nil, 0
    for i, day in ipairs(days) do
        local v = history[day]
        if v then last = v end
        values[i] = last or 0
        if values[i] > max then max = values[i] end
    end
    return values, max
end

-- Case-insensitive search: items = { [itemID] = name }; returns itemIDs sorted by name
function M.SearchNames(items, query, limit)
    query = ((query or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if #query < 2 then return {} end
    local hits = {}
    for itemID, name in pairs(items) do
        if name and name:lower():find(query, 1, true) then hits[#hits + 1] = itemID end
    end
    table.sort(hits, function(a, b) return (items[a] or "") < (items[b] or "") end)
    if limit and #hits > limit then
        for i = #hits, limit + 1, -1 do hits[i] = nil end
    end
    return hits
end
