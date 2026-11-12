-- Hawary's Addon: For Fun – Skins, Fashion Studio, Fun Stats & Badges (+ daily
-- challenges), Hex Hop (mini-game) and Fun Moments (fortune of the day, level-up party,
-- death roast, AFK show). Nothing here plays the game for you: no key presses, no chat,
-- no emotes, no camera or character control, and every message goes to your own chat only.
local _, ns = ...
local L, U, T, W = ns.L, ns.Util, ns.Theme, ns.W

local FUN = {}
ns.Fun = FUN

local function Stats()
    local s = ns.db.funStats
    for _, k in ipairs({ "jumps", "deaths", "distance", "quests", "gold", "level", "hearths", "hex", "hexBest", "fashion", "owl", "streak" }) do
        s[k] = s[k] or 0
    end
    s.skins = s.skins or {}
    s.badges = s.badges or {}
    s.daily = s.daily or {}
    return s
end
FUN.Stats = Stats

local function Bump(key, n)
    local s = Stats()
    s[key] = (s[key] or 0) + (n or 1)
    ns:Fire("FUN_STAT", key)
end
FUN.Bump = Bump

---------------------------------------------------------------------------
-- Badges (pure checks are unit-tested)
---------------------------------------------------------------------------
FUN.BADGES = {
    { id = "jump100", stat = "jumps", need = 100 },
    { id = "jump1000", stat = "jumps", need = 1000 },
    { id = "jump10000", stat = "jumps", need = 10000 },
    { id = "death1", stat = "deaths", need = 1 },
    { id = "death25", stat = "deaths", need = 25 },
    { id = "death100", stat = "deaths", need = 100 },
    { id = "walk10k", stat = "distance", need = 10000 },
    { id = "walk100k", stat = "distance", need = 100000 },
    { id = "walk1m", stat = "distance", need = 1000000 },
    { id = "quest50", stat = "quests", need = 50 },
    { id = "quest500", stat = "quests", need = 500 },
    { id = "gold100", stat = "gold", need = 1000000 },
    { id = "gold1000", stat = "gold", need = 10000000 },
    { id = "hearth25", stat = "hearths", need = 25 },
    { id = "level10", stat = "level", need = 10 },
    { id = "level60", stat = "level", need = 60 },
    { id = "fashion10", stat = "fashion", need = 10 },
    { id = "hex50", stat = "hexBest", need = 50 },
    { id = "skins5", stat = "skinCount", need = 5 },
    { id = "owl", stat = "owl", need = 1 },
    { id = "week", stat = "streak", need = 7 },
}

function FUN.Value(stats, key)
    if key == "skinCount" then
        local n = 0
        for _ in pairs(stats.skins or {}) do n = n + 1 end
        return n
    end
    return stats[key] or 0
end

-- Returns the ids of badges reached but not unlocked yet
function FUN.NewBadges(stats, unlocked)
    local out = {}
    for _, b in ipairs(FUN.BADGES) do
        if not unlocked[b.id] and FUN.Value(stats, b.stat) >= b.need then out[#out + 1] = b.id end
    end
    return out
end

function FUN:CheckBadges()
    local s = Stats()
    for _, id in ipairs(FUN.NewBadges(s, s.badges)) do
        s.badges[id] = time()
        ns:Toast(L.FUN_BADGE_UNLOCKED, L["BADGE_" .. id:upper()], "star")
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE) end
    end
end

---------------------------------------------------------------------------
-- Daily challenges: 3 a day, the same for the whole day
---------------------------------------------------------------------------
FUN.DAILY = {
    { id = "jumps", stat = "jumps", need = 50 },
    { id = "walk", stat = "distance", need = 3000 },
    { id = "quests", stat = "quests", need = 5 },
    { id = "gold", stat = "gold", need = 50000 },
    { id = "hearth", stat = "hearths", need = 1 },
    { id = "hex", stat = "hex", need = 1 },
    { id = "fashion", stat = "fashion", need = 1 },
    { id = "bigwalk", stat = "distance", need = 8000 },
    { id = "quests10", stat = "quests", need = 10 },
}

-- Pure: n distinct challenge indexes for a day number (deterministic). Unit-tested.
function FUN.DailyPick(day, n)
    local picks, used, seed = {}, {}, (day % 2147483646) + 1
    while #picks < math.min(n, #FUN.DAILY) do
        seed = (seed * 16807) % 2147483647
        local i = (seed % #FUN.DAILY) + 1
        if not used[i] then used[i] = true; picks[#picks + 1] = i end
    end
    return picks
end

function FUN.Today() return math.floor(time() / 86400) end

function FUN:Daily()
    local s = Stats()
    local d = s.daily
    local today = FUN.Today()
    if d.day ~= today then
        d.day, d.list, d.base, d.done = today, FUN.DailyPick(today, 3), {}, false
        for _, i in ipairs(d.list) do
            local c = FUN.DAILY[i]
            d.base[c.id] = s[c.stat] or 0
        end
    end
    local out, all = {}, true
    for _, i in ipairs(d.list) do
        local c = FUN.DAILY[i]
        local have = (s[c.stat] or 0) - (d.base[c.id] or 0)
        local ok = have >= c.need
        all = all and ok
        out[#out + 1] = { id = c.id, have = math.min(have, c.need), need = c.need, done = ok }
    end
    if all and not d.done then
        d.done = true
        s.streak = (s.lastDaily == today - 1) and (s.streak + 1) or 1
        s.lastDaily = today
        ns:Toast(L.FUN_DAILY_DONE, L.FUN_STREAK:format(s.streak), "star")
    end
    return out
end

---------------------------------------------------------------------------
-- Fortunes and roasts (original lines)
---------------------------------------------------------------------------
FUN.FORTUNES = {
    "A murloc will remember your kindness. It will not repay it.",
    "Today your loot rolls are blessed. Mostly with grey items.",
    "The quest you skip today will be the one your friend needs tomorrow.",
    "You will find exactly one Linen Cloth more than you need.",
    "A flight path is closer than it appears. Unless it isn't.",
    "Fortune favors the player who repairs before the dungeon.",
    "Somewhere, a gnome is jealous of your hat.",
    "Your hearthstone is ready. Your heart is not.",
    "The next rare spawn will appear the moment you go AFK.",
    "Great power awaits at level 60. So does a lot of walking.",
    "Do not trust the innkeeper's stew.",
    "You will vendor something valuable. Accept it and move on.",
    "A wise adventurer reads the quest text. Just this once.",
    "The road to 60 is long. Bring snacks (in game and in real life).",
    "Your bags will be full at the worst possible moment.",
    "Today is a good day to finally train your skills.",
    "A stranger will run past and steal your mob. Forgive them.",
    "The fish are biting. The raptors are also biting.",
    "Lucky number: 7. Unlucky number: every bandit in the next camp.",
    "Jump less. Or more. The badge counter is watching.",
    "Your mount is not lost. It is just not bought yet.",
    "Something shiny is in the next cave. So is something angry.",
    "The spirit healer knows your name by now.",
    "Today's lesson: if the mob has a skull, walk the other way.",
    "You are the main character. Act accordingly.",
}

FUN.ROASTS = {
    "The floor missed you. Welcome back.",
    "Bold strategy. Let's see if it works next time.",
    "The spirit healer says hi. Again.",
    "Maybe that mob was a little more than 'one more pull'.",
    "Respawning with style. Corpse run time!",
    "Fun fact: dead players don't take damage.",
    "Your repair bill sends its regards.",
    "That was definitely lag. Definitely.",
    "Achievement unlocked: Gravity Tester.",
    "Even the murlocs felt bad about that one.",
    "Tip: health bars work better when they're full.",
    "You died, but your fashion survived.",
}

function FUN.FortuneFor(day) return FUN.FORTUNES[(day % #FUN.FORTUNES) + 1] end

---------------------------------------------------------------------------
-- 1) Skins
---------------------------------------------------------------------------
local Skins = ns:NewModule("skins", {
    title = L.MOD_SKINS, desc = L.MOD_SKINS_DESC, order = 101, category = "fun",
})

function Skins:BuildPage(content, width, y)
    local cols = 3
    local size = (width - 16) / cols
    for i, id in ipairs(T.skins) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local b = CreateFrame("Button", nil, content)
        b:SetSize(size - 4, 74)
        b:SetPoint("TOPLEFT", col * (size + 8), y - row * 84)
        local p = T.palettes[id]
        b.bg = T.Shape(b, "round", id == "native" and { 0.12, 0.09, 0.05, 1 } or p.card, "BACKGROUND")
        b.line = T.Shape(b, "round_line", p.accent, "BORDER")
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetColorTexture(unpack(p.accent))
        b.bar:SetSize(size - 36, 6)
        b.bar:SetPoint("BOTTOM", 0, 12)
        b.name = W.Label(b, L["SKIN_" .. id:upper()], "h2", "text")
        b.name:SetTextColor(unpack(id == "native" and { 1, 0.82, 0, 1 } or p.text))
        b.name:SetPoint("TOPLEFT", 14, -14)
        if T.name() == id then
            b.tag = W.Tag(b, L.FUN_SKIN_ACTIVE, "accent")
            b.tag:SetPoint("TOPRIGHT", -10, -12)
        end
        b:SetScript("OnClick", function()
            Stats().skins[id] = true
            FUN:CheckBadges()
            ns.General:Set("theme", id)
        end)
        T.Focusable(b)
    end
    local rows = math.ceil(#T.skins / cols)
    local note = W.Label(content, L.FUN_SKIN_NOTE, "small", "text3")
    note:SetPoint("TOPLEFT", 0, y - rows * 84 - 6)
    note:SetWidth(width)
    note:SetWordWrap(true)
    return y - rows * 84 - 50
end

---------------------------------------------------------------------------
-- 2) Fashion Studio – outfits on a preview of your own character (like Blizzard's
--    dressing room). Your real gear and the game files are never changed.
---------------------------------------------------------------------------
local Fashion = ns:NewModule("fashion", {
    title = L.MOD_FASHION, desc = L.MOD_FASHION_DESC, order = 102, category = "fun",
})

local WEAR = {
    INVTYPE_HEAD = 1, INVTYPE_SHOULDER = 2, INVTYPE_CHEST = 3, INVTYPE_ROBE = 3, INVTYPE_WAIST = 4, INVTYPE_LEGS = 5,
    INVTYPE_FEET = 6, INVTYPE_WRIST = 7, INVTYPE_HAND = 8, INVTYPE_CLOAK = 9, INVTYPE_WEAPON = 10, INVTYPE_2HWEAPON = 10,
    INVTYPE_WEAPONMAINHAND = 10, INVTYPE_SHIELD = 11, INVTYPE_WEAPONOFFHAND = 11, INVTYPE_HOLDABLE = 11, INVTYPE_BODY = 12,
    INVTYPE_TABARD = 13,
}

-- Pure: one random item per visible slot from a list of {id, equipLoc}. Unit-tested.
function FUN.RandomOutfit(items, rand)
    rand = rand or math.random
    local bySlot = {}
    for _, it in ipairs(items) do
        local slot = WEAR[it.equipLoc]
        if slot then
            bySlot[slot] = bySlot[slot] or {}
            table.insert(bySlot[slot], it.id)
        end
    end
    local out = {}
    for slot = 1, 13 do
        local list = bySlot[slot]
        if list then out[#out + 1] = list[rand(1, #list)] end
    end
    return out
end

function Fashion:Pool(wild)
    local ids = {}
    if wild then
        local Q = ns.modules.quests
        if Q and Q.enabled and Q:LoadData() then for _, id in ipairs(Q:AllItemIDs()) do ids[id] = true end end
        local market = ns.modules.market
        if market and market.Store then for id in pairs(market:Store()) do ids[id] = true end end
    end
    for _, rec in pairs(ns.db.chars) do
        for _, store in ipairs({ rec.bags or {}, rec.bank or {}, rec.worn or {} }) do
            for id in pairs(store) do ids[id] = true end
        end
    end
    local items = {}
    for id in pairs(ids) do
        local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)
        if equipLoc and WEAR[equipLoc] and (classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon) then
            items[#items + 1] = { id = id, equipLoc = equipLoc }
        end
    end
    return items
end

function Fashion:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 420)
    local model = CreateFrame("DressUpModel", nil, card)
    model:SetPoint("TOPLEFT", 10, -10)
    model:SetSize(width * 0.58, 400)
    model:SetUnit("player")
    model.facing = 0
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if self.dragX then
            local x = GetCursorPosition()
            self.facing = self.facing + (x - self.dragX) * 0.02
            self.dragX = x
            self:SetFacing(self.facing)
        end
    end)
    local right = width * 0.58 + 24
    local title = W.Label(card, L.FASHION_TITLE, "h1", "text")
    title:SetPoint("TOPLEFT", right, -20)
    local hint = W.Label(card, L.FASHION_HINT, "small", "text3")
    hint:SetPoint("TOPLEFT", right, -44)
    hint:SetWidth(width - right - 16)
    hint:SetWordWrap(true)
    local status = W.Label(card, "", "small", "accent")
    status:SetPoint("BOTTOMLEFT", right, 16)
    status:SetWidth(width - right - 16)
    local function dress(wild)
        local outfit = FUN.RandomOutfit(Fashion:Pool(wild))
        if #outfit == 0 then status:SetText(L.FASHION_EMPTY); return end
        model:Undress()
        for _, id in ipairs(outfit) do
            local _, link = C_Item.GetItemInfo(id)
            pcall(model.TryOn, model, link or ("item:" .. id))
        end
        Bump("fashion")
        FUN:CheckBadges()
        status:SetText(L.FASHION_DONE:format(#outfit))
    end
    local yy = -110
    local function button(text, kind, fn)
        local b = W.Button(card, text, kind, width - right - 16, 28)
        b:SetPoint("TOPLEFT", right, yy)
        b:SetScript("OnClick", fn)
        yy = yy - 36
        return b
    end
    button(L.FASHION_RANDOM, "primary", function() dress(false) end)
    button(L.FASHION_WILD, "primary", function() dress(true) end)
    button(L.FASHION_UNDRESS, "secondary", function() model:Undress() end)
    button(L.FASHION_RESET, "secondary", function() model:SetUnit("player"); model:Dress() end)
    button(L.FASHION_SPIN, "ghost", function()
        model.facing = model.facing + math.pi / 2
        model:SetFacing(model.facing)
    end)
    return y - 440
end

---------------------------------------------------------------------------
-- 3) Fun Stats & Badges (+ daily challenges)
---------------------------------------------------------------------------
local FS = ns:NewModule("funstats", {
    title = L.MOD_FUNSTATS, desc = L.MOD_FUNSTATS_DESC, order = 103, category = "fun",
    defaults = { track = true },
})
FS.options = { { type = "toggle", key = "track", label = L.FUNSTATS_TRACK, desc = L.FUNSTATS_TRACK_DESC } }

local lastPos, lastMoney
local function WorldPos()
    if IsInInstance() or UnitOnTaxi("player") then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    local p = map and C_Map.GetPlayerMapPosition(map, "player")
    if not p then return nil end
    local x = p:GetXY()
    if not x or ns.IsSecret(x) then return nil end
    local cont, pos = C_Map.GetWorldPosFromMapPos(map, p)
    if not (cont and pos) then return nil end
    local wx, wy = pos:GetXY()
    return cont, wx, wy
end

function FS:Walk()
    local c, x, y = WorldPos()
    if not c then lastPos = nil; return end
    if lastPos and lastPos[1] == c then
        local dx, dy = x - lastPos[2], y - lastPos[3]
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 0.5 and d < 60 then Bump("distance", d) end -- bigger jumps are teleports or flights
    end
    lastPos = { c, x, y }
    local hour = tonumber(date("%H"))
    if hour and hour >= 3 and hour < 5 and Stats().owl == 0 then Stats().owl = 1 end
end

function FS:OnEnable()
    local s = Stats()
    s.level = math.max(s.level, UnitLevel("player") or 0)
    lastMoney = GetMoney()
    self:RegisterEvent("PLAYER_DEAD", function() Bump("deaths"); ns:Fire("FUN_DIED") end)
    self:RegisterEvent("QUEST_TURNED_IN", function() Bump("quests") end)
    self:RegisterEvent("PLAYER_LEVEL_UP", function(_, _, level)
        local st = Stats()
        st.level = math.max(st.level, level or 0)
        ns:Fire("FUN_STAT", "level")
    end)
    self:RegisterEvent("PLAYER_MONEY", function()
        local m = GetMoney()
        if lastMoney and m > lastMoney then Bump("gold", m - lastMoney) end
        lastMoney = m
    end)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
        if unit == "player" and not ns.IsSecret(spellID) and spellID == 8690 then Bump("hearths") end
    end)
    -- counts your jumps after the game handled them (a post-hook can't change or block anything)
    if JumpOrAscendStart and not FS.jumpHooked then
        FS.jumpHooked = true
        hooksecurefunc("JumpOrAscendStart", function() if FS.enabled and FS:Get("track") then Bump("jumps") end end)
    end
    self.ticker = C_Timer.NewTicker(1, function() if FS:Get("track") then ns.Safe(FS.Walk, FS) end end)
    self.badgeTicker = C_Timer.NewTicker(10, function() ns.Safe(FUN.CheckBadges, FUN); ns.Safe(FUN.Daily, FUN) end)
end

function FS:OnDisable()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.badgeTicker then self.badgeTicker:Cancel(); self.badgeTicker = nil end
end

local function Bar(parent, w)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(w, 8)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(T.color("accent"))
    bar:SetMinMaxValues(0, 1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(T.color("line"))
    return bar
end

function FS:BuildPage(content, width, y)
    local s = Stats()
    local tiles = {
        { L.FS_JUMPS, function() return U.thousands(s.jumps) end },
        { L.FS_DEATHS, function() return U.thousands(s.deaths) end },
        { L.FS_DISTANCE, function() return U.thousands(math.floor(s.distance)) .. " yd" end },
        { L.FS_QUESTS, function() return U.thousands(s.quests) end },
        { L.FS_GOLD, function() return U.money(s.gold, true) end },
        { L.FS_HEARTHS, function() return U.thousands(s.hearths) end },
    }
    local tw = (width - 12) / 3
    local labels = {}
    for i, t in ipairs(tiles) do
        local c = W.Card(content)
        c:SetSize(tw - 2, 62)
        c:SetPoint("TOPLEFT", ((i - 1) % 3) * (tw + 6), y - math.floor((i - 1) / 3) * 70)
        local v = W.Label(c, "", "number", "accent")
        v:SetPoint("TOPLEFT", 14, -10)
        local k = W.Label(c, t[1], "small", "text2")
        k:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -4)
        labels[i] = { v, t[2] }
    end
    y = y - 148

    local daily = W.Card(content)
    daily:SetPoint("TOPLEFT", 0, y)
    daily:SetSize(width, 150)
    local dh = W.Label(daily, L.FUN_DAILY, "h2", "text")
    dh:SetPoint("TOPLEFT", 16, -14)
    local streak = W.Label(daily, "", "small", "accent", "RIGHT")
    streak:SetPoint("TOPRIGHT", -16, -16)
    local drows = {}
    for i = 1, 3 do
        local name = W.Label(daily, "", "body", "text")
        name:SetPoint("TOPLEFT", 16, -42 - (i - 1) * 34)
        local bar = Bar(daily, width - 200)
        bar:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
        local num = W.Label(daily, "", "small", "text2", "RIGHT")
        num:SetPoint("LEFT", bar, "RIGHT", 10, 0)
        drows[i] = { name = name, bar = bar, num = num }
    end
    y = y - 166

    local badges = W.Card(content)
    badges:SetPoint("TOPLEFT", 0, y)
    local bh = W.Label(badges, L.FUN_BADGES, "h2", "text")
    bh:SetPoint("TOPLEFT", 16, -14)
    local cols = 3
    local bw = (width - 32) / cols
    local bl = {}
    for i, b in ipairs(FUN.BADGES) do
        local fs = W.Label(badges, "", "small", "text3")
        fs:SetPoint("TOPLEFT", 16 + ((i - 1) % cols) * bw, -42 - math.floor((i - 1) / cols) * 34)
        fs:SetWidth(bw - 8)
        fs:SetJustifyH("LEFT")
        bl[i] = { fs = fs, badge = b }
    end
    local bheight = 50 + math.ceil(#FUN.BADGES / cols) * 34
    badges:SetSize(width, bheight)

    local function refresh()
        for _, l in ipairs(labels) do l[1]:SetText(l[2]()) end
        for i, c in ipairs(FUN:Daily()) do
            local r = drows[i]
            r.name:SetText((c.done and ("|cff" .. T.hex("good") .. "+|r ") or "") .. L["DAILY_" .. c.id:upper()]:format(U.thousands(c.need)))
            r.bar:SetValue(c.need > 0 and c.have / c.need or 0)
            r.num:SetText(U.thousands(math.floor(c.have)) .. " / " .. U.thousands(c.need))
        end
        streak:SetText(L.FUN_STREAK:format(s.streak))
        for _, e in ipairs(bl) do
            local key = "BADGE_" .. e.badge.id:upper()
            local got = s.badges[e.badge.id]
            e.fs:SetText("|cff" .. T.hex(got and "warn" or "text3") .. (got and "[*] " or "[ ] ") .. L[key] .. "|r\n|cff"
                .. T.hex("text3") .. L[key .. "_DESC"] .. "|r")
        end
    end
    content:HookScript("OnShow", refresh)
    ns:On("FUN_STAT", function() if content:IsVisible() then refresh() end end)
    refresh()
    return y - bheight - 20
end

---------------------------------------------------------------------------
-- 4) Hex Hop – click the hex logos before they vanish (30-second rounds)
---------------------------------------------------------------------------
local Hex = ns:NewModule("hexhop", {
    title = L.MOD_HEXHOP, desc = L.MOD_HEXHOP_DESC, order = 104, category = "fun",
})

-- Pure: points for a hit (golden hexes are worth 3, combos add a bonus). Unit-tested.
function FUN.HexPoints(golden, combo)
    return (golden and 3 or 1) + math.floor((combo or 0) / 5)
end

function Hex:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 400)
    local score = W.Label(card, "", "number", "accent")
    score:SetPoint("TOPLEFT", 16, -14)
    local info = W.Label(card, "", "small", "text2")
    info:SetPoint("TOPLEFT", score, "BOTTOMLEFT", 0, -4)
    local start = W.Button(card, L.HEX_START, "primary", 140, 28)
    start:SetPoint("TOPRIGHT", -16, -14)
    local N, size = 4, 64
    local cells = {}
    local game = { running = false, score = 0, combo = 0, left = 0 }
    local gridLeft = (width - N * (size + 8)) / 2
    local function draw()
        score:SetText(L.HEX_SCORE:format(game.score))
        info:SetText(game.running and L.HEX_TIME:format(math.ceil(game.left)) or L.HEX_BEST:format(Stats().hexBest))
    end
    local function unlight(c) c.lit = nil; c.mark:Hide(); T.Tint(c.bg, "card2") end
    for i = 1, N * N do
        local c = CreateFrame("Button", nil, card)
        c:SetSize(size, size)
        c:SetPoint("TOPLEFT", gridLeft + ((i - 1) % N) * (size + 8), -80 - math.floor((i - 1) / N) * (size + 8))
        c.bg = T.Shape(c, "round", "card2", "BACKGROUND")
        c.mark = W.Icon(c, "mark", size - 18)
        c.mark:SetPoint("CENTER")
        c.mark:Hide()
        c:SetScript("OnClick", function(self)
            if not game.running then return end
            if self.lit then
                game.combo = game.combo + 1
                game.score = game.score + FUN.HexPoints(self.lit == "gold", game.combo)
                T.Sound("on")
            else
                game.combo = 0
                game.score = math.max(0, game.score - 1)
                T.Sound("off")
            end
            unlight(self)
            draw()
        end)
        T.Focusable(c)
        cells[i] = c
    end
    local function stop()
        game.running = false
        if game.ticker then game.ticker:Cancel(); game.ticker = nil end
        for _, c in ipairs(cells) do unlight(c) end
        local s = Stats()
        Bump("hex")
        if game.score > s.hexBest then
            s.hexBest = game.score
            ns:Toast(L.MOD_HEXHOP, L.HEX_NEW_BEST:format(game.score), "star")
        end
        FUN:CheckBadges()
        start:SetLabel(L.HEX_AGAIN)
        draw()
    end
    start:SetScript("OnClick", function()
        if game.running then return end
        game.running, game.score, game.combo, game.left = true, 0, 0, 30
        local step = 0
        game.ticker = C_Timer.NewTicker(0.1, function()
            game.left = game.left - 0.1
            step = step + 1
            if game.left <= 0 or not card:IsVisible() then stop(); return end
            local every = math.max(3, 8 - math.floor((30 - game.left) / 6)) -- faster over time
            if step % every == 0 then
                for _, c in ipairs(cells) do
                    if c.lit and math.random() < 0.35 then unlight(c) end
                end
                local c = cells[math.random(1, #cells)]
                c.lit = math.random() < 0.12 and "gold" or "hex"
                c.mark:Show()
                if c.lit == "gold" then c.mark:SetVertexColor(1, 0.82, 0.2, 1) else c.mark:SetVertexColor(T.color("accent")) end
                T.Tint(c.bg, "hover")
            end
            draw()
        end)
        draw()
    end)
    local how = W.Label(card, L.HEX_HOW, "small", "text3")
    how:SetPoint("BOTTOMLEFT", 16, 14)
    how:SetWidth(width - 32)
    how:SetWordWrap(true)
    draw()
    return y - 420
end

---------------------------------------------------------------------------
-- 5) Fun Moments – fortune of the day, level-up party, death roast, AFK show
---------------------------------------------------------------------------
local FM = ns:NewModule("moments", {
    title = L.MOD_MOMENTS, desc = L.MOD_MOMENTS_DESC, order = 105, category = "fun",
    defaults = { fortune = true, party = true, roast = true, afk = true },
    charDefaults = { fortuneDay = 0 },
})
FM.options = {
    { type = "toggle", key = "fortune", label = L.FM_FORTUNE, desc = L.FM_FORTUNE_DESC },
    { type = "toggle", key = "party", label = L.FM_PARTY, desc = L.FM_PARTY_DESC },
    { type = "toggle", key = "roast", label = L.FM_ROAST, desc = L.FM_ROAST_DESC },
    { type = "toggle", key = "afk", label = L.FM_AFK, desc = L.FM_AFK_DESC },
    { type = "button", label = L.FM_TRY_PARTY, desc = L.FM_TRY_PARTY_DESC, buttonText = L.FM_TRY, onClick = function() FM:Party() end },
    { type = "button", label = L.FM_TRY_AFK, desc = L.FM_TRY_AFK_DESC, buttonText = L.FM_TRY, onClick = function() FM:ShowAFK(true) end },
}

function FM:Fortune(force)
    local today = FUN.Today()
    if not force and (not self:Get("fortune") or self:Get("fortuneDay") == today) then return end
    self:Set("fortuneDay", today)
    local text = FUN.FortuneFor(today)
    ns:Print("|cffffd200" .. L.FM_FORTUNE_TITLE .. "|r " .. text)
    if not force then ns:Toast(L.FM_FORTUNE_TITLE, text, "star") end
end

-- Confetti: our own little squares falling over the screen for a few seconds
local confetti
function FM:Party()
    if not confetti then
        confetti = CreateFrame("Frame", nil, UIParent)
        confetti:SetAllPoints()
        confetti:SetFrameStrata("FULLSCREEN_DIALOG")
        confetti:EnableMouse(false)
        confetti.bits = {}
        local colors = { { 0.22, 0.78, 0.96 }, { 1, 0.82, 0.2 }, { 1, 0.4, 0.7 }, { 0.45, 1, 0.4 }, { 0.7, 0.45, 1 } }
        for i = 1, 60 do
            local t = confetti:CreateTexture(nil, "OVERLAY")
            local col = colors[(i % #colors) + 1]
            t:SetColorTexture(col[1], col[2], col[3], 1)
            local ag = t:CreateAnimationGroup()
            local move = ag:CreateAnimation("Translation")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0)
            ag:SetScript("OnFinished", function() t:Hide() end)
            confetti.bits[i] = { tex = t, ag = ag, move = move, fade = fade }
        end
    end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    for _, b in ipairs(confetti.bits) do
        local size = math.random(5, 11)
        b.tex:SetSize(size, size * (math.random() + 0.5))
        b.tex:ClearAllPoints()
        b.tex:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", math.random(0, math.floor(w)), math.random(-40, 0))
        local dur = 2.2 + math.random() * 1.6
        b.move:SetOffset(math.random(-120, 120), -h * (0.6 + math.random() * 0.5))
        b.move:SetDuration(dur)
        b.fade:SetStartDelay(dur * 0.7)
        b.fade:SetDuration(dur * 0.3)
        b.tex:Show()
        b.ag:Stop()
        b.ag:Play()
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK) end
end

function FM:Roast()
    if not self:Get("roast") then return end
    local n = Stats().deaths
    ns:Print("|cffff7070" .. L.FM_DEATH_N:format(n) .. "|r " .. FUN.ROASTS[(n % #FUN.ROASTS) + 1])
end

-- AFK show: your character turning slowly, with your stats. Hides when you're back or in combat.
local afk
function FM:ShowAFK(preview)
    if ns.InCombat() then return end
    if not afk then
        afk = CreateFrame("Button", "HawarysAFKShow", UIParent)
        afk:SetAllPoints()
        afk:SetFrameStrata("FULLSCREEN_DIALOG")
        afk.bg = afk:CreateTexture(nil, "BACKGROUND")
        afk.bg:SetAllPoints()
        afk.bg:SetColorTexture(0.03, 0.04, 0.06, 0.82)
        afk.model = CreateFrame("PlayerModel", nil, afk)
        afk.model:SetSize(420, 520)
        afk.model:SetPoint("LEFT", UIParent, "CENTER", -460, 0)
        afk.logo = W.Icon(afk, "logo", 96)
        afk.logo:SetPoint("TOPLEFT", UIParent, "CENTER", 40, 200)
        afk.name = W.Label(afk, "", "brandBig", "text")
        afk.name:SetPoint("TOPLEFT", afk.logo, "BOTTOMLEFT", 0, -14)
        afk.sub = W.Label(afk, "", "h2", "accent")
        afk.sub:SetPoint("TOPLEFT", afk.name, "BOTTOMLEFT", 0, -6)
        afk.lines = W.Label(afk, "", "body", "text2")
        afk.lines:SetPoint("TOPLEFT", afk.sub, "BOTTOMLEFT", 0, -16)
        afk.lines:SetJustifyH("LEFT")
        afk.fortune = W.Label(afk, "", "body", "warn")
        afk.fortune:SetPoint("TOPLEFT", afk.lines, "BOTTOMLEFT", 0, -16)
        afk.fortune:SetWidth(420)
        afk.fortune:SetWordWrap(true)
        afk.hint = W.Label(afk, L.FM_AFK_HINT, "small", "text3", "CENTER")
        afk.hint:SetPoint("BOTTOM", 0, 40)
        afk:SetScript("OnClick", function(self) self:Hide() end)
        afk:SetScript("OnUpdate", function(self, elapsed)
            self.facing = (self.facing or 0) + elapsed * 0.4
            self.model:SetFacing(self.facing)
            self.t = (self.t or 0) + elapsed
            if self.t > 1 then
                self.t = 0
                self.sub:SetText(L.FM_AFK_FOR:format(ns.JourneyData.FormatDuration(time() - (self.since or time()))))
            end
        end)
        tinsert(UISpecialFrames, "HawarysAFKShow")
    end
    local s = Stats()
    afk.since = time()
    afk.model:SetUnit("player")
    afk.name:SetText((UnitName("player") or "") .. "  ·  " .. L.LEVEL_N:format(UnitLevel("player")))
    afk.sub:SetText(L.FM_AFK_FOR:format("0s"))
    afk.lines:SetText(L.FM_AFK_STATS:format(U.thousands(s.jumps), U.thousands(math.floor(s.distance)), U.thousands(s.quests), U.thousands(s.deaths)))
    afk.fortune:SetText("\"" .. FUN.FortuneFor(FUN.Today()) .. "\"")
    afk.preview = preview
    afk:Show()
end

function FM:HideAFK()
    if afk then afk:Hide() end
end

function FM:OnEnable()
    self:RegisterEvent("PLAYER_LEVEL_UP", function() if FM:Get("party") then FM:Party() end end)
    self:RegisterEvent("PLAYER_FLAGS_CHANGED", function(_, _, unit)
        if unit ~= "player" then return end
        if UnitIsAFK("player") then
            if FM:Get("afk") and not ns.InCombat() then FM:ShowAFK() end
        elseif afk and not afk.preview then
            FM:HideAFK()
        end
    end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() FM:HideAFK() end)
    C_Timer.After(6, function() if FM.enabled then ns.Safe(FM.Fortune, FM) end end)
end

function FM:OnDisable() self:HideAFK() end

ns:On("FUN_DIED", function() if FM.enabled then FM:Roast() end end)
ns:On("FUN_FORTUNE", function() FM:Fortune(true) end)
