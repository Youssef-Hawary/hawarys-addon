-- Hawary's Addon: Quest Tracker+ – a compact tracker with the distance to each quest,
-- party members on the same quest and click-to-arrow, plus quest icons over NPC
-- nameplates (Questie-style). Display only: it never acts for you.
local _, ns = ...
local L, T, W = ns.L, ns.Theme, ns.W

local Tracker = ns:NewModule("tracker", {
    title = L.MOD_TRACKER,
    desc = L.MOD_TRACKER_DESC,
    order = 14,
    defaults = { show = true, party = true, nameplates = true, rows = 8, point = false },
})

Tracker.options = {
    { type = "toggle", key = "show", label = L.TRACKER_SHOW, desc = L.TRACKER_SHOW_DESC },
    { type = "toggle", key = "party", label = L.TRACKER_PARTY, desc = L.TRACKER_PARTY_DESC },
    { type = "toggle", key = "nameplates", label = L.TRACKER_PLATES, desc = L.TRACKER_PLATES_DESC },
    { type = "slider", key = "rows", label = L.TRACKER_ROWS, desc = L.TRACKER_ROWS_DESC, min = 3, max = 15, step = 1 },
}

---------------------------------------------------------------------------
-- Data (pure parts are unit-tested)
---------------------------------------------------------------------------
function Tracker.Yards(distSq)
    if not distSq or ns.IsSecret(distSq) or distSq <= 0 then return nil end
    return math.floor(math.sqrt(distSq) + 0.5)
end

function Tracker.FormatYards(y)
    if not y then return "" end
    if y >= 1000 then return string.format("%.1fk yd", y / 1000) end
    return y .. " yd"
end

-- Party members (names) who are on questID
function Tracker:PartyOn(questID)
    local out = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local ok, on = pcall(C_QuestLog.IsUnitOnQuest, unit, questID)
            if ok and on and not ns.IsSecret(on) then
                local name = UnitName(unit)
                if name and not ns.IsSecret(name) then out[#out + 1] = name end
            end
        end
    end
    return out
end

-- Watched quests first (Blizzard's tracked list), else the whole log; nearest first
function Tracker:List()
    local ids, seen = {}, {}
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if id and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
    end
    if #ids == 0 then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 and not seen[info.questID] then
                ids[#ids + 1] = info.questID; seen[info.questID] = true
            end
        end
    end
    local rows = {}
    for _, id in ipairs(ids) do
        local yards = Tracker.Yards((C_QuestLog.GetDistanceSqToQuest(id)))
        local done = C_QuestLog.IsComplete(id) or C_QuestLog.ReadyForTurnIn(id)
        rows[#rows + 1] = { id = id, title = C_QuestLog.GetTitleForQuestID(id) or ("#" .. id), yards = yards, done = done,
                            party = self:Get("party") and self:PartyOn(id) or {} }
    end
    table.sort(rows, function(a, b)
        if (a.yards ~= nil) ~= (b.yards ~= nil) then return a.yards ~= nil end
        return (a.yards or 0) < (b.yards or 0)
    end)
    return rows
end

-- Click: Blizzard's own super-track + the Hawary arrow follows it
function Tracker:Focus(questID)
    ns:RunOutOfCombat("tracker-focus", function() C_SuperTrack.SetSuperTrackedQuestID(questID) end)
    local j = ns.modules.journey
    if j and j.enabled then
        j.focusQuest = questID
        j:Refresh()
    end
    ns:Print(L.TRACKER_FOCUS, C_QuestLog.GetTitleForQuestID(questID) or questID)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local frame, rowFrames = nil, {}

local function Build()
    frame = CreateFrame("Frame", "HawarysQuestTracker", UIParent)
    frame:SetSize(250, 40)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, rel, x, y = f:GetPoint()
        Tracker:Set("point", { point, rel, x, y })
    end)
    local p = Tracker:Get("point")
    if type(p) == "table" and p[1] then
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    frame.bg = T.Shape(frame, "round", T.native() and { 0, 0, 0, 0.55 } or "window", "BACKGROUND")
    frame.title = W.Label(frame, L.TRACKER_TITLE, "h2", "accent")
    frame.title:SetPoint("TOPLEFT", 12, -9)
    frame.mark = W.Icon(frame, "mark", 14)
    frame.mark:SetPoint("TOPRIGHT", -10, -8)
end

local function Row(i)
    local r = rowFrames[i]
    if r then return r end
    r = CreateFrame("Button", nil, frame)
    r:SetHeight(30)
    r:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 31)
    r:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    r.bg = T.Shape(r, "round_sm", { 0, 0, 0, 0 }, "BACKGROUND")
    r.name = W.Label(r, "", "body", "text")
    r.name:SetPoint("TOPLEFT", 6, -2)
    r.name:SetPoint("RIGHT", r, "RIGHT", -60, 0)
    r.name:SetWordWrap(false)
    r.dist = W.Label(r, "", "small", "accent", "RIGHT")
    r.dist:SetPoint("TOPRIGHT", -6, -3)
    r.sub = W.Label(r, "", "small", "text3")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.sub:SetWordWrap(false)
    r:SetScript("OnEnter", function(self) T.Tint(self.bg, "hover") end)
    r:SetScript("OnLeave", function(self) T.Tint(self.bg, { 0, 0, 0, 0 }) end)
    r:SetScript("OnClick", function(self) if self.questID then Tracker:Focus(self.questID) end end)
    T.Focusable(r)
    rowFrames[i] = r
    return r
end

function Tracker:Update()
    if not frame then return end
    local show = self.enabled and self:Get("show") and not self.hidden
    frame:SetShown(show)
    if not show then return end
    local rows = self:List()
    local max = math.min(#rows, self:Get("rows"))
    for i = 1, max do
        local r, q = Row(i), rows[i]
        r.questID = q.id
        r.name:SetText(q.title)
        T.TextColor(r.name, q.done and "good" or "text")
        r.dist:SetText(Tracker.FormatYards(q.yards))
        local sub = q.done and L.TRACKER_DONE or ""
        if #q.party > 0 then sub = (sub ~= "" and sub .. " · " or "") .. L.TRACKER_WITH:format(table.concat(q.party, ", ")) end
        r.sub:SetText(sub)
        r:Show()
    end
    for i = max + 1, #rowFrames do rowFrames[i]:Hide() end
    frame:SetHeight(36 + math.max(max, 1) * 31)
    frame.title:SetText(max == 0 and L.TRACKER_EMPTY or L.TRACKER_TITLE)
end

---------------------------------------------------------------------------
-- Nameplate quest icons: "!" quest to pick up, "?" turn in, * needed for a quest.
-- Uses the quest database (Quests module). Skipped when the game hides the unit's
-- identity (secret values, e.g. in instances).
---------------------------------------------------------------------------
local npcKind = {}
local plateIcons = {}

function Tracker:BuildNpcIndex()
    wipe(npcKind)
    local Q = ns.modules.quests
    if not (Q and Q.enabled and Q.available and Q.ctx) then return end
    local F = ns.QuestLogic.FIELDS
    for id, status in pairs(Q.available) do
        if status == "available" then
            for _, npcID in ipairs((Q:Data("quest", id, "startedBy") or {})[1] or {}) do npcKind[npcID] = npcKind[npcID] or "starts" end
        end
    end
    for id in pairs(Q.ctx.active) do
        local quest = Q:Row("quest", id)
        if quest then
            if Q.ctx.complete[id] then
                for _, npcID in ipairs((quest[F.quest.finishedBy] or {})[1] or {}) do npcKind[npcID] = "turnin" end
            else
                local obj = quest[F.quest.objectives] or {}
                for _, o in ipairs(obj[1] or {}) do npcKind[o[1]] = npcKind[o[1]] or "objective" end
                for _, o in ipairs(obj[3] or {}) do
                    for _, npcID in ipairs(Q:Data("item", o[1], "npcDrops") or {}) do npcKind[npcID] = npcKind[npcID] or "objective" end
                end
            end
        end
    end
end

function Tracker.NpcIDFromGUID(guid)
    if not guid or ns.IsSecret(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

local ICON = { starts = { "!", "warn" }, turnin = { "?", "warn" }, objective = { "*", "accent" } }

function Tracker:OnPlateAdded(_, unit)
    if not self:Get("nameplates") then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
    if not plate then return end
    local npcID = Tracker.NpcIDFromGUID(UnitGUID(unit))
    local kind = npcID and npcKind[npcID]
    local icon = plateIcons[plate]
    if not kind then
        if icon then icon:Hide() end
        return
    end
    if not icon then
        icon = CreateFrame("Frame", nil, plate)
        icon:SetSize(20, 20)
        icon:SetPoint("BOTTOM", plate, "TOP", 0, 2)
        icon.text = W.Label(icon, "", "number", "warn", "CENTER")
        icon.text:SetPoint("CENTER")
        plateIcons[plate] = icon
    end
    icon.text:SetText(ICON[kind][1])
    T.TextColor(icon.text, ICON[kind][2])
    icon:Show()
end

function Tracker:OnPlateRemoved(_, unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
    if plate and plateIcons[plate] then plateIcons[plate]:Hide() end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Tracker:OnEnable()
    if not frame then Build() end
    local refresh = function() Tracker:Update() end
    self:RegisterEvent("QUEST_LOG_UPDATE", refresh)
    self:RegisterEvent("QUEST_WATCH_LIST_CHANGED", refresh)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", refresh)
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnPlateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnPlateRemoved")
    self.ticker = C_Timer.NewTicker(1, function() if frame and frame:IsShown() then ns.Safe(Tracker.Update, Tracker) end end)
    self:BuildNpcIndex()
    self:Update()
end

function Tracker:OnDisable()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if frame then frame:Hide() end
    for _, icon in pairs(plateIcons) do icon:Hide() end
end

function Tracker:OnSettingChanged() self:Update() end

ns:On("QUESTS_UPDATED", function() if Tracker.enabled then Tracker:BuildNpcIndex() end end)
ns:On("TRACKER_TOGGLE", function()
    Tracker.hidden = not Tracker.hidden
    Tracker:Update()
end)
