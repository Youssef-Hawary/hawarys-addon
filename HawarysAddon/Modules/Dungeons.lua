-- Hawary's Addon: Dungeons – Adventure Planner (from Blizzard's own Group Finder list:
-- names, minimum and suggested levels) and a personal dungeon log (runs, time, bosses).
-- Read-only; no made-up dungeon data.
local _, ns = ...
local L, T, W, A, J = ns.L, ns.Theme, ns.W, ns.AdventureData, ns.JourneyData

local Dungeons = ns:NewModule("dungeons", {
    title = L.MOD_DUNGEONS,
    desc = L.MOD_DUNGEONS_DESC,
    order = 7,
    defaults = { showDone = false },
    charDefaults = { stats = {}, runs = {} },
})

Dungeons.options = {
    { type = "toggle", key = "showDone", label = L.DUNGEONS_SHOWDONE, desc = L.DUNGEONS_SHOWDONE_DESC },
}

---------------------------------------------------------------------------
-- Blizzard's group-finder activities (the same list Forever's Group Finder uses)
---------------------------------------------------------------------------
function Dungeons:Activities()
    if self.activities then return self.activities end
    local list, seen = {}, {}
    if not (C_LFGList and C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableActivities) then return list end
    for _, catID in ipairs(C_LFGList.GetAvailableCategories() or {}) do
        local cat = C_LFGList.GetLfgCategoryInfo(catID)
        for _, actID in ipairs(C_LFGList.GetAvailableActivities(catID) or {}) do
            local a = C_LFGList.GetActivityInfoTable(actID)
            if a and not a.isPvpActivity and a.fullName and not seen[a.fullName]
                and ((a.minLevelSuggestion or 0) > 0 or (a.minLevel or 0) > 0) then
                seen[a.fullName] = true
                list[#list + 1] = {
                    id = actID, name = a.fullName, minLevel = a.minLevel, minSugg = a.minLevelSuggestion,
                    maxSugg = a.maxLevelSuggestion, players = a.maxNumPlayers, category = cat and cat.name or "",
                }
            end
        end
    end
    if #list > 0 then self.activities = list end
    return list
end

function Dungeons:Planner()
    return A.Classify(self:Activities(), UnitLevel("player"))
end

-- First group activity that fits your level now and that you haven't run yet ("What now?")
function Dungeons:Suggestion()
    local now = self:Planner()
    local stats = self:Get("stats")
    for _, a in ipairs(now) do
        if (a.players or 0) >= 5 and not stats[a.name] then return a end
    end
    return nil
end

---------------------------------------------------------------------------
-- Dungeon log
---------------------------------------------------------------------------
function Dungeons:CheckInstance()
    local name, instanceType = GetInstanceInfo()
    if ns.IsSecret(name) then return end
    local inDungeon = instanceType == "party" or instanceType == "raid"
    if inDungeon and not self.run then
        self.run = { name = name, start = time(), bosses = 0, level = UnitLevel("player") }
        ns:Fire("DUNGEON_UPDATED")
    elseif not inDungeon and self.run then
        local run = self.run
        self.run = nil
        run.finish = time()
        run.duration = run.finish - run.start
        if run.duration >= 60 then
            local runs = self:Get("runs")
            runs[#runs + 1] = run
            A.Trim(runs, 100)
            A.AddRun(self:Get("stats"), run)
            if run.bosses > 0 then ns:Fire("MILESTONE", "dungeon", run) end
        end
        ns:Fire("DUNGEON_UPDATED")
    end
end

function Dungeons:OnEncounterEnd(_, _, _, _, _, success)
    if self.run and success == 1 then
        self.run.bosses = self.run.bosses + 1
        ns:Fire("DUNGEON_UPDATED")
    end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Dungeons:BuildPage(content, width, y)
    y = ns:BuildOptions(self, content, width, y)
    local top = y
    local holder = CreateFrame("Frame", nil, content)
    holder:SetPoint("TOPLEFT", 0, top)
    holder:SetWidth(width)
    holder.rows, holder.labels = {}, {}

    local function Label(i, text, fontKey, color)
        local fs = holder.labels[i]
        if not fs then
            fs = W.Label(holder, "", fontKey, color)
            holder.labels[i] = fs
        end
        fs:SetFontObject(T.font(fontKey))
        T.TextColor(fs, color)
        fs:SetText(text)
        fs:Show()
        return fs
    end

    local function Row(i)
        local row = holder.rows[i]
        if not row then
            row = W.Card(holder)
            row:SetHeight(40)
            row.name = W.Label(row, "", "body", "text")
            row.name:SetPoint("TOPLEFT", 14, -7)
            row.info = W.Label(row, "", "small", "text3")
            row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
            row.range = W.Tag(row, "", "accent")
            row.range:SetPoint("RIGHT", -12, 0)
            row.mine = W.Label(row, "", "small", "text2", "RIGHT")
            row.mine:SetPoint("RIGHT", row.range, "LEFT", -12, 0)
            holder.rows[i] = row
        end
        return row
    end

    function holder:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        for _, l in ipairs(self.labels) do l:Hide() end
        local stats = Dungeons:Get("stats")
        local hy, li, ri = 0, 0, 0

        if Dungeons.run then
            li = li + 1
            local fs = Label(li, L.DUNGEONS_CURRENT:format(Dungeons.run.name, J.FormatDuration(time() - Dungeons.run.start), Dungeons.run.bosses), "h2", "accent")
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 0, hy)
            hy = hy - 28
        end

        local now, soon, done = Dungeons:Planner()
        local groups = { { L.DUNGEONS_NOW, now }, { L.DUNGEONS_SOON, soon } }
        if Dungeons:Get("showDone") then groups[#groups + 1] = { L.DUNGEONS_DONE, done } end
        if #Dungeons:Activities() == 0 then
            li = li + 1
            local fs = Label(li, L.DUNGEONS_NO_DATA, "small", "text3")
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 0, hy)
            fs:SetWidth(width)
            fs:SetWordWrap(true)
            hy = hy - fs:GetStringHeight() - 16
        end
        for _, g in ipairs(groups) do
            if #g[2] > 0 then
                li = li + 1
                local h = Label(li, g[1], "h2", "accent")
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 0, hy)
                hy = hy - 24
                for _, a in ipairs(g[2]) do
                    ri = ri + 1
                    local row = Row(ri)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, hy)
                    row:SetWidth(width)
                    row.name:SetText(a.name)
                    row.info:SetText(a.category or "")
                    row.range.text:SetText(L.DUNGEONS_LEVELS:format(A.LevelRange(a)))
                    row.range:SetWidth(row.range.text:GetStringWidth() + 16)
                    local s = stats[a.name]
                    row.mine:SetText(s and L.DUNGEONS_MINE:format(s.runs, s.best and J.FormatDuration(s.best) or "–") or "")
                    row:Show()
                    hy = hy - 46
                end
                hy = hy - 6
            end
        end

        local runs = Dungeons:Get("runs")
        if #runs > 0 then
            li = li + 1
            local h = Label(li, L.DUNGEONS_RECENT, "h2", "accent")
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, hy)
            hy = hy - 24
            for i = #runs, math.max(1, #runs - 7), -1 do
                local r = runs[i]
                li = li + 1
                local fs = Label(li, L.DUNGEONS_RUN:format(date("%b %d", r.finish), r.name, J.FormatDuration(r.duration), r.bosses, r.level or 0), "small", "text2")
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", 4, hy)
                hy = hy - 18
            end
        end
        self:SetHeight(math.max(1, -hy))
        content:SetHeight(-top - hy + 20)
        return hy
    end

    local function maybe() if content:IsVisible() then holder:Refresh() end end
    ns:On("DUNGEON_UPDATED", maybe)
    ns:On("SETTING_CHANGED", function(id) if id == "dungeons" then maybe() end end)
    content:HookScript("OnShow", function() holder:Refresh() end)
    return top + holder:Refresh()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Dungeons:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckInstance")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckInstance")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterEvent("PLAYER_LEVEL_UP", function() self.activities = nil end)
    C_Timer.After(2, function() if self.enabled then ns.Safe(self.CheckInstance, self) end end)
end
