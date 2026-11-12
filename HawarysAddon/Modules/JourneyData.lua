-- Hawary's Addon: Journey logic – guide format parser, step completion, Auto Journey
-- ordering and arrow math. No WoW API here, so it is unit-tested.
--
-- Guide format (one step per line; # starts a comment; see docs/GUIDE-FORMAT.md):
--   guide: Elwynn Forest 1-10        name of the guide
--   level: 1-10                      level range (optional)
--   map: 1429                        default uiMapID for coordinates (optional)
--   accept 783 A Threat Within @ 48.2 42.9
--   complete 783 Kill kobolds
--   turnin 783
--   goto 52.1 45.0 Northshire Abbey [map=1429]
--   level 6 Grind to level 6
--   train | hearth Goldshire | fly Stormwind | note Any text
local _, ns = ...

local J = {}
ns.JourneyData = J

J.TYPES = { accept = true, complete = true, turnin = true, ["goto"] = true, level = true, train = true, hearth = true, fly = true, note = true, objective = true, getfp = true, vendor = true }
J.QUEST_TYPES = { accept = true, complete = true, turnin = true }
J.ARRIVE_YARDS = 12

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Pull "@ x y" / "@ x,y" and "map=123" out of a line; returns rest, x, y, map
local function extractCoords(rest)
    local map
    rest = rest:gsub("%s*map%s*=%s*(%d+)", function(m) map = tonumber(m); return "" end)
    local x, y
    rest = rest:gsub("%s*@%s*([%d%.]+)%s*[,%s]%s*([%d%.]+)", function(a, b) x, y = tonumber(a), tonumber(b); return "" end)
    return trim(rest), x, y, map
end

-- Returns guide, errors (list of "line N: message")
function J.ParseGuide(text)
    local guide = { name = "Guide", steps = {} }
    local errors = {}
    local n = 0
    for raw in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        n = n + 1
        local line = trim(raw)
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^(%a+)%s*:%s*(.*)$")
            local word0, after0 = line:match("^(%a+)%s*(.*)$")
            if word0 == "section" then
                guide.section = after0
                key = nil
            elseif word0 == "tip" then
                guide.tip = after0
                key = nil
            end
            if not key and (word0 == "section" or word0 == "tip") then
                -- handled above
            elseif key and (key == "guide" or key == "level" or key == "map" or key == "id") then
                if key == "id" then
                    guide.id = value
                elseif key == "guide" then
                    guide.name = trim(value)
                elseif key == "level" then
                    local a, b = value:match("(%d+)%s*%-%s*(%d+)")
                    guide.minLevel, guide.maxLevel = tonumber(a), tonumber(b)
                else
                    guide.map = tonumber(value)
                end
            else
                local word, rest = line:match("^(%a+)%s*(.*)$")
                word = word and word:lower()
                if not word or not J.TYPES[word] then
                    errors[#errors + 1] = ("line %d: unknown step '%s'"):format(n, word or line)
                else
                    local step = { type = word, line = n, section = guide.section, tip = guide.tip }
                    guide.tip = nil
                    rest = rest or ""
                    local wcond, warg
                    rest = rest:gsub("%s+when%s+(!?%a+)%s*(.-)%s*$", function(c, a) wcond, warg = c, a; return "" end)
                    if wcond then step.when = { wcond, (warg:gsub('"', '')) } end
                    rest = rest:gsub("%s+only%s+(!?[%a,!]+)%s*$", function(o) step.only = o; return "" end)
                    rest, step.x, step.y, step.map = extractCoords(rest)
                    if J.QUEST_TYPES[word] then
                        local id, title = rest:match("^(%d+)%s*(.*)$")
                        if not id then
                            errors[#errors + 1] = ("line %d: '%s' needs a quest ID"):format(n, word)
                            step = nil
                        else
                            step.questID = tonumber(id)
                            step.text = trim(title)
                        end
                    elseif word == "goto" then
                        local gx, gy, label = rest:match("^([%d%.]+)%s*[,%s]%s*([%d%.]+)%s*(.*)$")
                        if gx then
                            step.x, step.y = tonumber(gx), tonumber(gy)
                            step.text = trim(label)
                        end
                        if not step.x then
                            errors[#errors + 1] = ("line %d: 'goto' needs coordinates"):format(n)
                            step = nil
                        end
                    elseif word == "objective" then
                        local q, o, verb = rest:match("^(%d+)%.(%d+)%s*(.*)$")
                        if not q then
                            errors[#errors + 1] = ("line %d: 'objective' needs quest.index"):format(n)
                            step = nil
                        else
                            step.questID, step.obj, step.text = tonumber(q), tonumber(o), trim(verb)
                        end
                    elseif word == "level" then
                        local lvl, label = rest:match("^([%d%.]+)%s*(.*)$")
                        if not lvl then
                            errors[#errors + 1] = ("line %d: 'level' needs a number"):format(n)
                            step = nil
                        else
                            step.level = tonumber(lvl)
                            step.text = trim(label)
                        end
                    else
                        step.text = rest
                    end
                    if step then
                        if step.x and (step.x < 0 or step.x > 100 or step.y < 0 or step.y > 100) then
                            errors[#errors + 1] = ("line %d: coordinates must be 0-100"):format(n)
                        else
                            step.map = step.map or guide.map
                            guide.steps[#guide.steps + 1] = step
                        end
                    end
                end
            end
        end
    end
    if #guide.steps == 0 then errors[#errors + 1] = "the guide has no steps" end
    return guide, errors
end

-- ctx: { onQuest(id), flagged(id), complete(id), level(), distance(step) -> yards|nil, manual(step) -> bool }
-- only = "Orc,Troll" / "Orc,Warrior" / "!Warlock" / "NightElf,Skyborne,Alliance"
-- Races, classes and factions are each "any of"; groups must all match; "!" excludes.
J.CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
J.FACTIONS = { ALLIANCE = true, HORDE = true }
local RACE_ALIAS = { UNDEAD = "SCOURGE" }
function J.Matches(only, who)
    if not only or not who then return true end
    local groups = {}
    for token in only:gmatch("[^,]+") do
        local neg = token:sub(1, 1) == "!"
        local name = (neg and token:sub(2) or token):upper()
        name = RACE_ALIAS[name] or name
        local kind = J.CLASSES[name] and "class" or (J.FACTIONS[name] and "faction" or "race")
        local mine = (who[kind] or ""):upper()
        mine = RACE_ALIAS[mine] or mine
        if neg then
            if mine == name then return false end
        else
            groups[kind] = groups[kind] or false
            if mine == name then groups[kind] = true end
        end
    end
    for _, ok in pairs(groups) do if not ok then return false end end
    return true
end

function J.IsDone(step, ctx)
    if step.only and not J.Matches(step.only, ctx.who) then return true end -- not for you: skip
    if step.when and ctx.when and not ctx.when(step.when[1], step.when[2]) then return true end
    if ctx.manual and ctx.manual(step) then return true end
    local t, id = step.type, step.questID
    if t == "objective" then
        if ctx.flagged(id) then return true end
        if not ctx.onQuest(id) then return true end -- not on that quest: nothing to do here
        if ctx.complete(id) then return true end
        return ctx.objectiveDone and ctx.objectiveDone(id, step.obj) or false
    end
    if t == "accept" then
        return ctx.onQuest(id) or ctx.flagged(id)
    elseif t == "complete" then
        return ctx.flagged(id) or (ctx.onQuest(id) and ctx.complete(id))
    elseif t == "turnin" then
        return ctx.flagged(id)
    elseif t == "level" then
        return (ctx.levelExact and ctx.levelExact() or ctx.level()) >= step.level
    elseif t == "goto" then
        local d = ctx.distance and ctx.distance(step)
        return d ~= nil and d <= J.ARRIVE_YARDS
    end
    return false -- train / hearth / fly / note: the player ticks these off
end

-- First step at or after `from` that isn't done; returns index (or #steps + 1 when finished)
function J.CurrentIndex(steps, from, ctx)
    local i = math.max(1, from or 1)
    while i <= #steps and J.IsDone(steps[i], ctx) do i = i + 1 end
    return i
end

-- quests: { {id, title, level, complete, objectives = { {text, finished} }, distSq, skipped} }
-- Returns steps: turn-ins first, then quests in progress; nearest first; far-too-hard quests last.
function J.AutoSteps(quests, playerLevel)
    local turnins, todo, later = {}, {}, {}
    for _, q in ipairs(quests) do
        local step = { type = q.complete and "turnin" or "complete", questID = q.id, text = q.title,
                       objectives = q.objectives, distSq = q.distSq, questLevel = q.level, auto = true }
        if q.skipped then
            later[#later + 1] = step
        elseif q.complete then
            turnins[#turnins + 1] = step
        elseif q.level and playerLevel and q.level > playerLevel + 3 then
            later[#later + 1] = step
        else
            todo[#todo + 1] = step
        end
    end
    local function byDistance(a, b)
        if a.distSq and b.distSq then return a.distSq < b.distSq end
        if a.distSq then return true end
        if b.distSq then return false end
        return (a.questLevel or 0) < (b.questLevel or 0)
    end
    table.sort(turnins, byDistance)
    table.sort(todo, byDistance)
    table.sort(later, byDistance)
    local out = {}
    for _, list in ipairs({ turnins, todo, later }) do
        for _, s in ipairs(list) do out[#out + 1] = s end
    end
    return out
end

-- World positions: x points north, y points west (yards). Facing: radians, 0 = north,
-- counter-clockwise. Returns the texture rotation (counter-clockwise) and the distance.
function J.Bearing(px, py, tx, ty, facing)
    local dNorth, dWest = tx - px, ty - py
    local dist = math.sqrt(dNorth * dNorth + dWest * dWest)
    local bearing = math.atan2(dWest, dNorth)
    local rot = (bearing - (facing or 0)) % (2 * math.pi)
    return rot, dist
end

function J.FormatDistance(yards)
    if not yards then return "" end
    if yards >= 1000 then return string.format("%.1fk yd", yards / 1000) end
    return string.format("%d yd", math.floor(yards + 0.5))
end

-- Session rates (Overwolf-style stats): returns xpPerHour, secondsToLevel (or nil), goldPerHour
function J.SessionRates(elapsedSeconds, xpGained, xpLeft, copperGained)
    if not elapsedSeconds or elapsedSeconds < 60 then return 0, nil, 0 end
    local hours = elapsedSeconds / 3600
    local xph = (xpGained or 0) / hours
    local ttl = (xph > 0 and xpLeft and xpLeft > 0) and (xpLeft / xph * 3600) or nil
    return xph, ttl, math.max(0, copperGained or 0) / hours
end

-- 125 -> "2m", 3725 -> "1h 2m"
function J.FormatDuration(seconds)
    if not seconds then return "–" end
    seconds = math.floor(seconds + 0.5)
    local h, m = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", math.max(1, m))
end

-- 12345 -> "12.3k"
function J.Short(n)
    n = n or 0
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
end

function J.XPPercent(xp, xpMax)
    if not xp or not xpMax or xpMax <= 0 then return 0 end
    return math.floor(xp / xpMax * 100)
end
