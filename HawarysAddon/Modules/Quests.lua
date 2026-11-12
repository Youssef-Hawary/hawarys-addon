-- Hawary's Addon: Quests – the quest database layer (Questie-style), plus data for the
-- Zygor/RestedXP-style Smart Route in Journey.
--   * quest givers you can take (!), turn-ins (?), every objective spot (mobs, objects such as
--     eggs or crates, item drops, places to explore) and hidden "secret" objectives
--   * world map pins, minimap pins, and quest lines in mob / object / item tooltips
-- Data: an installed QuestieDB is used when present; otherwise our bundled copy
-- (HawarysAddon_QuestData, from QuestieDB under GPLv3). Read-only; nothing is automated.
local _, ns = ...
local L, T, W, Q = ns.L, ns.Theme, ns.W, ns.QuestLogic
local F = Q.FIELDS

local Quests = ns:NewModule("quests", {
    title = L.MOD_QUESTS,
    desc = L.MOD_QUESTS_DESC,
    order = 0.5,
    defaults = { available = true, trivial = false, turnins = true, objectives = true, minimap = true, tooltips = true, route = true },
})

Quests.options = {
    { type = "toggle", key = "available", label = L.QUESTS_AVAILABLE, desc = L.QUESTS_AVAILABLE_DESC },
    { type = "toggle", key = "trivial", label = L.QUESTS_TRIVIAL, desc = L.QUESTS_TRIVIAL_DESC, parent = "available" },
    { type = "toggle", key = "turnins", label = L.QUESTS_TURNINS, desc = L.QUESTS_TURNINS_DESC },
    { type = "toggle", key = "objectives", label = L.QUESTS_OBJECTIVES, desc = L.QUESTS_OBJECTIVES_DESC },
    { type = "toggle", key = "minimap", label = L.QUESTS_MINIMAP, desc = L.QUESTS_MINIMAP_DESC },
    { type = "toggle", key = "tooltips", label = L.QUESTS_TOOLTIPS, desc = L.QUESTS_TOOLTIPS_DESC },
    { type = "toggle", key = "route", label = L.QUESTS_ROUTE, desc = L.QUESTS_ROUTE_DESC },
}

local STYLE = {
    available = { icon = "quest_new", color = { 1, 0.82, 0.24 }, size = 18 },
    low = { icon = "quest_new", color = { 0.75, 0.45, 0.45 }, size = 16 },
    trivial = { icon = "quest_new", color = { 0.6, 0.6, 0.6 }, size = 15 },
    turnin = { icon = "quest_done", color = { 1, 0.82, 0.24 }, size = 18 },
    npc = { icon = "dot", color = { 1, 0.35, 0.35 }, size = 11 },
    object = { icon = "dot", color = { 1, 0.85, 0.3 }, size = 11 },
    item_npc = { icon = "dot", color = { 0.3, 0.9, 0.5 }, size = 11 },
    item_object = { icon = "dot", color = { 0.3, 0.9, 0.5 }, size = 11 },
    explore = { icon = "pin", color = { 0.22, 0.78, 0.96 }, size = 16 },
    secret = { icon = "star", color = { 0.75, 0.5, 1 }, size = 14 },
}
Quests.STYLE = STYLE

---------------------------------------------------------------------------
-- Data source
---------------------------------------------------------------------------
local tables, rows = {}, {}
local areaMap, areaOverride
local lib -- LibQuestieDB when installed

local ENTITY = { quest = "Quest", npc = "Npc", object = "Object", item = "Item" }

function Quests:LoadData()
    if self.dataReady ~= nil then return self.dataReady end
    if LibQuestieDB and LibQuestieDB.Quest and LibQuestieDB.Quest.Get then lib = LibQuestieDB end
    if not HawarysQuestData and C_AddOns.DoesAddOnExist("HawarysAddon_QuestData") then
        C_AddOns.LoadAddOn("HawarysAddon_QuestData")
    end
    local data = HawarysQuestData
    if data then
        areaMap = Q.Decode(data.areaToUiMap) or {}
        areaOverride = Q.Decode(data.areaToUiMapOverride) or {}
    end
    self.source = lib and "questiedb" or (data and "bundled") or nil
    self.dataReady = (lib ~= nil or data ~= nil) and areaMap ~= nil
    return self.dataReady
end

local function Table(entity)
    local t = tables[entity]
    if t == nil then
        t = Q.Decode(HawarysQuestData and HawarysQuestData[entity]) or false
        tables[entity] = t
    end
    return t or nil
end

-- A row (indexed like QuestieDB's positional data) or nil
function Quests:Row(entity, id)
    if not id then return nil end
    if lib then
        local E = lib[ENTITY[entity]]
        if not (E and E.Exists and E.Exists(id)) then return nil end
        local key = entity .. id
        local r = rows[key]
        if not r then
            r = setmetatable({}, { __index = function(_, k) return E.Get(id, k) end })
            rows[key] = r
        end
        return r
    end
    local t = Table(entity)
    return t and t[id]
end

-- One field of an entity (not to be confused with Module:Get, which reads settings)
function Quests:Data(entity, id, field)
    local r = self:Row(entity, id)
    return r and r[F[entity][field]]
end

function Quests:AllQuestIDs()
    if lib then return lib.Quest.GetAllIds() end
    local ids = {}
    for id in pairs(Table("quest") or {}) do ids[#ids + 1] = id end
    return ids
end

function Quests:AllItemIDs()
    if lib then return (lib.Item and lib.Item.GetAllIds) and lib.Item.GetAllIds() or {} end
    local ids = {}
    for id in pairs(Table("item") or {}) do ids[#ids + 1] = id end
    return ids
end

function Quests:MapOf(areaID)
    if not areaMap then return nil end
    local o = areaOverride[areaID]
    if o ~= nil then return o ~= 0 and o or nil end
    return areaMap[areaID]
end

---------------------------------------------------------------------------
-- What's available for this character
---------------------------------------------------------------------------
function Quests:Context()
    local completed = {}
    for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do completed[id] = true end
    local active, complete = {}, {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            active[info.questID] = true
            if C_QuestLog.IsComplete(info.questID) or C_QuestLog.ReadyForTurnIn(info.questID) then complete[info.questID] = true end
        end
    end
    local _, _, raceID = UnitRace("player")
    local _, _, classID = UnitClass("player")
    return {
        level = UnitLevel("player"), raceID = raceID, classID = classID, faction = UnitFactionGroup("player"),
        completed = completed, active = active, complete = complete, greyDiff = 7,
        skill = function(skillID)
            local s = C_SkillInfo.GetSkillLineInfoByID(skillID)
            return s and s.rank
        end,
    }
end

function Quests:Rebuild()
    if not self:LoadData() then return end
    local ctx = self:Context()
    local available = {}
    for _, id in ipairs(self:AllQuestIDs()) do
        local row = self:Row("quest", id)
        if row then
            local status = Q.Status(row, id, ctx)
            if status then available[id] = status end
        end
    end
    self.ctx, self.available = ctx, available
    self.pinCache = {}
    self:BuildTooltipIndex()
    ns:Fire("QUESTS_UPDATED")
end

function Quests:QueueRebuild()
    if self.rebuildQueued then return end
    self.rebuildQueued = true
    C_Timer.After(1, function()
        self.rebuildQueued = false
        if self.enabled then ns.Safe(self.Rebuild, self) end
    end)
end

---------------------------------------------------------------------------
-- Pins for one map: { {x, y, kind, quest, name} }
---------------------------------------------------------------------------
local MAX_PINS = 900
local MAX_PER_SOURCE = 80

local function addSpawns(out, spawns, mapID, kind, name, questID)
    local pts = Q.SpawnsOnMap(spawns, function(a) return Quests:MapOf(a) end, mapID)
    for i = 1, math.min(#pts, MAX_PER_SOURCE) do
        if #out >= MAX_PINS then return end
        out[#out + 1] = { x = pts[i][1], y = pts[i][2], kind = kind, name = name, quest = questID }
    end
end

function Quests:PinsFor(mapID)
    if not (mapID and self.available) then return {} end
    if self.pinCache[mapID] then return self.pinCache[mapID] end
    local out, ctx = {}, self.ctx
    if self:Get("available") then
        for id, status in pairs(self.available) do
            if status ~= "trivial" or self:Get("trivial") then
                local starts = self:Data("quest", id, "startedBy") or {}
                for _, npcID in ipairs(starts[1] or {}) do
                    local npc = self:Row("npc", npcID)
                    if npc and Q.FriendlyTo(npc[F.npc.friendlyToFaction], ctx.faction) then
                        addSpawns(out, npc[F.npc.spawns], mapID, status, npc[F.npc.name], id)
                    end
                end
                for _, objID in ipairs(starts[2] or {}) do
                    local obj = self:Row("object", objID)
                    if obj then addSpawns(out, obj[F.object.spawns], mapID, status, obj[F.object.name], id) end
                end
            end
        end
    end
    for id in pairs(ctx.active) do
        local quest = self:Row("quest", id)
        if quest then
            if ctx.complete[id] then
                if self:Get("turnins") then
                    local ends = quest[F.quest.finishedBy] or {}
                    for _, npcID in ipairs(ends[1] or {}) do
                        local npc = self:Row("npc", npcID)
                        if npc then addSpawns(out, npc[F.npc.spawns], mapID, "turnin", npc[F.npc.name], id) end
                    end
                    for _, objID in ipairs(ends[2] or {}) do
                        local obj = self:Row("object", objID)
                        if obj then addSpawns(out, obj[F.object.spawns], mapID, "turnin", obj[F.object.name], id) end
                    end
                end
            elseif self:Get("objectives") then
                local get = function(e, eid, field) return self:Data(e, eid, field) end
                for _, src in ipairs(Q.ObjectiveSources(quest, get)) do
                    local name = src.label
                    if not name and src.id then
                        local ent = (src.kind == "npc" or src.kind == "item_npc") and "npc" or "object"
                        name = self:Data(ent, src.id, "name")
                    end
                    addSpawns(out, src.spawns, mapID, src.kind, name, id)
                end
            end
        end
    end
    self.pinCache[mapID] = out
    return out
end

-- Quest title from the client when possible (localized), else the database
function Quests:Title(id)
    return C_QuestLog.GetTitleForQuestID(id) or self:Data("quest", id, "name") or ("#" .. id)
end

---------------------------------------------------------------------------
-- World map pins (Blizzard's data provider + pin system)
---------------------------------------------------------------------------
local Provider
local function SetupMapLayer()
    if Provider or not (MapCanvasPinMixin and MapCanvasDataProviderMixin and WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
    HawarysQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
    function HawarysQuestPinMixin:OnLoad()
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        self:SetScalingLimits(1, 1.0, 1.3)
    end
    function HawarysQuestPinMixin:OnAcquired(pin)
        self.pin = pin
        local s = STYLE[pin.kind] or STYLE.npc
        self:SetSize(s.size, s.size)
        self:SetPosition(pin.x, pin.y)
        self.Icon:SetTexture(ns.media .. s.icon)
        self.Icon:SetVertexColor(s.color[1], s.color[2], s.color[3])
        self.Glow:SetVertexColor(s.color[1], s.color[2], s.color[3], s.size >= 16 and 0.35 or 0)
    end
    function HawarysQuestPinMixin:OnMouseEnter() Quests:PinTooltip(self, self.pin) end
    function HawarysQuestPinMixin:OnMouseLeave() GameTooltip:Hide() end
    Provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function Provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate("HawarysQuestPinTemplate")
    end
    function Provider:RefreshAllData()
        self:RemoveAllData()
        if not Quests.enabled then return end
        for _, pin in ipairs(Quests:PinsFor(self:GetMap():GetMapID())) do
            self:GetMap():AcquirePin("HawarysQuestPinTemplate", pin)
        end
    end
    WorldMapFrame:AddDataProvider(Provider)
end

function Quests:RefreshMap()
    if Provider and WorldMapFrame:IsShown() then Provider:RefreshAllData() end
end

local KIND_TEXT
function Quests:PinTooltip(owner, pin)
    KIND_TEXT = KIND_TEXT or {
        available = L.QUESTS_PIN_AVAILABLE, low = L.QUESTS_PIN_LOW, trivial = L.QUESTS_PIN_TRIVIAL, turnin = L.QUESTS_PIN_TURNIN,
        npc = L.QUESTS_PIN_KILL, object = L.QUESTS_PIN_OBJECT, item_npc = L.QUESTS_PIN_DROP, item_object = L.QUESTS_PIN_LOOT,
        explore = L.QUESTS_PIN_EXPLORE, secret = L.QUESTS_PIN_SECRET,
    }
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(pin.name or "", 1, 1, 1)
    local s = STYLE[pin.kind] or STYLE.npc
    GameTooltip:AddLine(KIND_TEXT[pin.kind] or "", s.color[1], s.color[2], s.color[3])
    GameTooltip:AddLine(self:Title(pin.quest), 1, 0.82, 0)
    local lvl = self:Data("quest", pin.quest, "questLevel")
    if lvl and lvl > 0 then GameTooltip:AddLine(L.QUESTS_LEVEL:format(lvl), 0.68, 0.72, 0.78) end
    GameTooltip:AddLine("|cff38c6f4Hawary's|r " .. L.MOD_QUESTS, 0.47, 0.5, 0.56)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Minimap pins (nearest spots on your current map)
---------------------------------------------------------------------------
local miniPins, miniTicker = {}, nil
local rectCache = {}

function Quests:MapRect(mapID)
    local r = rectCache[mapID]
    if r == nil then
        local c1, tl = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local c2, br = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if c1 and tl and br and c1 == c2 then
            local tlx, tly = tl:GetXY()
            local brx, bry = br:GetXY()
            r = { tlx, tly, brx, bry }
        else
            r = false
        end
        rectCache[mapID] = r
    end
    return r or nil
end

local function MiniPin(i)
    local p = miniPins[i]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetFrameLevel(Minimap:GetFrameLevel() + 6)
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetAllPoints()
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) if self.pin then Quests:PinTooltip(self, self.pin) end end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        miniPins[i] = p
    end
    return p
end

function Quests:UpdateMinimap()
    local shown = 0
    if self.enabled and self:Get("minimap") and self.available and not ns.InCombat() then
        local mapID = C_Map.GetBestMapForUnit("player")
        local rect = mapID and self:MapRect(mapID)
        local pos = rect and C_Map.GetPlayerMapPosition(mapID, "player")
        local mx, my
        if pos then mx, my = pos:GetXY() end
        if mx and not ns.IsSecret(mx) then
            local px, py = Q.ToWorld(rect, mx, my)
            local radius = (IsIndoors() and Q.MINIMAP_INDOOR or Q.MINIMAP_OUTDOOR)[Minimap:GetZoom()] or 200
            local rotate = C_CVar.GetCVar("rotateMinimap") == "1"
            local facing = rotate and GetPlayerFacing() or nil
            if facing and ns.IsSecret(facing) then facing = nil end
            local pixel = Minimap:GetWidth() / 2 - 6
            local best = {}
            for _, pin in ipairs(self:PinsFor(mapID)) do
                local tx, ty = Q.ToWorld(rect, pin.x, pin.y)
                local ox, oy, dist = Q.MinimapOffset(px, py, tx, ty, radius, pixel, facing ~= nil, facing)
                if ox then best[#best + 1] = { pin = pin, ox = ox, oy = oy, dist = dist } end
            end
            table.sort(best, function(a, b) return a.dist < b.dist end)
            for i = 1, math.min(#best, 60) do
                local b = best[i]
                local s = STYLE[b.pin.kind] or STYLE.npc
                local p = MiniPin(i)
                p.pin = b.pin
                local size = s.size >= 16 and 14 or 8
                p:SetSize(size, size)
                p.icon:SetTexture(ns.media .. s.icon)
                p.icon:SetVertexColor(s.color[1], s.color[2], s.color[3])
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", b.ox, b.oy)
                p:Show()
                shown = i
            end
        end
    end
    for i = shown + 1, #miniPins do miniPins[i]:Hide() end
end

---------------------------------------------------------------------------
-- Tooltips: quest lines on mobs, objects and items
---------------------------------------------------------------------------
function Quests:BuildTooltipIndex()
    local byName, byItem = {}, {}
    local ctx = self.ctx
    local function add(map, key, line)
        if not key then return end
        map[key] = map[key] or {}
        table.insert(map[key], line)
    end
    for id in pairs(ctx.active) do
        local quest = self:Row("quest", id)
        if quest and not ctx.complete[id] then
            local obj = quest[F.quest.objectives] or {}
            for _, o in ipairs(obj[1] or {}) do add(byName, self:Data("npc", o[1], "name"), { quest = id, kind = "npc" }) end
            for _, o in ipairs(obj[2] or {}) do add(byName, self:Data("object", o[1], "name"), { quest = id, kind = "object" }) end
            for _, o in ipairs(obj[3] or {}) do
                add(byItem, o[1], { quest = id, kind = "item" })
                for _, npcID in ipairs(self:Data("item", o[1], "npcDrops") or {}) do
                    add(byName, self:Data("npc", npcID, "name"), { quest = id, kind = "drop", item = o[1] })
                end
                for _, objID in ipairs(self:Data("item", o[1], "objectDrops") or {}) do
                    add(byName, self:Data("object", objID, "name"), { quest = id, kind = "drop", item = o[1] })
                end
            end
        elseif quest and ctx.complete[id] then
            for _, npcID in ipairs((quest[F.quest.finishedBy] or {})[1] or {}) do
                add(byName, self:Data("npc", npcID, "name"), { quest = id, kind = "turnin" })
            end
        end
    end
    for id, status in pairs(self.available or {}) do
        if status == "available" then
            for _, npcID in ipairs((self:Data("quest", id, "startedBy") or {})[1] or {}) do
                add(byName, self:Data("npc", npcID, "name"), { quest = id, kind = "starts" })
            end
        end
    end
    self.tipByName, self.tipByItem = byName, byItem
end

local function ObjectiveProgress(questID, hint)
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        if hint and o.text and o.text:find(hint, 1, true) then return o.text, o.finished end
    end
    return nil
end

function Quests:AddLines(tooltip, lines, hint)
    if not lines then return false end
    local added = false
    for _, line in ipairs(lines) do
        local title = self:Title(line.quest)
        local text, done
        if line.kind == "starts" then
            text = L.QUESTS_TIP_STARTS:format(title)
        elseif line.kind == "turnin" then
            text = L.QUESTS_TIP_TURNIN:format(title)
        else
            local progress
            progress, done = ObjectiveProgress(line.quest, line.item and self:Data("item", line.item, "name") or hint)
            text = title .. (progress and ("  |cffaeb7c7" .. progress .. "|r") or "")
        end
        if not done then
            if not added then tooltip:AddLine(" ") end
            tooltip:AddLine("|T" .. ns.media .. "mark:12:12|t " .. text, 1, 0.82, 0.24)
            added = true
        end
    end
    return added
end

local function OnUnitTooltip(tooltip)
    if not (Quests.enabled and Quests:Get("tooltips") and Quests.tipByName) or tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    if not unit or UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if not name or ns.IsSecret(name) then return end
    if Quests:AddLines(tooltip, Quests.tipByName[name], name) then tooltip:Show() end
end

local function OnObjectTooltip(tooltip, data)
    if not (Quests.enabled and Quests:Get("tooltips") and Quests.tipByName) or tooltip ~= GameTooltip then return end
    local line = data and data.lines and data.lines[1]
    local name = line and line.leftText
    if not name or ns.IsSecret(name) then return end
    if Quests:AddLines(tooltip, Quests.tipByName[name], name) then tooltip:Show() end
end

local function OnItemTooltip(tooltip)
    if not (Quests.enabled and Quests:Get("tooltips") and Quests.tipByItem) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link or ns.IsSecret(link) then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    if Quests:AddLines(tooltip, Quests.tipByItem[itemID], C_Item.GetItemNameByID(itemID)) then tooltip:Show() end
end

---------------------------------------------------------------------------
-- Smart Route provider for Journey (Zygor / RestedXP style, built from real data)
---------------------------------------------------------------------------
local function PlayerOnMap()
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or ns.IsSecret(x) then return nil end
    return mapID, x, y
end

local function Dist2(rect, ax, ay, bx, by)
    if rect then
        local wx1, wy1 = Q.ToWorld(rect, ax, ay)
        local wx2, wy2 = Q.ToWorld(rect, bx, by)
        return (wx1 - wx2) ^ 2 + (wy1 - wy2) ^ 2
    end
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end

ns.QuestProvider = {
    -- Nearest quest givers you can take on your current map
    NearbyAvailable = function(max)
        if not (Quests.enabled and Quests:Get("route") and Quests.available) then return {} end
        local mapID, px, py = PlayerOnMap()
        if not mapID then return {} end
        local rect = Quests:MapRect(mapID)
        local best = {}
        for _, pin in ipairs(Quests:PinsFor(mapID)) do
            if pin.kind == "available" then
                local d = Dist2(rect, px, py, pin.x, pin.y)
                local cur = best[pin.quest]
                if not cur or d < cur.d then best[pin.quest] = { pin = pin, d = d } end
            end
        end
        local list = {}
        for questID, b in pairs(best) do
            list[#list + 1] = { questID = questID, name = Quests:Title(questID), giver = b.pin.name, mapID = mapID, x = b.pin.x, y = b.pin.y, d = b.d }
        end
        table.sort(list, function(a, b) return a.d < b.d end)
        for i = #list, (max or 3) + 1, -1 do list[i] = nil end
        return list
    end,
    -- Nearest spot for an active quest (objective, or the turn-in when finished)
    NearestFor = function(questID)
        if not (Quests.enabled and Quests.available) then return nil end
        local mapID, px, py = PlayerOnMap()
        if not mapID then return nil end
        local rect = Quests:MapRect(mapID)
        local bestPin, bestD
        for _, pin in ipairs(Quests:PinsFor(mapID)) do
            if pin.quest == questID and pin.kind ~= "available" and pin.kind ~= "low" and pin.kind ~= "trivial" then
                local d = Dist2(rect, px, py, pin.x, pin.y)
                if not bestD or d < bestD then bestPin, bestD = pin, d end
            end
        end
        return bestPin and { mapID = mapID, x = bestPin.x, y = bestPin.y, quest = questID } or nil
    end,
}

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Quests:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 96)
    local count = W.Label(card, "", "number", "accent")
    count:SetPoint("TOPLEFT", 18, -14)
    W.Label(card, L.QUESTS_COUNT, "small", "text3"):SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -4)
    local near = W.Label(card, "", "number", "text")
    near:SetPoint("TOPLEFT", width / 2, -14)
    W.Label(card, L.QUESTS_NEAR, "small", "text3"):SetPoint("TOPLEFT", near, "BOTTOMLEFT", 0, -4)
    local source = W.Label(card, "", "small", "text2")
    source:SetPoint("BOTTOMLEFT", 18, 12)
    y = y - 96 - 16
    y = ns:BuildOptions(self, content, width, y)

    local listTop = y
    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", 0, y)
    list:SetWidth(width)
    list.title = W.Label(list, L.QUESTS_HERE, "h2", "accent")
    list.title:SetPoint("TOPLEFT")
    list.rows = {}
    function list:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        local n = 0
        for _, status in pairs(Quests.available or {}) do if status == "available" then n = n + 1 end end
        count:SetText(Quests.available and n or "–")
        local nearby = ns.QuestProvider.NearbyAvailable(25)
        near:SetText(#nearby)
        local info = HawarysQuestData and HawarysQuestData.info
        source:SetText(Quests.source == "questiedb" and L.QUESTS_SOURCE_QDB
            or (Quests.source == "bundled" and L.QUESTS_SOURCE_BUNDLED:format(info and info.built or "?"))
            or L.QUESTS_SOURCE_NONE)
        local ly = -26
        for i, q in ipairs(nearby) do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Button", nil, self)
                row:SetHeight(26)
                row.bg = T.Shape(row, "round_sm", "card", "BACKGROUND")
                row.icon = W.Icon(row, "quest_new", 14, { 1, 0.82, 0.24, 1 })
                row.icon:SetPoint("LEFT", 8, 0)
                row.name = W.Label(row, "", "body", "text")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.giver = W.Label(row, "", "small", "text3", "RIGHT")
                row.giver:SetPoint("RIGHT", -10, 0)
                row:SetScript("OnEnter", function(selfRow) T.Tint(selfRow.bg, "hover") end)
                row:SetScript("OnLeave", function(selfRow) T.Tint(selfRow.bg, "card") end)
                row:SetScript("OnClick", function(selfRow)
                    if selfRow.q and C_Map.CanSetUserWaypointOnMap(selfRow.q.mapID) then
                        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(selfRow.q.mapID, selfRow.q.x, selfRow.q.y))
                        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                    end
                end)
                W.Tooltip(row, L.QUESTS_WAYPOINT)
                self.rows[i] = row
            end
            row.q = q
            local lvl = Quests:Data("quest", q.questID, "questLevel") or 0
            row.name:SetText(("[%d] %s"):format(lvl, q.name))
            row.giver:SetText(("%s  ·  %.1f, %.1f"):format(q.giver or "", q.x * 100, q.y * 100))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, ly)
            row:SetPoint("TOPRIGHT", 0, ly)
            row:Show()
            ly = ly - 30
        end
        self:SetHeight(-ly)
        content:SetHeight(-listTop - ly + 20)
        return ly
    end
    ns:On("QUESTS_UPDATED", function() if content:IsVisible() then list:Refresh() end end)
    content:HookScript("OnShow", function() list:Refresh() end)
    return listTop + list:Refresh()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Quests:OnInitialize()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip) ns.Safe(OnUnitTooltip, tooltip) end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data) ns.Safe(OnObjectTooltip, tooltip, data) end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) ns.Safe(OnItemTooltip, tooltip) end)
    ns:On("QUESTS_UPDATED", function() Quests:RefreshMap() end)
end

function Quests:OnEnable()
    SetupMapLayer()
    self:RegisterEvent("ADDON_LOADED", function() SetupMapLayer() end)
    for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
        self:RegisterEvent(e, "QueueRebuild")
    end
    C_Timer.After(2, function() if self.enabled then ns.Safe(self.Rebuild, self) end end)
    if not miniTicker then miniTicker = C_Timer.NewTicker(0.15, function() ns.Safe(Quests.UpdateMinimap, Quests) end) end
end

function Quests:OnDisable()
    self:RefreshMap()
    self:UpdateMinimap()
end

function Quests:OnSettingChanged()
    if self.pinCache then wipe(self.pinCache) end
    self:RefreshMap()
    self:UpdateMinimap()
end
