-- Hawary's Addon: Journey & Guide engine (Zygor / RestedXP / Questie / NAG Journey style)
-- Two modes:
--   Auto Journey: a route built from YOUR quest log with Blizzard's own quest positions
--                 (turn-ins first, then the nearest objectives). No made-up data.
--   Guide:        step-by-step guides you import (docs/GUIDE-FORMAT.md).
-- Quest automation is optional, OFF by default, paused while Shift is held, never runs in
-- combat and never chooses between several rewards for you.
local _, ns = ...
local L, J = ns.L, ns.JourneyData

local Journey = ns:NewModule("journey", {
    title = L.MOD_JOURNEY,
    desc = L.MOD_JOURNEY_DESC,
    order = 0,
    defaults = {
        window = true, arrow = true, waypoint = true,
        autoAccept = false, autoTurnIn = false, skipTrivial = true,
        levelUp = true, lock = false, scale = 1,
        windowPos = {}, arrowPos = {},
    },
    charDefaults = { guide = "auto", step = 1, manual = {}, who = {} },
})

Journey.options = {
    { type = "dropdown", key = "guide", label = L.JOURNEY_MODE, desc = L.JOURNEY_MODE_DESC, values = function()
        local out = { { value = "auto", text = L.JOURNEY_AUTO } }
        for _, name in ipairs(ns.Util.sortedKeys(ns.db.guides)) do out[#out + 1] = { value = name, text = name } end
        local current = Journey:Get("guide")
        if current and current:find("^pack:") then out[#out + 1] = { value = current, text = Journey:GuideTitle(current) } end
        return out
    end },
    { type = "toggle", key = "window", label = L.JOURNEY_WINDOW, desc = L.JOURNEY_WINDOW_DESC },
    { type = "toggle", key = "arrow", label = L.JOURNEY_ARROW, desc = L.JOURNEY_ARROW_DESC },
    { type = "toggle", key = "waypoint", label = L.JOURNEY_WAYPOINT, desc = L.JOURNEY_WAYPOINT_DESC },
    { type = "toggle", key = "levelUp", label = L.JOURNEY_LEVELUP, desc = L.JOURNEY_LEVELUP_DESC },
    { type = "toggle", key = "lock", label = L.JOURNEY_LOCK, desc = L.JOURNEY_LOCK_DESC },
    { type = "slider", key = "scale", label = L.JOURNEY_SCALE, desc = L.JOURNEY_SCALE_DESC, min = 0.7, max = 1.5, step = 0.05,
      format = function(v) return string.format("%d%%", v * 100 + 0.5) end },
    { type = "header", label = L.JOURNEY_AUTOMATION },
    { type = "toggle", key = "autoAccept", label = L.JOURNEY_ACCEPT, desc = L.JOURNEY_ACCEPT_DESC },
    { type = "toggle", key = "autoTurnIn", label = L.JOURNEY_TURNIN, desc = L.JOURNEY_TURNIN_DESC },
    { type = "toggle", key = "skipTrivial", label = L.JOURNEY_TRIVIAL, desc = L.JOURNEY_TRIVIAL_DESC },
}

ns:RegisterStat("xph", L.HOME_SESSION, function()
    local s = Journey.enabled and Journey:SessionStats()
    return (s and s.elapsed >= 60) and J.Short(s.xph) or "–"
end, 40)

Journey.skipped = {}   -- Auto mode: quests the player skipped this session
local guideCache = {}

---------------------------------------------------------------------------
-- Guides library (account-wide text in ns.db.guides; progress per character)
---------------------------------------------------------------------------
-- Built-in leveling routes (HawarysAddon_Guides, from Polestar) are named "pack:<id>"
function Journey:LoadPacks()
    if not HawarysGuides and C_AddOns.DoesAddOnExist("HawarysAddon_Guides") then C_AddOns.LoadAddOn("HawarysAddon_Guides") end
    if HawarysGuides and not self.packIndex then
        self.packIndex = {}
        for _, e in ipairs(HawarysGuides.list) do self.packIndex[e.id] = e end
    end
    return HawarysGuides ~= nil
end

function Journey:PackInfo(name)
    local id = name and name:match("^pack:(.+)$")
    if not id or not self:LoadPacks() then return nil end
    return self.packIndex[id], id
end

function Journey:GuideTitle(name)
    local info = self:PackInfo(name)
    if info then return ("%s (%s)"):format(info.title or name, info.levels or "") end
    return name
end

function Journey:Who()
    local w = self:CharDB().who or {}
    local _, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    return { race = w.race or raceFile, class = w.class or classFile, faction = w.faction or UnitFactionGroup("player") }
end

function Journey:Guide(name)
    local text
    local _, packID = self:PackInfo(name)
    if packID then text = HawarysGuides.text[packID] else text = ns.db.guides[name] end
    if not text then return nil end
    local cached = guideCache[name]
    if cached and cached.text == text then return cached.guide end
    local guide = J.ParseGuide(text)
    guideCache[name] = { text = text, guide = guide }
    return guide
end

-- Returns name (or nil), errors, step count
function Journey:ImportGuide(text)
    local guide, errors = J.ParseGuide(text)
    if #guide.steps == 0 then return nil, errors end
    local name = guide.name
    ns.db.guides[name] = text
    guideCache[name] = nil
    return name, errors, #guide.steps
end

function Journey:DeleteGuide(name)
    ns.db.guides[name] = nil
    guideCache[name] = nil
    self:CharDB().manual[name] = nil
    if self:Get("guide") == name then self:Set("guide", "auto") end
end

-- Pick the route for a faction / race / class and jump to the first step you haven't done yet,
-- following the chain of zone guides (Zygor / RestedXP style).
function Journey:StartRoute(faction, race, class)
    if not self:LoadPacks() then ns:Print(L.JOURNEY_NO_PACKS); return end
    self:CharDB().who = { faction = faction, race = race, class = class }
    local start
    for _, e in ipairs(HawarysGuides.list) do
        if not e.category and e.faction == faction and e.race and e.race:lower() == (race or ""):lower() then
            if not start or e.id < start.id then start = e end
        end
    end
    if not start then ns:Print(L.JOURNEY_NO_ROUTE); return end
    local id, ctx = start.id, nil
    for _ = 1, 40 do
        local guide = J.ParseGuide(HawarysGuides.text[id])
        ctx = self:Ctx("pack:" .. id)
        if J.CurrentIndex(guide.steps, 1, ctx) <= #guide.steps then break end
        local nextID = self.packIndex[id] and self.packIndex[id].next
        if not (nextID and HawarysGuides.text[nextID]) then break end
        id = nextID
    end
    self.browsing = false
    self:CharDB().manual["pack:" .. id] = nil
    self:Set("guide", "pack:" .. id)
    ns:Print(L.JOURNEY_ROUTE_STARTED, self:GuideTitle("pack:" .. id))
end

function Journey:RestartGuide()
    local name = self:Get("guide")
    self:CharDB().manual[name] = nil
    self:CharDB().step = 1
    self.browsing = false
    self:Refresh()
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
local function World(mapID, x, y)
    if not (mapID and x and y) then return nil end
    local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not (continent and pos) then return nil end
    local wx, wy = pos:GetXY()
    return continent, wx, wy
end

function Journey:PlayerWorld()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local p = C_Map.GetPlayerMapPosition(map, "player")
    if not p then return nil end
    local px, py = p:GetXY()
    if not px or ns.IsSecret(px) then return nil end
    return World(map, px, py)
end

-- Returns yards, rotation (radians) to a target {mapID, x, y}, or nil
function Journey:DistanceTo(target)
    if not (target and target.x) then return nil end
    local c1, px, py = self:PlayerWorld()
    if not c1 then return nil end
    local c2, tx, ty = World(target.mapID, target.x, target.y)
    if c1 ~= c2 then return nil end
    local facing = GetPlayerFacing()
    if facing and ns.IsSecret(facing) then facing = nil end
    local rot, dist = J.Bearing(px, py, tx, ty, facing or 0)
    return dist, facing and rot or nil
end

-- Where a step happens: { mapID, x, y, quest } (x/y 0..1), or nil
function Journey:TargetFor(step)
    if not step then return nil end
    if step.x then
        return { mapID = step.map or C_Map.GetBestMapForUnit("player"), x = step.x / 100, y = step.y / 100 }
    end
    local id = step.questID
    if id and C_QuestLog.IsOnQuest(id) then
        local mapID, x, y = C_QuestLog.GetNextWaypoint(id)
        if mapID and x then return { mapID = mapID, x = x, y = y, quest = id } end
        local best = C_Map.GetBestMapForUnit("player")
        if best then
            for _, q in ipairs(C_QuestLog.GetQuestsOnMap(best) or {}) do
                if q.questID == id then return { mapID = best, x = q.x, y = q.y, quest = id } end
            end
        end
        local db = ns.QuestProvider and ns.QuestProvider.NearestFor(id)
        if db then return db end
        return { quest = id }
    end
    return nil
end

---------------------------------------------------------------------------
-- Quest log snapshot for Auto Journey
---------------------------------------------------------------------------
function Journey:Quests()
    local list = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
            local id = info.questID
            local complete = C_QuestLog.IsComplete(id) or C_QuestLog.ReadyForTurnIn(id) or false
            local objectives = {}
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
                if o.text and o.text ~= "" then objectives[#objectives + 1] = { text = o.text, finished = o.finished } end
            end
            local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(id)
            list[#list + 1] = {
                id = id, title = info.title, level = info.level, complete = complete,
                objectives = objectives, distSq = onContinent and distSq or nil, skipped = self.skipped[id],
            }
        end
    end
    return list
end

local function GuideObjectives(step)
    if not (step.questID and C_QuestLog.IsOnQuest(step.questID)) then return nil end
    local out = {}
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(step.questID) or {}) do
        if o.text and o.text ~= "" then out[#out + 1] = { text = o.text, finished = o.finished } end
    end
    return out
end

---------------------------------------------------------------------------
-- Building the view the window shows
---------------------------------------------------------------------------
function Journey:Ctx(guideName)
    local manual = self:CharDB().manual[guideName] or {}
    return {
        onQuest = function(id) return C_QuestLog.IsOnQuest(id) end,
        flagged = function(id) return C_QuestLog.IsQuestFlaggedCompleted(id) end,
        complete = function(id) return C_QuestLog.IsComplete(id) end,
        level = function() return UnitLevel("player") end,
        distance = function(step) return (self:DistanceTo(self:TargetFor(step))) end,
        manual = function(step) return manual[step.line] end,
        who = self:Who(),
        objectiveDone = function(q, i)
            local o = C_QuestLog.GetQuestObjectives(q)
            return o and o[i] and o[i].finished or false
        end,
        levelExact = function()
            local xp, mx = UnitXP("player"), UnitXPMax("player")
            if ns.IsSecret(xp) or ns.IsSecret(mx) or not mx or mx == 0 then return UnitLevel("player") end
            return UnitLevel("player") + xp / mx
        end,
        when = function(cond, arg)
            local neg = cond:sub(1, 1) == "!"
            local c = neg and cond:sub(2) or cond
            local id = tonumber(arg)
            local r = true
            if c == "complete" and id then r = C_QuestLog.IsQuestFlaggedCompleted(id) or (C_QuestLog.IsOnQuest(id) and C_QuestLog.IsComplete(id))
            elseif c == "onquest" and id then r = C_QuestLog.IsOnQuest(id)
            elseif c == "turnedin" and id then r = C_QuestLog.IsQuestFlaggedCompleted(id)
            elseif c == "zone" then r = GetZoneText() == arg end
            if neg then return not r end
            return r and true or false
        end,
    }
end

function Journey:Refresh()
    if not self.enabled then return end
    local mode = self:Get("guide")
    local guide = mode ~= "auto" and self:Guide(mode)
    local view = {}
    if guide then
        local ctx = self:Ctx(mode)
        local idx = self:Get("step")
        if not self.browsing then idx = J.CurrentIndex(guide.steps, idx, ctx) end
        self:CharDB().step = idx
        view.mode, view.title, view.index, view.total = "guide", guide.name, idx, #guide.steps
        view.steps = {}
        for i = idx, math.min(idx + 2, #guide.steps) do
            local s = guide.steps[i]
            s.objectives = GuideObjectives(s)
            s.done = J.IsDone(s, ctx)
            view.steps[#view.steps + 1] = s
        end
        view.finished = idx > #guide.steps
        local info = self:PackInfo(mode)
        if view.finished and info and info.next and HawarysGuides.text[info.next] and not self.chaining then
            self.chaining = true
            self:Set("guide", "pack:" .. info.next) -- on to the next zone of the route
            self.chaining = false
            return
        end
        view.title = self:GuideTitle(mode)
        view.progress = math.min(1, (idx - 1) / math.max(1, #guide.steps))
        view.progressText = L.JOURNEY_PROGRESS_STEP:format(math.min(idx, #guide.steps), #guide.steps)
    else
        local steps = J.AutoSteps(self:Quests(), UnitLevel("player"))
        -- Smart Route: nearby quests you can pick up (from the quest database)
        if ns.QuestProvider then
            for _, q in ipairs(ns.QuestProvider.NearbyAvailable(3)) do
                steps[#steps + 1] = { type = "accept", questID = q.questID, text = q.name, x = q.x * 100, y = q.y * 100,
                                      map = q.mapID, auto = true, giver = q.giver }
            end
        end
        view.mode, view.title = "auto", L.JOURNEY_AUTO
        view.steps = { steps[1], steps[2], steps[3] }
        view.empty = #steps == 0
        local xp, xpMax = UnitXP("player"), UnitXPMax("player")
        if ns.IsSecret(xp) or ns.IsSecret(xpMax) then xp, xpMax = 0, 1 end
        view.progress = xpMax > 0 and xp / xpMax or 0
        view.progressText = L.JOURNEY_PROGRESS_XP:format(UnitLevel("player"), J.XPPercent(xp, xpMax))
    end
    view.session = self:SessionStats()
    self.view = view
    self.current = view.steps[1]
    self.target = self:TargetFor(self.current)
    -- A quest clicked in the Hawary tracker takes over the arrow until it's done
    if self.focusQuest then
        if C_QuestLog.IsOnQuest(self.focusQuest) then
            self.target = self:TargetFor({ questID = self.focusQuest }) or self.target
        else
            self.focusQuest = nil
        end
    end
    self:UpdateWaypoint()
    ns:Fire("JOURNEY_UPDATED", view)
end

-- Throttled refresh for bursts of quest-log events
function Journey:QueueRefresh()
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0.25, function()
        self.refreshQueued = false
        ns.Safe(self.Refresh, self)
    end)
end

---------------------------------------------------------------------------
-- Session stats (XP/hour, time to level, gold/hour, quests turned in)
---------------------------------------------------------------------------
local session = { start = nil, xp = 0, gold = 0, quests = 0, lastXP = nil, lastXPMax = nil, lastMoney = nil }

function Journey:TrackXP()
    local xp, xpMax = UnitXP("player"), UnitXPMax("player")
    if ns.IsSecret(xp) or ns.IsSecret(xpMax) then return end
    if session.lastXP then
        local gained = xp - session.lastXP
        if gained < 0 then gained = (session.lastXPMax or 0) - session.lastXP + xp end -- level up
        if gained > 0 then session.xp = session.xp + gained end
    end
    session.lastXP, session.lastXPMax = xp, xpMax
end

function Journey:TrackMoney()
    local money = GetMoney()
    if session.lastMoney and money > session.lastMoney then session.gold = session.gold + (money - session.lastMoney) end
    session.lastMoney = money
end

function Journey:SessionStats()
    if not session.start then return nil end
    local xp, xpMax = UnitXP("player"), UnitXPMax("player")
    local left = (not ns.IsSecret(xp) and not ns.IsSecret(xpMax)) and (xpMax - xp) or nil
    local elapsed = GetTime() - session.start
    local xph, ttl, gph = J.SessionRates(elapsed, session.xp, left, session.gold)
    return { elapsed = elapsed, xph = xph, ttl = ttl, gph = gph, quests = session.quests, xp = session.xp, gold = session.gold }
end

function Journey:StartSession()
    session.start = GetTime()
    session.xp, session.gold, session.quests = 0, 0, 0
    session.lastXP, session.lastXPMax, session.lastMoney = nil, nil, nil
    self:TrackXP()
    self:TrackMoney()
end

---------------------------------------------------------------------------
-- Navigation buttons
---------------------------------------------------------------------------
function Journey:Next()
    local view = self.view
    if not view then return end
    if view.mode == "auto" then
        local s = self.current
        if s and s.questID then self.skipped[s.questID] = true end
    else
        local mode = self:Get("guide")
        local s = self.current
        if s and not s.done then
            local manual = self:CharDB().manual
            manual[mode] = manual[mode] or {}
            manual[mode][s.line] = true
        end
        self.browsing = false
        self:CharDB().step = (view.index or 1) + 1
    end
    self:Refresh()
end

function Journey:Back()
    local view = self.view
    if not view then return end
    if view.mode == "auto" then
        wipe(self.skipped)
    else
        local idx = math.max(1, (view.index or 1) - 1)
        local mode = self:Get("guide")
        local guide = self:Guide(mode)
        local manual = self:CharDB().manual[mode]
        if manual and guide and guide.steps[idx] then manual[guide.steps[idx].line] = nil end
        self.browsing = true
        self:CharDB().step = idx
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- Blizzard's own map pin / in-world marker for the current step
---------------------------------------------------------------------------
function Journey:ClearOwnWaypoint()
    if self.ownWaypoint then
        self.ownWaypoint = false
        ns:RunOutOfCombat("journey-waypoint", function() C_Map.ClearUserWaypoint() end)
    end
    self.lastWaypoint = nil
end

function Journey:UpdateWaypoint()
    if not (self.enabled and self:Get("waypoint")) then return end
    local t = self.target
    local key = t and table.concat({ tostring(t.quest), tostring(t.mapID), tostring(t.x), tostring(t.y) }, ":") or "none"
    if key == self.lastWaypoint then return end
    self.lastWaypoint = key
    ns:RunOutOfCombat("journey-waypoint", function()
        if t and t.quest and C_QuestLog.IsOnQuest(t.quest) then
            C_SuperTrack.SetSuperTrackedQuestID(t.quest)
        elseif t and t.x and t.mapID and C_Map.CanSetUserWaypointOnMap(t.mapID) then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(t.mapID, t.x, t.y))
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            self.ownWaypoint = true
        end
    end)
end

---------------------------------------------------------------------------
-- Quest automation (optional, off by default). Only after YOU open the NPC/quest,
-- never in combat, Shift pauses it, never picks between several rewards.
---------------------------------------------------------------------------
local function Paused()
    return IsShiftKeyDown() or ns.InCombat()
end

function Journey:OnQuestDetail()
    if not self:Get("autoAccept") or Paused() then return end
    if QuestGetAutoAccept() then
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end
end

function Journey:OnQuestProgress()
    if not self:Get("autoTurnIn") or Paused() then return end
    if GetQuestMoneyToGet() > 0 then return end -- costs gold: let the player decide
    if IsQuestCompletable() then CompleteQuest() end
end

function Journey:OnQuestComplete()
    if not self:Get("autoTurnIn") or Paused() then return end
    local choices = GetNumQuestChoices()
    if choices > 1 then return end -- the player chooses; Gear marks the best one
    GetQuestReward(choices) -- 0 = no choice, 1 = the only choice (same as Blizzard's button)
end

function Journey:OnGossip()
    if Paused() then return end
    if self:Get("autoTurnIn") then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID); return end
        end
    end
    if self:Get("autoAccept") then
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if not (self:Get("skipTrivial") and q.isTrivial) and not q.repeatable then
                C_GossipInfo.SelectAvailableQuest(q.questID)
                return
            end
        end
    end
end

function Journey:OnQuestGreeting()
    if Paused() then return end
    if self:Get("autoTurnIn") then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then SelectActiveQuest(i); return end
        end
    end
    if self:Get("autoAccept") then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial, _, isRepeatable = GetAvailableQuestInfo(i)
            if not (self:Get("skipTrivial") and isTrivial) and not isRepeatable then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Journey:OnEnable()
    self:RegisterEvent("QUEST_LOG_UPDATE", "QueueRefresh")
    self:RegisterEvent("QUEST_ACCEPTED", "QueueRefresh")
    self:RegisterEvent("QUEST_TURNED_IN", function()
        session.quests = session.quests + 1
        self:QueueRefresh()
    end)
    self:RegisterEvent("QUEST_REMOVED", "QueueRefresh")
    self:RegisterEvent("PLAYER_XP_UPDATE", function(_, _, unit)
        if unit == "player" then self:TrackXP(); self:QueueRefresh() end
    end)
    self:RegisterEvent("PLAYER_MONEY", "TrackMoney")
    if not session.start then self:StartSession() end
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "QueueRefresh")
    self:RegisterEvent("PLAYER_LEVEL_UP", function(_, _, level)
        self:QueueRefresh()
        if self:Get("levelUp") then
            ns:Toast(L.JOURNEY_LEVELUP_TOAST:format(level or UnitLevel("player")), L.JOURNEY_LEVELUP_TEXT, "star")
        end
    end)
    self:RegisterEvent("QUEST_DETAIL", "OnQuestDetail")
    self:RegisterEvent("QUEST_PROGRESS", "OnQuestProgress")
    self:RegisterEvent("QUEST_COMPLETE", "OnQuestComplete")
    self:RegisterEvent("GOSSIP_SHOW", "OnGossip")
    self:RegisterEvent("QUEST_GREETING", "OnQuestGreeting")
    C_Timer.After(1, function() ns.Safe(self.Refresh, self) end)
    if not self.questHook then
        self.questHook = true
        ns:On("QUESTS_UPDATED", function() if Journey.enabled then Journey:QueueRefresh() end end)
    end
    ns:Fire("JOURNEY_ENABLED", true)
end

function Journey:OnDisable()
    self:ClearOwnWaypoint()
    ns:Fire("JOURNEY_ENABLED", false)
end

function Journey:OnSettingChanged(key)
    if key == "guide" then
        self.browsing = false
        self:CharDB().step = 1
        self:Refresh()
    elseif key == "waypoint" then
        if self:Get("waypoint") then self.lastWaypoint = nil; self:UpdateWaypoint() else self:ClearOwnWaypoint() end
    end
    ns:Fire("JOURNEY_SETTINGS", key)
end
