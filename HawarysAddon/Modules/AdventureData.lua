-- Hawary's Addon: Phase 4 logic – adventure planner, discovery map layer, "What now?"
-- suggestions and diary helpers. No WoW API here, so it is unit-tested.
local _, ns = ...

local A = {}
ns.AdventureData = A

---------------------------------------------------------------------------
-- Adventure planner: group Blizzard's own group-finder activities by your level
-- activity = { name, minLevel, minSugg, maxSugg, players, category }
---------------------------------------------------------------------------
A.SOON_LEVELS = 5

local function low(a) return (a.minSugg and a.minSugg > 0) and a.minSugg or (a.minLevel or 0) end
local function high(a) return (a.maxSugg and a.maxSugg > 0) and a.maxSugg or nil end

function A.Classify(activities, level)
    local now, soon, done = {}, {}, {}
    for _, a in ipairs(activities) do
        local lo, hi = low(a), high(a)
        if level >= lo and (not hi or level <= hi) then
            now[#now + 1] = a
        elseif level < lo and lo - level <= A.SOON_LEVELS then
            soon[#soon + 1] = a
        elseif hi and level > hi then
            done[#done + 1] = a
        end
    end
    local function byLevel(x, y)
        if low(x) ~= low(y) then return low(x) < low(y) end
        return (x.name or "") < (y.name or "")
    end
    table.sort(now, byLevel); table.sort(soon, byLevel); table.sort(done, byLevel)
    return now, soon, done
end

function A.LevelRange(a)
    local lo, hi = low(a), high(a)
    if hi and hi ~= lo then return ("%d-%d"):format(lo, hi) end
    return tostring(lo)
end

-- Dungeon log: add a finished run to stats { [name] = { runs, best, last } }
function A.AddRun(stats, run)
    local s = stats[run.name] or { runs = 0 }
    s.runs = s.runs + 1
    s.last = run.finish
    if run.bosses and run.bosses > 0 and (not s.best or run.duration < s.best) then s.best = run.duration end
    stats[run.name] = s
    return s
end

---------------------------------------------------------------------------
-- Discovery map layer
---------------------------------------------------------------------------
-- Sightings closer than ~0.6% of the map are the same spot.
function A.SpotKey(kind, name, x, y)
    return ("%s:%s:%d:%d"):format(kind, name, math.floor(x * 160 + 0.5), math.floor(y * 160 + 0.5))
end

-- store = { [key] = { kind, name, x, y, count, first, last } }; returns entry, isNew
function A.AddSighting(store, kind, name, x, y, now)
    local key = A.SpotKey(kind, name, x, y)
    local e = store[key]
    if e then
        e.count = e.count + 1
        e.last = now
        return e, false
    end
    e = { kind = kind, name = name, x = x, y = y, count = 1, first = now, last = now }
    store[key] = e
    return e, true
end

---------------------------------------------------------------------------
-- "What now?" – turn the player's situation into a short, ranked to-do list
-- state = { turnins, upgrades = { {link, pct} }, freeSlots, durability (0..1),
--           trainerDue, shoppingMissing, rested, dungeonNow, level }
---------------------------------------------------------------------------
function A.Suggestions(state)
    local out = {}
    local function add(key, priority, data) out[#out + 1] = { key = key, priority = priority, data = data } end
    if state.durability and state.durability < 0.2 then add("repair", 100, state.durability) end
    if state.freeSlots and state.freeSlots <= 2 then add("bags", 90, state.freeSlots) end
    if state.upgrades and #state.upgrades > 0 then add("upgrade", 80, state.upgrades[1]) end
    if state.turnins and state.turnins > 0 then add("turnin", 70, state.turnins) end
    if state.trainerDue then add("trainer", 60, state.level) end
    if state.dungeonNow then add("dungeon", 40, state.dungeonNow) end
    if state.shoppingMissing and state.shoppingMissing > 0 then add("shopping", 30, state.shoppingMissing) end
    if state.rested then add("rested", 20, nil) end
    if #out == 0 then add("quest", 10, nil) end
    table.sort(out, function(a, b) return a.priority > b.priority end)
    return out
end

---------------------------------------------------------------------------
-- Diary
---------------------------------------------------------------------------
A.GOLD_MILESTONES = { 10, 100, 1000, 10000, 100000 }

-- Highest gold milestone (in gold) crossed between two copper amounts, or nil
function A.GoldMilestone(oldCopper, newCopper)
    local hit
    for _, g in ipairs(A.GOLD_MILESTONES) do
        local c = g * 10000
        if (oldCopper or 0) < c and newCopper >= c then hit = g end
    end
    return hit
end

-- Keep a list bounded (oldest dropped)
function A.Trim(list, max)
    while #list > max do table.remove(list, 1) end
    return list
end
