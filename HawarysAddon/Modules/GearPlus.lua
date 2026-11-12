-- Hawary's Addon: Best-in-Slot finder + Equipment Sets.
-- BiS: ranks gear you can actually get – in any of your characters' bags or bank, seen on
-- the auction house, or as a quest reward – with your stat weights, for your level now and
-- the next 5 levels. Sets: Blizzard's own equipment manager, one click = one set, never in combat.
local _, ns = ...
local L, U, T, W = ns.L, ns.Util, ns.Theme, ns.W
local D = ns.GearData

local GP = ns:NewModule("gearplus", {
    title = L.MOD_GEARPLUS,
    desc = L.MOD_GEARPLUS_DESC,
    order = 15,
    defaults = { ahItems = true, questItems = true, altItems = true },
})

GP.options = {
    { type = "toggle", key = "altItems", label = L.BIS_ALTS, desc = L.BIS_ALTS_DESC },
    { type = "toggle", key = "ahItems", label = L.BIS_AH, desc = L.BIS_AH_DESC },
    { type = "toggle", key = "questItems", label = L.BIS_QUEST, desc = L.BIS_QUEST_DESC },
}

-- Slot groups shown in the list
GP.GROUP = {
    INVTYPE_HEAD = "HEAD", INVTYPE_NECK = "NECK", INVTYPE_SHOULDER = "SHOULDER", INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST",
    INVTYPE_WAIST = "WAIST", INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET", INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HANDS",
    INVTYPE_FINGER = "FINGER", INVTYPE_TRINKET = "TRINKET", INVTYPE_CLOAK = "BACK", INVTYPE_WEAPON = "MAINHAND",
    INVTYPE_2HWEAPON = "MAINHAND", INVTYPE_WEAPONMAINHAND = "MAINHAND", INVTYPE_SHIELD = "OFFHAND",
    INVTYPE_WEAPONOFFHAND = "OFFHAND", INVTYPE_HOLDABLE = "OFFHAND", INVTYPE_RANGED = "RANGED",
    INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED", INVTYPE_RELIC = "RANGED",
}
GP.ORDER = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND", "RANGED" }

-- Pure: keep the best candidate per group and bucket ("now" / "soon"). Unit-tested.
-- cand = { group, pct, minLevel, ... }
function GP.Pick(cands, level)
    local best = { now = {}, soon = {} }
    for _, c in ipairs(cands) do
        local bucket = (c.minLevel or 0) <= level and "now" or ((c.minLevel or 0) <= level + 5 and "soon" or nil)
        if bucket and c.group and c.pct and c.pct > 0 then
            local cur = best[bucket][c.group]
            if not cur or c.pct > cur.pct then best[bucket][c.group] = c end
        end
    end
    return best
end

-- Candidates: itemID -> source text
function GP:Candidates()
    local out = {}
    local me = ns:CharKey()
    if self:Get("altItems") then
        for key, rec in pairs(ns.db.chars) do
            local who = key == me and L.BIS_SRC_BAGS or L.BIS_SRC_ALT:format(rec.name or key)
            for _, store in ipairs({ rec.bags or {}, rec.bank or {} }) do
                for id in pairs(store) do out[id] = out[id] or who end
            end
        end
    end
    local market = ns.modules.market
    if self:Get("ahItems") and market and market.Store then
        for id, e in pairs(market:Store()) do out[id] = out[id] or L.BIS_SRC_AH:format(U.money(e.p, true)) end
    end
    local Q = ns.modules.quests
    if self:Get("questItems") and Q and Q.enabled and Q.available and Q.ctx then
        -- quest rewards of quests you can take or already have
        if not self.rewardIndex then
            self.rewardIndex = {}
            do
                for _, id in ipairs(Q:AllItemIDs()) do
                    for _, qid in ipairs(Q:Data("item", id, "questRewards") or {}) do
                        self.rewardIndex[qid] = self.rewardIndex[qid] or {}
                        table.insert(self.rewardIndex[qid], id)
                    end
                end
            end
        end
        local function add(qid)
            for _, id in ipairs(self.rewardIndex[qid] or {}) do out[id] = out[id] or L.BIS_SRC_QUEST:format(Q:Title(qid) or qid) end
        end
        for qid, status in pairs(Q.available) do if status == "available" then add(qid) end end
        for qid in pairs(Q.ctx.active) do add(qid) end
    end
    return out
end

function GP:Scan()
    local gear = ns.modules.gear
    if not (gear and gear.enabled) then self.result = { error = L.BIS_NEED_GEAR }; return self.result end
    local cands, pending, n = {}, 0, 0
    for id, source in pairs(self:Candidates()) do
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
        local group = equipLoc and GP.GROUP[equipLoc]
        if group then
            n = n + 1
            local _, link, _, _, minLevel = C_Item.GetItemInfo(id)
            if link then
                local r = gear:Evaluate(link)
                if r and (r.kind == "upgrade" or r.kind == "empty") then
                    cands[#cands + 1] = { id = id, link = link, group = group, pct = r.kind == "empty" and 100 or r.pct,
                                          minLevel = minLevel or 0, source = source }
                end
            elseif pending < 200 then
                pending = pending + 1
                C_Item.RequestLoadItemDataByID(id)
            end
        end
    end
    self.result = { best = GP.Pick(cands, UnitLevel("player")), checked = n, pending = pending }
    return self.result
end

---------------------------------------------------------------------------
-- Equipment sets (Blizzard's equipment manager)
---------------------------------------------------------------------------
function GP:Sets()
    local out = {}
    if not C_EquipmentSet then return out end
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon, setID, isEquipped, numItems, _, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then out[#out + 1] = { id = setID or id, name = name, icon = icon, equipped = isEquipped, items = numItems, lost = numLost } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function GP:UseSet(id)
    if ns.InCombat() then ns:Print(L.NOT_IN_COMBAT); return end
    C_EquipmentSet.UseEquipmentSet(id)
end

function GP:SaveSet(name, id)
    if ns.InCombat() then ns:Print(L.NOT_IN_COMBAT); return end
    if id then
        C_EquipmentSet.SaveEquipmentSet(id)
        ns:Print(L.SETS_SAVED)
        return
    end
    name = U.trim(name or "")
    if name == "" then return end
    C_EquipmentSet.CreateEquipmentSet(name)
    ns:Print(L.SETS_CREATED:format(name))
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function GP:BuildPage(content, width, y)
    -- Best in slot
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetWidth(width)
    local head = W.Label(card, L.BIS_TITLE, "h2", "text")
    head:SetPoint("TOPLEFT", 16, -14)
    local scan = W.Button(card, L.BIS_SCAN, "primary", 120)
    scan:SetPoint("TOPRIGHT", -14, -10)
    local info = W.Label(card, "", "small", "text3")
    info:SetPoint("TOPLEFT", 16, -36)
    info:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    info:SetWordWrap(true)
    local lines = {}
    local function line(i)
        if lines[i] then return lines[i] end
        local b = CreateFrame("Button", nil, card)
        b:SetHeight(20)
        b.slot = W.Label(b, "", "small", "text3")
        b.slot:SetPoint("LEFT", 0, 0)
        b.slot:SetWidth(90)
        b.item = W.Label(b, "", "body", "text")
        b.item:SetPoint("LEFT", 96, 0)
        b.item:SetWidth(width * 0.42)
        b.item:SetWordWrap(false)
        b.pct = W.Label(b, "", "body", "good")
        b.pct:SetPoint("LEFT", b.item, "RIGHT", 6, 0)
        b.src = W.Label(b, "", "small", "text2")
        b.src:SetPoint("LEFT", b.pct, "RIGHT", 10, 0)
        b.src:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        b.src:SetWordWrap(false)
        b:SetScript("OnEnter", function(self)
            if not self.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lines[i] = b
        return b
    end
    local function fill()
        local r = GP.result
        for _, b in ipairs(lines) do b:Hide() end
        if not r then info:SetText(L.BIS_HINT); card:SetHeight(70); return end
        if r.error then info:SetText(r.error); card:SetHeight(70); return end
        info:SetText(L.BIS_INFO:format(r.checked, UnitLevel("player")) .. (r.pending > 0 and (" " .. L.BIS_PENDING) or ""))
        local i, yy = 0, -60
        for _, bucket in ipairs({ "now", "soon" }) do
            i = i + 1
            local h = line(i)
            h.link = nil
            h:SetPoint("TOPLEFT", 16, yy); h:SetPoint("RIGHT", card, "RIGHT", -16, 0)
            h.slot:SetText(""); h.pct:SetText(""); h.src:SetText("")
            h.item:SetText("|cff" .. T.hex("accent") .. (bucket == "now" and L.BIS_NOW or L.BIS_SOON) .. "|r")
            h:Show()
            yy = yy - 22
            local any = false
            for _, g in ipairs(GP.ORDER) do
                local c = r.best[bucket][g]
                if c then
                    any = true
                    i = i + 1
                    local b = line(i)
                    b:SetPoint("TOPLEFT", 16, yy); b:SetPoint("RIGHT", card, "RIGHT", -16, 0)
                    b.link = c.link
                    b.slot:SetText(L["SLOT_" .. g])
                    b.item:SetText(c.link)
                    b.pct:SetText(c.pct >= 100 and L.BIS_EMPTY_SLOT or string.format("+%d%%", c.pct))
                    b.src:SetText(c.source .. ((c.minLevel or 0) > UnitLevel("player") and (" · " .. L.BIS_LEVEL:format(c.minLevel)) or ""))
                    b:Show()
                    yy = yy - 21
                end
            end
            if not any then
                i = i + 1
                local b = line(i)
                b.link = nil
                b:SetPoint("TOPLEFT", 16, yy); b:SetPoint("RIGHT", card, "RIGHT", -16, 0)
                b.slot:SetText(""); b.pct:SetText(""); b.src:SetText("")
                b.item:SetText("|cff" .. T.hex("text3") .. L.BIS_NONE .. "|r")
                b:Show()
                yy = yy - 21
            end
            yy = yy - 6
        end
        card:SetHeight(-yy + 10)
    end
    scan:SetScript("OnClick", function() GP:Scan(); fill(); content.Relayout() end)
    fill()

    -- Equipment sets
    local sets = W.Card(content)
    sets:SetWidth(width)
    local sh = W.Label(sets, L.SETS_TITLE, "h2", "text")
    sh:SetPoint("TOPLEFT", 16, -14)
    local nameBox = W.EditBox(sets, 180, 24)
    nameBox:SetPoint("TOPRIGHT", -140, -10)
    local save = W.Button(sets, L.SETS_NEW, "primary", 120)
    save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    save:SetScript("OnClick", function() GP:SaveSet(nameBox:GetText()); nameBox:SetText("") end)
    local setRows = {}
    local function fillSets()
        for _, r in ipairs(setRows) do r:Hide() end
        local list = GP:Sets()
        local yy = -46
        if not C_EquipmentSet or #list == 0 then
            setRows.empty = setRows.empty or W.Label(sets, L.SETS_EMPTY, "small", "text3")
            setRows.empty:SetPoint("TOPLEFT", 16, yy)
            setRows.empty:Show()
            yy = yy - 22
        elseif setRows.empty then setRows.empty:Hide() end
        for i, s in ipairs(list) do
            local r = setRows[i]
            if not r then
                r = CreateFrame("Frame", nil, sets)
                r:SetHeight(28)
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(22, 22)
                r.icon:SetPoint("LEFT", 0, 0)
                r.name = W.Label(r, "", "body", "text")
                r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
                r.use = W.Button(r, L.SETS_EQUIP, "primary", 80)
                r.use:SetPoint("RIGHT", -90, 0)
                r.upd = W.Button(r, L.SETS_UPDATE, "secondary", 80)
                r.upd:SetPoint("RIGHT", 0, 0)
                setRows[i] = r
            end
            r:SetPoint("TOPLEFT", 16, yy); r:SetPoint("RIGHT", sets, "RIGHT", -16, 0)
            r.icon:SetTexture(s.icon)
            r.name:SetText(s.name .. (s.equipped and ("  |cff" .. T.hex("good") .. L.SETS_WORN .. "|r") or "")
                .. ((s.lost or 0) > 0 and ("  |cff" .. T.hex("bad") .. L.SETS_LOST:format(s.lost) .. "|r") or ""))
            r.use:SetScript("OnClick", function() GP:UseSet(s.id) end)
            r.upd:SetScript("OnClick", function() GP:SaveSet(nil, s.id) end)
            r:Show()
            yy = yy - 30
        end
        sets:SetHeight(-yy + 10)
    end
    fillSets()
    sets.Refresh = fillSets
    GP.setsCard = sets

    function content.Relayout()
        sets:ClearAllPoints()
        sets:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -16)
        content:SetHeight(-y + card:GetHeight() + sets:GetHeight() + 60)
    end
    content.Relayout()
    return y - card:GetHeight() - sets:GetHeight() - 40
end

function GP:OnEnable()
    self:RegisterEvent("EQUIPMENT_SETS_CHANGED", function() if GP.setsCard then GP.setsCard.Refresh() end end)
end
