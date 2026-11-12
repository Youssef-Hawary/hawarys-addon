-- Hawary's Addon: quest database logic (availability, objective locations, map math).
-- No WoW API here, so it is unit-tested. Rows have the same shape as QuestieDB's data
-- (field indexes from QuestieDB's src/meta/*Meta.lua).
local _, ns = ...

local Q = {}
ns.QuestLogic = Q

Q.FIELDS = {
    quest = {
        name = 1, startedBy = 2, finishedBy = 3, requiredLevel = 4, questLevel = 5, requiredRaces = 6,
        requiredClasses = 7, objectivesText = 8, triggerEnd = 9, objectives = 10, sourceItemId = 11,
        preQuestGroup = 12, preQuestSingle = 13, childQuests = 14, inGroupWith = 15, exclusiveTo = 16,
        zoneOrSort = 17, requiredSkill = 18, requiredMinRep = 19, requiredMaxRep = 20, requiredSourceItems = 21,
        nextQuestInChain = 22, questFlags = 23, specialFlags = 24, parentQuest = 25, reputationReward = 26,
        breadcrumbForQuestId = 27, breadcrumbs = 28, extraObjectives = 29, requiredSpell = 30,
    },
    npc = {
        name = 1, minLevel = 4, maxLevel = 5, rank = 6, spawns = 7, waypoints = 8, zoneID = 9,
        questStarts = 10, questEnds = 11, factionID = 12, friendlyToFaction = 13, subName = 14, npcFlags = 15,
    },
    object = { name = 1, questStarts = 2, questEnds = 3, spawns = 4, zoneID = 5, factionID = 6, waypoints = 7 },
    item = {
        name = 1, npcDrops = 2, objectDrops = 3, itemDrops = 4, startQuest = 5, questRewards = 6, flags = 7,
        foodType = 8, itemLevel = 9, requiredLevel = 10, class = 12, subClass = 13, vendors = 14, relatedQuests = 15,
    },
}

local band = (bit and bit.band) or function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end
Q.band = band

-- Decode a "return { ... }" data string (WoW: loadstring). Returns the table or nil.
function Q.Decode(source)
    if type(source) ~= "string" then return nil end
    local fn = (loadstring or load)(source)
    if not fn then return nil end
    local ok, t = pcall(fn)
    return ok and t or nil
end

---------------------------------------------------------------------------
-- Availability
-- ctx = { level, raceID, classID, completed = {[id]=true}, active = {[id]=true},
--         skill = function(skillID) -> rank or nil, greyDiff = number }
-- Returns "available" | "trivial" (grey) | "low" (1-2 levels too low) | nil (not for you)
---------------------------------------------------------------------------
local function anyIn(list, set)
    if type(list) ~= "table" then return false end
    for _, id in ipairs(list) do if set[id] then return true end end
    return false
end
local function allIn(list, set)
    if type(list) ~= "table" then return true end
    for _, id in ipairs(list) do if not set[id] then return false end end
    return true
end

function Q.Status(row, id, ctx)
    local F = Q.FIELDS.quest
    if ctx.completed[id] or ctx.active[id] then return nil end
    local races = row[F.requiredRaces]
    if races and races ~= 0 and ctx.raceID and band(races, 2 ^ (ctx.raceID - 1)) == 0 then return nil end
    local classes = row[F.requiredClasses]
    if classes and classes ~= 0 and ctx.classID and band(classes, 2 ^ (ctx.classID - 1)) == 0 then return nil end
    local single = row[F.preQuestSingle]
    if type(single) == "table" and #single > 0 and not anyIn(single, ctx.completed) then return nil end
    if not allIn(row[F.preQuestGroup], ctx.completed) then return nil end
    if anyIn(row[F.exclusiveTo], ctx.completed) or anyIn(row[F.exclusiveTo], ctx.active) then return nil end
    local nextQ = row[F.nextQuestInChain]
    if nextQ and nextQ ~= 0 and (ctx.completed[nextQ] or ctx.active[nextQ]) then return nil end
    local parent = row[F.parentQuest]
    if parent and parent ~= 0 and not ctx.active[parent] then return nil end
    local skill = row[F.requiredSkill]
    if type(skill) == "table" and skill[1] and skill[1] > 0 then
        local rank = ctx.skill and ctx.skill(skill[1])
        if not rank or rank < (skill[2] or 0) then return nil end
    end
    local req = row[F.requiredLevel] or 0
    if req > ctx.level then
        return (req - ctx.level <= 2) and "low" or nil
    end
    local qlvl = row[F.questLevel] or req
    if qlvl > 0 and qlvl < ctx.level - (ctx.greyDiff or 7) then return "trivial" end
    return "available"
end

-- NPC/object faction check: friendlyToFaction "A", "H" or "AH" (nil = everyone)
function Q.FriendlyTo(friendly, faction)
    if not friendly or friendly == "" then return true end
    if faction == "Alliance" then return friendly:find("A", 1, true) ~= nil end
    if faction == "Horde" then return friendly:find("H", 1, true) ~= nil end
    return true
end

---------------------------------------------------------------------------
-- Locations
---------------------------------------------------------------------------
-- spawns = { [areaID] = { {x, y}, ... } } in map percent; mapOf(areaID) -> uiMapID
-- Appends { x, y } normalized 0..1 for the requested uiMapID to `out`
function Q.SpawnsOnMap(spawns, mapOf, uiMapID, out)
    out = out or {}
    if type(spawns) ~= "table" then return out end
    for areaID, list in pairs(spawns) do
        if mapOf(areaID) == uiMapID and type(list) == "table" then
            for _, c in ipairs(list) do
                if type(c) == "table" and c[1] and c[2] and c[1] >= 0 and c[2] >= 0 then
                    out[#out + 1] = { c[1] / 100, c[2] / 100 }
                end
            end
        end
    end
    return out
end

-- Every place a quest's objectives can be done. get(entity, id, field) reads the data.
-- Returns { {kind = "npc"|"object"|"item_npc"|"item_object"|"explore"|"secret", id, label, spawns} }
function Q.ObjectiveSources(quest, get)
    local F = Q.FIELDS.quest
    local out = {}
    local obj = quest[F.objectives] or {}
    for _, o in ipairs(obj[1] or {}) do
        out[#out + 1] = { kind = "npc", id = o[1], label = o[2], spawns = get("npc", o[1], "spawns") }
    end
    for _, o in ipairs(obj[2] or {}) do
        out[#out + 1] = { kind = "object", id = o[1], label = o[2], spawns = get("object", o[1], "spawns") }
    end
    for _, o in ipairs(obj[3] or {}) do
        local itemID = o[1]
        for _, npcID in ipairs(get("item", itemID, "npcDrops") or {}) do
            out[#out + 1] = { kind = "item_npc", id = npcID, item = itemID, spawns = get("npc", npcID, "spawns") }
        end
        for _, objectID in ipairs(get("item", itemID, "objectDrops") or {}) do
            out[#out + 1] = { kind = "item_object", id = objectID, item = itemID, spawns = get("object", objectID, "spawns") }
        end
    end
    for _, kc in ipairs(obj[5] or {}) do
        for _, npcID in ipairs(kc[1] or {}) do
            out[#out + 1] = { kind = "npc", id = npcID, label = kc[3], spawns = get("npc", npcID, "spawns") }
        end
    end
    local trigger = quest[F.triggerEnd]
    if type(trigger) == "table" and type(trigger[2]) == "table" then
        out[#out + 1] = { kind = "explore", label = trigger[1], spawns = trigger[2] }
    end
    for _, extra in ipairs(quest[F.extraObjectives] or {}) do
        if type(extra[1]) == "table" then
            out[#out + 1] = { kind = "secret", label = extra[3], spawns = extra[1] }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Map math
---------------------------------------------------------------------------
-- rect = { tlx, tly, brx, bry }: world corners of a map (x = north, y = west)
function Q.ToWorld(rect, mx, my)
    return rect[1] + (rect[3] - rect[1]) * my, rect[2] + (rect[4] - rect[2]) * mx
end

-- Minimap offset in pixels from the player for a world point, or nil when outside the radius.
-- rotate = the minimap turns with the camera; facing = radians (0 = north, counter-clockwise).
function Q.MinimapOffset(px, py, tx, ty, radiusYards, pixelRadius, rotate, facing)
    local dNorth, dWest = tx - px, ty - py
    local dist = math.sqrt(dNorth * dNorth + dWest * dWest)
    if dist > radiusYards then return nil end
    local east, north = -dWest, dNorth
    if rotate and facing then
        local c, s = math.cos(facing), math.sin(facing)
        east, north = east * c + north * s, -east * s + north * c
    end
    local scale = pixelRadius / radiusYards
    return east * scale, north * scale, dist
end

-- Minimap radius in yards by zoom level (HereBeDragons values: diameter / 2)
Q.MINIMAP_OUTDOOR = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 }
Q.MINIMAP_INDOOR = { [0] = 150, 120, 90, 60, 40, 25 }
