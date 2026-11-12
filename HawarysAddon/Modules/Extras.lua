-- Hawary's Addon: Extras – quest-done alert, level-up summary, session report,
-- settings export/import and bag sort. All read-only or a single Blizzard action on your click.
local _, ns = ...
local L, U, W = ns.L, ns.Util, ns.W

local X = ns:NewModule("extras", {
    title = L.MOD_EXTRAS,
    desc = L.MOD_EXTRAS_DESC,
    order = 13,
    defaults = { questDone = true, levelSummary = true },
    charDefaults = { levelStart = 0, levelQuests = 0, levelQuestXP = 0 },
})

X.options = {
    { type = "toggle", key = "questDone", label = L.EXTRA_QUESTDONE, desc = L.EXTRA_QUESTDONE_DESC },
    { type = "toggle", key = "levelSummary", label = L.EXTRA_LEVELSUM, desc = L.EXTRA_LEVELSUM_DESC },
    { type = "button", label = L.EXTRA_SORT, desc = L.EXTRA_SORT_DESC, buttonText = L.EXTRA_SORT_BTN, onClick = function() X:SortBags() end },
    { type = "button", label = L.EXTRA_EXPORT, desc = L.EXTRA_EXPORT_DESC, buttonText = L.EXPORT, onClick = function() X:Export() end },
    { type = "button", label = L.EXTRA_IMPORT, desc = L.EXTRA_IMPORT_DESC, buttonText = L.IMPORT, onClick = function() X:Import() end },
}

-- Quest-done alert: a notice the moment every objective of a quest is finished
local done = {}
function X:ScanDone(initial)
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            local id = info.questID
            local complete = C_QuestLog.IsComplete(id) and true or false
            if complete and not done[id] and not initial and self:Get("questDone") then
                ns:Toast(L.EXTRA_QUESTDONE_TOAST, info.title or "", "quest_done")
            end
            done[id] = complete
        end
    end
end

-- Level-up summary: time on the level, quests turned in and quest XP
function X:OnLevel(_, level)
    local db = self:CharDB()
    if self:Get("levelSummary") and db.levelStart > 0 then
        local text = L.EXTRA_LEVELSUM_TEXT:format(level or UnitLevel("player"), ns.JourneyData.FormatDuration(time() - db.levelStart),
            db.levelQuests, ns.JourneyData.Short(db.levelQuestXP))
        ns:Print(text)
        ns:Toast(L.EXTRA_LEVELSUM, text, "star")
    end
    db.levelStart, db.levelQuests, db.levelQuestXP = time(), 0, 0
end

-- /ha session
function X:SessionReport()
    local j = ns.modules.journey
    local s = j and j:SessionStats()
    if not s then ns:Print(L.EXTRA_NO_SESSION); return end
    ns:Print(L.EXTRA_SESSION:format(ns.JourneyData.FormatDuration(s.elapsed), ns.JourneyData.Short(s.xp), ns.JourneyData.Short(s.xph),
        U.money(s.gold), U.money(s.gph), s.quests, ns.JourneyData.FormatDuration(s.ttl)))
end

-- Bag sort: Blizzard's own sort (the same as its sort button), out of combat
function X:SortBags()
    if ns.InCombat() then ns:Print(L.NOT_IN_COMBAT); return end
    C_Container.SortBags()
    ns:Print(L.EXTRA_SORTED)
end

-- Settings export / import (a shareable code; only settings, never character data)
local PREFIX = "HAWARY1:"
function X:Export()
    local data = { general = {}, modules = {} }
    for k, v in pairs(ns.db.general) do
        if k ~= "window" and k ~= "lastPage" then data.general[k] = U.copy(v) end
    end
    for id, settings in pairs(ns.db.modules) do
        data.modules[id] = {}
        for k, v in pairs(settings) do
            if type(v) ~= "table" then data.modules[id][k] = v end
        end
    end
    W.TextDialog(L.EXTRA_EXPORT_PROMPT, PREFIX .. U.base64encode(U.serialize(data)), true)
end

function X.Decode(text)
    text = U.trim(text or "")
    if text:sub(1, #PREFIX) ~= PREFIX then return nil end
    local raw = U.base64decode(text:sub(#PREFIX + 1))
    local data = raw and U.deserialize(raw)
    if type(data) ~= "table" or type(data.modules) ~= "table" then return nil end
    return data
end

function X:Apply(data)
    for k, v in pairs(data.general or {}) do
        if ns.defaults.general[k] ~= nil and type(v) == type(ns.defaults.general[k]) then ns.db.general[k] = v end
    end
    for id, settings in pairs(data.modules) do
        local target = ns.db.modules[id]
        if target then
            for k, v in pairs(settings) do
                if target[k] ~= nil and type(target[k]) == type(v) then target[k] = v end
            end
        end
    end
end

function X:Import()
    W.TextDialog(L.EXTRA_IMPORT_PROMPT, "", false, function(text)
        local data = X.Decode(text)
        if not data then ns:Print(L.EXTRA_IMPORT_BAD); return end
        X:Apply(data)
        StaticPopup_Show("HAWARYS_ADDON_RELOAD")
    end)
end

function X:OnEnable()
    self:RegisterEvent("QUEST_LOG_UPDATE", function() ns.Safe(X.ScanDone, X, false) end)
    self:RegisterEvent("PLAYER_LEVEL_UP", "OnLevel")
    self:RegisterEvent("QUEST_TURNED_IN", function(_, _, _, xp)
        local db = X:CharDB()
        db.levelQuests = db.levelQuests + 1
        db.levelQuestXP = db.levelQuestXP + (tonumber(xp) or 0)
    end)
    if self:CharDB().levelStart == 0 then self:CharDB().levelStart = time() end
    C_Timer.After(2, function() ns.Safe(X.ScanDone, X, true) end)
end

ns:On("EXTRAS_SESSION", function() X:SessionReport() end)
ns:On("EXTRAS_SORT", function() X:SortBags() end)
