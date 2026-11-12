-- Hawary's Addon: Alts & Gold (Altoholic-style overview + Overwolf-style character snapshot)
-- Every character's level, item level, gold, professions and last login; a gold history chart;
-- and a search across every character's bags, bank and gear. Read-only.
local _, ns = ...
local L, U, T, W, M = ns.L, ns.Util, ns.Theme, ns.W, ns.MarketData

local Alts = ns:NewModule("alts", {
    title = L.MOD_ALTS,
    desc = L.MOD_ALTS_DESC,
    order = 6,
    defaults = { days = 30 },
})

Alts.options = {
    { type = "slider", key = "days", label = L.ALTS_DAYS, desc = L.ALTS_DAYS_DESC, min = 7, max = 90, step = 1,
      format = function(v) return L.ALTS_DAYS_FMT:format(v) end },
}

local KEEP_DAYS = 120

function Alts:TotalCopper()
    local me, total = ns:CharKey(), 0
    for key, rec in pairs(ns.db.chars) do
        if key == me then total = total + GetMoney() else total = total + (rec.money or 0) end
    end
    return total
end

function Alts:Record()
    local rec = ns.db.chars[ns:CharKey()]
    if not rec then return end
    rec.lastSeen = time()
    rec.faction = UnitFactionGroup("player")
    local gear = ns.modules.gear
    local ilvl = gear and gear:AverageItemLevel()
    if ilvl then rec.ilvl = tonumber(ilvl) end
    local history = ns.db.goldHistory
    history[date("%Y-%m-%d")] = self:TotalCopper()
    local cutoff = date("%Y-%m-%d", time() - KEEP_DAYS * 86400)
    for day in pairs(history) do
        if day < cutoff then history[day] = nil end
    end
    ns:Fire("ALTS_UPDATED")
end

function Alts:Days(n)
    local days = {}
    for i = n - 1, 0, -1 do days[#days + 1] = date("%Y-%m-%d", time() - i * 86400) end
    return days
end

local function ClassHex(classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    return c and c:GenerateHexColor():sub(3) or "f2f5f9"
end

local function Gold(copper) return U.thousands(math.floor((copper or 0) / 10000)) .. "|cffffd700g|r" end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Alts:BuildPage(content, width, y)
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

    -- 1) Gold summary + chart
    local gold = W.Card(content)
    gold.total = W.Label(gold, "", "brandBig", "accent")
    gold.total:SetPoint("TOPLEFT", 18, -14)
    gold.sub = W.Label(gold, "", "small", "text3")
    gold.sub:SetPoint("TOPLEFT", gold.total, "BOTTOMLEFT", 0, -4)
    gold.delta = W.Label(gold, "", "body", nil, "RIGHT")
    gold.delta:SetPoint("TOPRIGHT", -18, -18)
    gold.bars = {}
    function gold:Refresh()
        local n = Alts:Get("days")
        local days = Alts:Days(n)
        local values, max = M.GoldSeries(ns.db.goldHistory, days)
        local total = Alts:TotalCopper()
        local count = 0
        for _ in pairs(ns.db.chars) do count = count + 1 end
        self.total:SetText(Gold(total))
        self.sub:SetText(L.ALTS_SUMMARY:format(count, n))
        local yesterday = values[#values - 1]
        if yesterday and yesterday > 0 then
            local d = total - yesterday
            self.delta:SetText((d >= 0 and "|cff4ade80+" or "|cfff87171-") .. Gold(math.abs(d)) .. "|r  " .. L.ALTS_TODAY)
        else
            self.delta:SetText("")
        end
        local chartW, chartH = width - 36, 70
        local gap = 2
        local bw = math.max(2, (chartW - gap * (n - 1)) / n)
        for _, b in ipairs(self.bars) do b:Hide() end
        for i, v in ipairs(values) do
            local b = self.bars[i]
            if not b then
                b = CreateFrame("Frame", nil, self)
                b.tex = b:CreateTexture(nil, "ARTWORK")
                b.tex:SetPoint("BOTTOMLEFT")
                b.tex:SetPoint("BOTTOMRIGHT")
                b:EnableMouse(true)
                b:SetScript("OnEnter", function(selfBar)
                    selfBar.tex:SetColorTexture(0.6, 0.9, 1, 1)
                    GameTooltip:SetOwner(selfBar, "ANCHOR_TOP")
                    GameTooltip:SetText(selfBar.day or "", 1, 1, 1)
                    GameTooltip:AddLine(Gold(selfBar.value), 1, 1, 1)
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function(selfBar)
                    selfBar.tex:SetColorTexture(T.color(selfBar.today and "accent" or "accent2"))
                    GameTooltip:Hide()
                end)
                self.bars[i] = b
            end
            b.day, b.value, b.today = days[i], v, i == #values
            b:ClearAllPoints()
            b:SetSize(bw, chartH)
            b:SetPoint("BOTTOMLEFT", 18 + (i - 1) * (bw + gap), 16)
            b.tex:SetColorTexture(T.color(b.today and "accent" or "accent2"))
            b.tex:SetHeight(math.max(2, max > 0 and (v / max) * chartH or 2))
            b:Show()
        end
        return 74 + chartH + 26
    end
    sections[#sections + 1] = gold

    -- 2) Characters
    local chars = CreateFrame("Frame", nil, content)
    chars.title = W.Label(chars, L.ALTS_CHARS, "h2", "accent")
    chars.title:SetPoint("TOPLEFT")
    chars.rows = {}
    function chars:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        local me = ns:CharKey()
        local keys = {}
        for key in pairs(ns.db.chars) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            if a == me or b == me then return a == me end
            return (ns.db.chars[a].level or 0) > (ns.db.chars[b].level or 0)
        end)
        local ry = -26
        for i, key in ipairs(keys) do
            local rec = ns.db.chars[key]
            local row = self.rows[i]
            if not row then
                row = W.Card(self)
                row:SetHeight(48)
                row.name = W.Label(row, "", "body", "text")
                row.name:SetPoint("TOPLEFT", 14, -9)
                row.info = W.Label(row, "", "small", "text3")
                row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
                row.info:SetPoint("RIGHT", row, "RIGHT", -170, 0)
                row.info:SetWordWrap(false)
                row.gold = W.Label(row, "", "body", "text", "RIGHT")
                row.gold:SetPoint("TOPRIGHT", -44, -9)
                row.seen = W.Label(row, "", "small", "text3", "RIGHT")
                row.seen:SetPoint("TOPRIGHT", row.gold, "BOTTOMRIGHT", 0, -3)
                row.del = W.Button(row, "x", "danger", 24, 20)
                row.del:SetPoint("RIGHT", -10, 0)
                W.Tooltip(row.del, L.ALTS_DELETE, L.ALTS_DELETE_DESC)
                row.del:SetScript("OnClick", function()
                    if IsShiftKeyDown() and row.key and row.key ~= ns:CharKey() then
                        ns.db.chars[row.key] = nil
                        Alts:Record()
                        Relayout()
                    end
                end)
                self.rows[i] = row
            end
            row.key = key
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, ry)
            row:SetWidth(width)
            row.name:SetText("|cff" .. ClassHex(rec.class) .. (rec.name or key) .. "|r" .. (key == me and ("  |cff38c6f4" .. L.ALTS_YOU .. "|r") or ""))
            local profs = {}
            for _, p in ipairs(rec.profs or {}) do profs[#profs + 1] = ("%s %d"):format(p.name, p.rank) end
            local parts = { L.ALTS_LEVEL:format(rec.level or 0) }
            if rec.ilvl then parts[#parts + 1] = L.ALTS_ILVL:format(rec.ilvl) end
            if #profs > 0 then parts[#parts + 1] = table.concat(profs, ", ") end
            row.info:SetText(table.concat(parts, "  ·  "))
            row.gold:SetText(Gold(key == me and GetMoney() or rec.money))
            row.seen:SetText(key == me and L.ALTS_ONLINE or M.Age(time() - (rec.lastSeen or rec.updated or time())))
            row.del:SetShown(key ~= me)
            row:Show()
            ry = ry - 54
        end
        return -ry
    end
    sections[#sections + 1] = chars

    -- 3) Item search across characters
    local search = CreateFrame("Frame", nil, content)
    search.title = W.Label(search, L.ALTS_SEARCH, "h2", "accent")
    search.title:SetPoint("TOPLEFT")
    search.box = W.EditBox(search, 260, 26)
    search.box:SetPoint("TOPRIGHT", 0, 4)
    search.rows = {}
    search.box.edit:SetScript("OnTextChanged", function(_, userInput) if userInput then Relayout() end end)
    function search:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        local names, totals = {}, {}
        for _, rec in pairs(ns.db.chars) do
            for _, store in ipairs({ rec.bags or {}, rec.bank or {}, rec.worn or {} }) do
                for itemID, n in pairs(store) do
                    if names[itemID] == nil then
                        local name = C_Item.GetItemNameByID(itemID)
                        if not name then C_Item.RequestLoadItemDataByID(itemID) end
                        names[itemID] = name or false
                    end
                    totals[itemID] = (totals[itemID] or 0) + n
                end
            end
        end
        for k, v in pairs(names) do if not v then names[k] = nil end end
        local query = self.box:GetText()
        local hits = M.SearchNames(names, query, 20)
        local sy = -32
        if #query >= 2 and #hits == 0 then
            self.none = self.none or W.Label(self, L.ALTS_NO_HITS, "small", "text3")
            self.none:SetPoint("TOPLEFT", 0, sy)
            self.none:Show()
            return -sy + 20
        elseif self.none then
            self.none:Hide()
        end
        for i, itemID in ipairs(hits) do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, self)
                row:SetHeight(24)
                row.bg = T.Shape(row, "round_sm", "card", "BACKGROUND")
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", 6, 0)
                row.name = W.Label(row, "", "small", "text")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.where = W.Label(row, "", "small", "text3", "RIGHT")
                row.where:SetPoint("RIGHT", -8, 0)
                row.where:SetPoint("LEFT", row, "CENTER", 0, 0)
                row.where:SetWordWrap(false)
                self.rows[i] = row
            end
            local where = {}
            for _, rec in pairs(ns.db.chars) do
                local n = (rec.bags and rec.bags[itemID] or 0) + (rec.bank and rec.bank[itemID] or 0) + (rec.worn and rec.worn[itemID] or 0)
                if n > 0 then where[#where + 1] = ("|cff%s%s|r %d"):format(ClassHex(rec.class), rec.name or "?", n) end
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, sy)
            row:SetPoint("TOPRIGHT", 0, sy)
            row.icon:SetTexture(C_Item.GetItemIconByID(itemID) or 134400)
            row.name:SetText(("%s  |cff38c6f4x%d|r"):format(names[itemID], totals[itemID]))
            row.where:SetText(table.concat(where, "  ·  "))
            row:Show()
            sy = sy - 28
        end
        return -sy + 4
    end
    sections[#sections + 1] = search

    local function maybeRelayout() if content:IsVisible() then Relayout() end end
    ns:On("ALTS_UPDATED", maybeRelayout)
    ns:On("SETTING_CHANGED", function(id, key) if id == "alts" and key == "days" then maybeRelayout() end end)
    content:HookScript("OnShow", Relayout)
    return Relayout()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Alts:OnEnable()
    self:RegisterEvent("PLAYER_MONEY", function() C_Timer.After(0.2, function() ns.Safe(Alts.Record, Alts) end) end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() C_Timer.After(1, function() ns.Safe(Alts.Record, Alts) end) end)
    self:RegisterEvent("PLAYER_LOGOUT", "Record")
    C_Timer.After(4, function() if self.enabled then ns.Safe(self.Record, self) end end)
end
