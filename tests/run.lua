-- Hawary's Addon test runner (LuaJIT / Lua 5.1, same language as WoW)
-- Usage (from the repo root):  luajit tests/run.lua
-- Part 1: unit tests for pure logic.  Part 2: smoke test that loads the whole addon in TOC
-- order against a mocked WoW API, logs in, opens every page and toggles every module.

local ROOT = (arg and arg[0] or "tests/run.lua"):gsub("tests/run%.lua$", "")
if ROOT == "" then ROOT = "./" end
local ADDON = ROOT .. "HawarysAddon/"

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end

local function loadInto(ns, rel)
    local chunk = assert(loadfile(ADDON .. rel))
    chunk("HawarysAddon", ns)
end

---------------------------------------------------------------------------
-- Part 1: unit tests
---------------------------------------------------------------------------
local ns = {}
loadInto(ns, "Core/Util.lua")
loadInto(ns, "Modules/GearData.lua")
local U, D = ns.Util, ns.GearData

test("mergeDefaults fills missing, keeps false, fixes wrong types", function()
    local t = U.mergeDefaults({ a = false, b = "x", nested = { k = 1 } }, { a = true, b = 5, c = 3, nested = { k = 2, j = 4 } })
    eq(t.a, false); eq(t.b, 5, "wrong type replaced"); eq(t.c, 3); eq(t.nested.k, 1); eq(t.nested.j, 4)
end)

test("mergeDefaults copies default tables (no shared state)", function()
    local defaults = { list = { 1, 2 } }
    local a = U.mergeDefaults({}, defaults)
    a.list[1] = 99
    eq(defaults.list[1], 1)
end)

test("money formatting", function()
    eq(U.money(0, true), "0c")
    eq(U.money(5, true), "5c")
    eq(U.money(10305, true), "1g 3s 5c")
    eq(U.money(12345678, true), "1,234g 56s 78c")
    eq(U.money(20000, true), "2g")
end)

test("base64 round-trips every byte value", function()
    local bytes = {}
    for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
    local s = table.concat(bytes)
    for len = 0, 5 do
        local part = s:sub(1, 250 + len)
        eq(U.base64decode(U.base64encode(part)), part, "len " .. #part)
    end
    eq(U.base64encode("Man"), "TWFu")
    eq(U.base64encode("Ma"), "TWE=")
    eq(U.base64decode("not base64!"), nil)
    eq(U.base64decode("TW=u"), nil, "data after padding")
end)

test("serializer round-trips nested data", function()
    local v = { name = "Test", steps = { "/cast A", "/cast B" }, n = 3.5, flag = false, deep = { x = { y = true } } }
    local back = assert(U.deserialize(U.serialize(v)))
    eq(back.name, "Test"); eq(back.steps[2], "/cast B"); eq(back.n, 3.5); eq(back.flag, false); eq(back.deep.x.y, true)
end)

test("deserializer rejects bad input safely", function()
    eq(U.deserialize(""), nil)
    eq(U.deserialize("s5:abc"), nil, "short string")
    eq(U.deserialize("{s1:a"), nil, "unterminated")
    eq(U.deserialize("Tjunk"), nil, "trailing data")
    eq(U.deserialize("os.exit()"), nil, "code is not executed")
    local deep = string.rep("{n1;", 30) .. string.rep("}", 30)
    eq(U.deserialize(deep), nil, "too deep")
end)

test("score uses profile weights", function()
    local p = D.FindProfile("WARRIOR_DPS")
    eq(D.Score({ ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10 }, p), 10 * 1.0 + 10 * 0.3)
    eq(D.Score(nil, p), nil)
end)

test("profile picking by role and primary stat", function()
    eq(D.PickProfile("SHAMAN", "DAMAGER", 4).id, "SHAMAN_ELE")
    eq(D.PickProfile("SHAMAN", "DAMAGER", 2).id, "SHAMAN_ENH")
    eq(D.PickProfile("DRUID", "TANK", 2).id, "DRUID_BEAR")
    eq(D.PickProfile("MAGE", nil, nil).id, "MAGE_DPS")
    eq(D.PickProfile("WARRIOR", "DAMAGER", 1, "WARRIOR_TANK").id, "WARRIOR_TANK", "override")
    eq(D.PickProfile("SOMENEWCLASS", "DAMAGER", 1).id, "GENERIC")
end)

test("compare: empty slot, upgrade, downgrade, same, weakest ring", function()
    eq((D.Compare(10, { false })), "empty")
    local k, pct = D.Compare(12, { 10 })
    eq(k, "upgrade"); eq(math.floor(pct + 0.5), 20)
    eq((D.Compare(8, { 10 })), "downgrade")
    eq((D.Compare(10.05, { 10 })), "same")
    eq((D.Compare(15, { 20, 12 })), "upgrade", "compared with the weaker ring")
    eq(D.Compare(nil, { 10 }), nil)
end)

test("who can wear what", function()
    eq(D.CanWear("MAGE", 60, 4, 4), false, "mage plate")
    eq(D.CanWear("WARRIOR", 20, 4, 4), false, "warrior plate before 40")
    eq(D.CanWear("WARRIOR", 40, 4, 4), true, "warrior plate at 40")
    eq(D.CanWear("PRIEST", 10, 2, 19), true, "priest wand")
    eq(D.CanWear("ROGUE", 10, 2, 10), false, "rogue staff")
    eq(D.CanWear("WARRIOR", 10, 2, 20), false, "fishing pole")
    eq(D.CanWear("MAGE", 10, 4, 0), true, "generic (rings, necks)")
    eq(D.CanWear("PRIEST", 10, 4, 6), false, "priest shield")
end)

test("best quest reward: upgrade beats value; value fallback", function()
    eq((D.BestReward({ { index = 1, kind = "downgrade", value = 500 }, { index = 2, kind = "upgrade", pct = 5, value = 10 } })), 2)
    eq((D.BestReward({ { index = 1, kind = "upgrade", pct = 5 }, { index = 2, kind = "upgrade", pct = 30 } })), 2)
    eq((D.BestReward({ { index = 1, kind = "upgrade", pct = 50 }, { index = 2, kind = "empty" } })), 2, "empty slot wins")
    local idx, why = D.BestReward({ { index = 1, kind = "downgrade", value = 100 }, { index = 2, kind = "cantuse", value = 900 } })
    eq(idx, 2); eq(why, "value")
    eq(D.BestReward({ { index = 1 }, { index = 2 } }), nil)
end)

loadInto(ns, "Modules/JourneyData.lua")
local JD = ns.JourneyData

local SAMPLE_GUIDE = [[
# a test guide
guide: Test Valley 1-5
level: 1-5
map: 1429
accept 100 First Steps @ 48.2 42.9
complete 100 Kill wolves
turnin 100
goto 52.1,45.0 The Inn map=1430
level 4 Grind a bit
train
hearth Goldshire
note Read the sign
]]

test("guide parser: header, step types, coordinates, map", function()
    local g, errors = JD.ParseGuide(SAMPLE_GUIDE)
    eq(#errors, 0, table.concat(errors, "; "))
    eq(g.name, "Test Valley 1-5"); eq(g.minLevel, 1); eq(g.maxLevel, 5); eq(g.map, 1429)
    eq(#g.steps, 8)
    local s = g.steps[1]
    eq(s.type, "accept"); eq(s.questID, 100); eq(s.text, "First Steps"); eq(s.x, 48.2); eq(s.y, 42.9); eq(s.map, 1429)
    eq(g.steps[3].type, "turnin"); eq(g.steps[3].text, "")
    local go = g.steps[4]
    eq(go.type, "goto"); eq(go.x, 52.1); eq(go.y, 45.0); eq(go.text, "The Inn"); eq(go.map, 1430)
    eq(g.steps[5].level, 4); eq(g.steps[5].text, "Grind a bit")
    eq(g.steps[7].text, "Goldshire")
end)

test("guide parser: reports mistakes with line numbers", function()
    local g, errors = JD.ParseGuide("accept\nacept 5\ngoto nowhere\nlevel high\ngoto 150 20\nturnin 7")
    eq(#g.steps, 1, "only the valid turnin survives")
    eq(#errors, 5)
    truthy(errors[1]:find("line 1"), errors[1])
    truthy(errors[2]:find("unknown step"), errors[2])
    local _, none = JD.ParseGuide("# only comments")
    truthy(none[1]:find("no steps"))
end)

test("step completion rules", function()
    local state = { on = { [1] = true }, flagged = { [2] = true }, complete = { [1] = true }, level = 5, dist = 8, manual = {} }
    local ctx = {
        onQuest = function(id) return state.on[id] end,
        flagged = function(id) return state.flagged[id] end,
        complete = function(id) return state.complete[id] end,
        level = function() return state.level end,
        distance = function() return state.dist end,
        manual = function(step) return state.manual[step.line] end,
    }
    truthy(JD.IsDone({ type = "accept", questID = 1 }, ctx))
    truthy(JD.IsDone({ type = "accept", questID = 2 }, ctx), "already turned in counts as accepted")
    truthy(not JD.IsDone({ type = "accept", questID = 3 }, ctx))
    truthy(JD.IsDone({ type = "complete", questID = 1 }, ctx))
    truthy(not JD.IsDone({ type = "turnin", questID = 1 }, ctx))
    truthy(JD.IsDone({ type = "turnin", questID = 2 }, ctx))
    truthy(JD.IsDone({ type = "level", level = 5 }, ctx))
    truthy(not JD.IsDone({ type = "level", level = 6 }, ctx))
    truthy(JD.IsDone({ type = "goto", x = 1, y = 1 }, ctx), "within 12 yards")
    state.dist = 40
    truthy(not JD.IsDone({ type = "goto", x = 1, y = 1 }, ctx))
    truthy(not JD.IsDone({ type = "train", line = 9 }, ctx))
    state.manual[9] = true
    truthy(JD.IsDone({ type = "train", line = 9 }, ctx), "ticked off by the player")
    local steps = { { type = "accept", questID = 1 }, { type = "turnin", questID = 2 }, { type = "turnin", questID = 1 } }
    eq(JD.CurrentIndex(steps, 1, ctx), 3)
    eq(JD.CurrentIndex({ { type = "turnin", questID = 2 } }, 1, ctx), 2, "finished guide")
end)

test("auto journey: turn-ins first, nearest first, too-hard and skipped last", function()
    local steps = JD.AutoSteps({
        { id = 1, title = "Far", level = 5, distSq = 900 },
        { id = 2, title = "Near", level = 5, distSq = 100 },
        { id = 3, title = "Done far", level = 5, complete = true, distSq = 5000 },
        { id = 4, title = "Too hard", level = 20, distSq = 10 },
        { id = 5, title = "Skipped", level = 5, distSq = 1, skipped = true },
        { id = 6, title = "No position", level = 4 },
    }, 6)
    local order = {}
    for i, s in ipairs(steps) do order[i] = s.questID end
    eq(table.concat(order, ","), "3,2,1,6,5,4")
    eq(steps[1].type, "turnin"); eq(steps[2].type, "complete")
end)

test("arrow math: bearing and distance", function()
    local rot, dist = JD.Bearing(0, 0, 10, 0, 0) -- target north, facing north
    eq(math.floor(rot * 1000 + 0.5), 0); eq(dist, 10)
    rot = JD.Bearing(0, 0, 0, 10, 0) -- target west, facing north -> arrow points left
    eq(math.floor(rot * 1000 + 0.5), math.floor(math.pi / 2 * 1000 + 0.5))
    rot = JD.Bearing(0, 0, 0, 10, math.pi / 2) -- facing west, target west -> straight ahead
    eq(math.floor(rot * 1000 + 0.5) % math.floor(2 * math.pi * 1000 + 0.5), 0)
    eq(JD.FormatDistance(123.4), "123 yd"); eq(JD.FormatDistance(2500), "2.5k yd")
end)

test("session rates", function()
    local xph, ttl, gph = JD.SessionRates(1800, 5000, 10000, 20000)
    eq(xph, 10000); eq(ttl, 3600); eq(gph, 40000)
    local a, b = JD.SessionRates(30, 100, 100, 0)
    eq(a, 0); eq(b, nil)
    eq(JD.FormatDuration(3725), "1h 2m"); eq(JD.FormatDuration(125), "2m"); eq(JD.FormatDuration(nil), "–")
    eq(JD.Short(12345), "12.3k"); eq(JD.Short(999), "999"); eq(JD.XPPercent(50, 200), 25)
end)

loadInto(ns, "Modules/MarketData.lua")
local MD = ns.MarketData

test("market: lowest unit price per item from a full scan", function()
    local best = MD.LowestUnitPrices({
        { itemID = 1, count = 10, buyout = 1000 }, { itemID = 1, count = 1, buyout = 90 },
        { itemID = 2, count = 5, buyout = 0 }, { itemID = 3, count = 2, buyout = 50 },
    })
    eq(best[1], 90); eq(best[2], nil, "no buyout ignored"); eq(best[3], 25)
    local store = {}
    eq(MD.StorePrices(store, best, 100), 2); eq(store[1].p, 90); eq(store[1].t, 100)
end)

test("market: recipe profit treats unknown prices as unknown, never zero", function()
    local prices = { [10] = 100, [11] = 50, [20] = 400 }
    local function priceOf(id) return prices[id] end
    local r = MD.RecipeProfit({ output = 20, qty = 2, reagents = { { id = 10, n = 2 }, { id = 11, n = 1 } } }, priceOf)
    eq(r.cost, 250); eq(r.value, 800); eq(r.profit, 550); eq(#r.missing, 0)
    local u = MD.RecipeProfit({ output = 20, qty = 1, reagents = { { id = 10, n = 1 }, { id = 99, n = 3 } } }, priceOf)
    eq(u.cost, nil); eq(u.profit, nil); eq(u.missing[1], 99); eq(u.partialCost, 100)
    local list = MD.RankByProfit({
        { name = "B", result = { profit = 10 } }, { name = "A", result = {} }, { name = "C", result = { profit = 500 } },
    })
    eq(list[1].name, "C"); eq(list[2].name, "B"); eq(list[3].name, "A")
end)

test("shopping list: adds reagents across recipes, missing first", function()
    local recipes = {
        [1] = { reagents = { { id = 100, n = 2 }, { id = 200, n = 1 } } },
        [2] = { reagents = { { id = 100, n = 1 } } },
    }
    local rows = MD.ShoppingNeeds({ { recipeID = 1, count = 3 }, { recipeID = 2, count = 1 }, { recipeID = 9, count = 1 } },
        recipes, function(id) return id == 200 and 10 or 4 end)
    eq(#rows, 2)
    eq(rows[1].itemID, 100); eq(rows[1].need, 7); eq(rows[1].have, 4); eq(rows[1].missing, 3)
    eq(rows[2].itemID, 200); eq(rows[2].need, 3); eq(rows[2].missing, 0)
end)

test("age, gold series and item search", function()
    eq(MD.Age(30), "just now"); eq(MD.Age(600), "10m ago"); eq(MD.Age(7200), "2h ago"); eq(MD.Age(200000), "2d ago")
    local values, max = MD.GoldSeries({ ["d2"] = 100, ["d4"] = 300 }, { "d1", "d2", "d3", "d4" })
    eq(table.concat(values, ","), "0,100,100,300"); eq(max, 300)
    local hits = MD.SearchNames({ [1] = "Copper Ore", [2] = "Tin Ore", [3] = "Copper Bar" }, "copper")
    eq(#hits, 2); eq(hits[1], 3, "sorted by name")
    eq(#MD.SearchNames({ [1] = "A" }, "a"), 0, "needs 2 letters")
end)

loadInto(ns, "Modules/AdventureData.lua")
local AD = ns.AdventureData

test("adventure planner: now / soon / done by level", function()
    local acts = {
        { name = "Low", minLevel = 10, minSugg = 13, maxSugg = 18 },
        { name = "Mine", minLevel = 15, minSugg = 18, maxSugg = 23 },
        { name = "Next", minLevel = 20, minSugg = 24, maxSugg = 30 },
        { name = "Far", minLevel = 40, minSugg = 45, maxSugg = 52 },
        { name = "OpenEnded", minLevel = 19 },
    }
    local now, soon, done = AD.Classify(acts, 20)
    eq(#now, 2); eq(now[1].name, "Mine"); eq(now[2].name, "OpenEnded")
    eq(#soon, 1); eq(soon[1].name, "Next")
    eq(#done, 1); eq(done[1].name, "Low")
    eq(AD.LevelRange(acts[2]), "18-23"); eq(AD.LevelRange(acts[5]), "19")
    local stats = {}
    AD.AddRun(stats, { name = "Mine", duration = 1800, bosses = 3, finish = 10 })
    AD.AddRun(stats, { name = "Mine", duration = 1500, bosses = 3, finish = 20 })
    AD.AddRun(stats, { name = "Mine", duration = 900, bosses = 0, finish = 30 })
    eq(stats.Mine.runs, 3); eq(stats.Mine.best, 1500, "runs without bosses don't count as best"); eq(stats.Mine.last, 30)
end)

test("discovery: nearby sightings merge, far ones don't", function()
    local store = {}
    local _, new1 = AD.AddSighting(store, "node", "Peacebloom", 0.500, 0.500, 1)
    local e, new2 = AD.AddSighting(store, "node", "Peacebloom", 0.502, 0.501, 2)
    local _, new3 = AD.AddSighting(store, "node", "Peacebloom", 0.600, 0.500, 3)
    truthy(new1); truthy(not new2); truthy(new3)
    eq(e.count, 2); eq(e.last, 2)
    local _, rareNew = AD.AddSighting(store, "rare", "Peacebloom", 0.5, 0.5, 4)
    truthy(rareNew, "a rare is separate from a herb with the same name")
end)

test("what now: priorities", function()
    local list = AD.Suggestions({ turnins = 2, durability = 0.1, freeSlots = 10, upgrades = { { link = "x", pct = 12 } }, rested = true })
    eq(list[1].key, "repair"); eq(list[2].key, "upgrade"); eq(list[3].key, "turnin"); eq(list[#list].key, "rested")
    eq(AD.Suggestions({ freeSlots = 20 })[1].key, "quest", "nothing urgent -> go questing")
    eq(AD.Suggestions({ freeSlots = 1 })[1].key, "bags")
end)

test("diary: gold milestones and trimming", function()
    eq(AD.GoldMilestone(50000, 120000), 10)
    eq(AD.GoldMilestone(50000, 15000000), 1000, "highest crossed")
    eq(AD.GoldMilestone(200000, 300000), nil)
    local l = { 1, 2, 3, 4, 5 }
    AD.Trim(l, 3)
    eq(table.concat(l, ","), "3,4,5")
end)

loadInto(ns, "Modules/QuestLogic.lua")
local QL = ns.QuestLogic

test("quest availability: level, race/class masks, chains, exclusive, grey", function()
    local ctx = { level = 20, raceID = 2, classID = 1, completed = { [5] = true }, active = { [7] = true }, greyDiff = 7 }
    local function row(t) return t end
    eq(QL.Status(row({ [4] = 18, [5] = 20 }), 1, ctx), "available")
    eq(QL.Status(row({ [4] = 22, [5] = 22 }), 1, ctx), "low", "two levels too low")
    eq(QL.Status(row({ [4] = 25 }), 1, ctx), nil, "far too high")
    eq(QL.Status(row({ [4] = 5, [5] = 6 }), 1, ctx), "trivial")
    eq(QL.Status(row({ [4] = 18, [6] = 1 }), 1, ctx), nil, "race 2 not in mask 1")
    eq(QL.Status(row({ [4] = 18, [6] = 2 }), 1, ctx), "available")
    eq(QL.Status(row({ [4] = 18, [7] = 4 }), 1, ctx), nil, "class mask")
    eq(QL.Status(row({ [4] = 18, [13] = { 9, 5 } }), 1, ctx), "available", "one of the prereqs done")
    eq(QL.Status(row({ [4] = 18, [12] = { 5, 9 } }), 1, ctx), nil, "all prereqs needed")
    eq(QL.Status(row({ [4] = 18, [16] = { 7 } }), 1, ctx), nil, "exclusive with an active quest")
    eq(QL.Status(row({ [4] = 18 }), 5, ctx), nil, "already done")
    eq(QL.Status(row({ [4] = 18, [18] = { 186, 50 } }), 1, ctx), nil, "needs a profession skill")
    ctx.skill = function() return 75 end
    eq(QL.Status(row({ [4] = 18, [18] = { 186, 50 } }), 1, ctx), "available")
    truthy(QL.FriendlyTo("AH", "Horde")); truthy(not QL.FriendlyTo("A", "Horde")); truthy(QL.FriendlyTo(nil, "Horde"))
end)

test("quest objectives: mobs, objects, item drops, explore, hidden", function()
    local data = {
        npc = { [10] = { spawns = { [12] = { { 40, 40 } } } } },
        object = { [20] = { spawns = { [12] = { { 30, 30 } } } } },
        item = { [30] = { npcDrops = { 10 }, objectDrops = { 20 } } },
    }
    local get = function(e, id, f) return data[e][id] and data[e][id][f] end
    local quest = { [10] = { { { 10, "Wolf" } }, { { 20 } }, { { 30 } } }, [9] = { "Scout the hill", { [12] = { { 60, 60 } } } },
                    [29] = { { { [12] = { { 70, 70 } } }, 1, "Secret egg", 1 } } }
    local src = QL.ObjectiveSources(quest, get)
    local kinds = {}
    for _, s in ipairs(src) do kinds[#kinds + 1] = s.kind end
    eq(table.concat(kinds, ","), "npc,object,item_npc,item_object,explore,secret")
    local pts = QL.SpawnsOnMap({ [12] = { { 50, 25 } }, [99] = { { 1, 1 } } }, function(a) return a == 12 and 1429 or 2 end, 1429)
    eq(#pts, 1); eq(pts[1][1], 0.5); eq(pts[1][2], 0.25)
end)

test("minimap math", function()
    local x, y, d = QL.MinimapOffset(0, 0, 10, 0, 100, 50, false)
    eq(math.floor(x + 0.5), 0); eq(math.floor(y + 0.5), 5); eq(d, 10) -- north is up
    x, y = QL.MinimapOffset(0, 0, 0, 10, 100, 50, false)
    eq(math.floor(x + 0.5), -5); eq(math.floor(y + 0.5), 0) -- west is left
    x, y = QL.MinimapOffset(0, 0, 0, 10, 100, 50, true, math.pi / 2) -- facing west: west is up
    eq(math.floor(x + 0.5), 0); eq(math.floor(y + 0.5), 5)
    eq(QL.MinimapOffset(0, 0, 500, 0, 100, 50, false), nil, "outside the radius")
    local wx, wy = QL.ToWorld({ 100, 200, 0, 0 }, 0.5, 0.25)
    eq(wx, 75); eq(wy, 100)
end)

---------------------------------------------------------------------------
-- Part 2: smoke test with a mocked WoW API
---------------------------------------------------------------------------
local function returnsFor(name)
    if name == "GetWidth" or name == "GetHeight" or name:match("^GetString") then return 100 end
    if name == "GetScale" or name == "GetEffectiveScale" then return 1 end
    if name == "GetFrameLevel" then return 5 end
    if name == "GetID" then return 1 end
    if name == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
    if name == "GetCenter" then return 50, 50 end
    if name == "GetText" then return "" end
    if name == "GetChecked" or name:match("^Is") or name:match("^Has") then return false end
    if name == "SetFont" then return true end
    if name == "EnumerateValidItems" then return function() return nil end end
    return nil
end

local mockMT
local function mock() return setmetatable({}, mockMT) end
mockMT = {
    __index = function(t, k)
        if type(k) ~= "string" or k:match("^%l") then return nil end -- like real frames: only Methods exist
        local f = function()
            local r = { returnsFor(k) }
            if #r > 0 then return unpack(r) end
            if k:match("^Create") or k:match("^Get") then return mock() end
            return nil
        end
        rawset(t, k, f)
        return f
    end,
}

local events = {}
local function newFrame()
    local f = mock()
    local scripts = {}
    f.RegisterEvent = function(self, e) events[e] = events[e] or {}; events[e][self] = true end
    f.UnregisterEvent = function(self, e) if events[e] then events[e][self] = nil end end
    f.UnregisterAllEvents = function(self) for _, set in pairs(events) do set[self] = nil end end
    f.SetScript = function(_, s, fn) scripts[s] = fn end
    f.GetScript = function(_, s) return scripts[s] end
    f.HookScript = function(_, s, fn) scripts[s] = scripts[s] or fn end
    return f
end
local function fire(e, ...)
    local list = {}
    for f in pairs(events[e] or {}) do list[#list + 1] = f end
    for _, f in ipairs(list) do
        local h = f:GetScript("OnEvent")
        if h then h(f, e, ...) end
    end
end

local env = setmetatable({}, { __index = _G })
env._G = env
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.tinsert = table.insert
env.time = os.time
env.CreateFrame = function() return newFrame() end
env.CreateFont = function() return mock() end
env.hooksecurefunc = function() end
env.issecretvalue = function() return false end
env.geterrorhandler = function() return function(err) error(err, 0) end end
local inCombat = false
env.InCombatLockdown = function() return inCombat end
env.UnitName = function() return "Tester", "Forever" end
env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
env.UnitLevel = function() return 20 end
env.GetRealmName = function() return "Forever" end
env.GetMoney = function() return 123456 end
env.GetInventoryItemLink = function() return nil end
env.GetInventoryItemID = function() return nil end
env.GetLocale = function() return "enUS" end
env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
env.UISpecialFrames = {}
env.SlashCmdList = {}
env.StaticPopupDialogs = {}
env.StaticPopup_Show = function() end
env.StaticPopup_Hide = function() end
env.UIParent = newFrame()
env.Minimap = newFrame()
env.GameTooltip = mock()
env.SOUNDKIT = {}
env.PlaySound = function() end
env.MinimalSliderWithSteppersMixin = { Label = { Right = 2 }, Event = { OnValueChanged = "OnValueChanged" } }
env.Enum = {
    UITextureSliceMode = { Stretched = 0 },
    TooltipDataType = { Item = 0 },
    BagIndex = { Backpack = 0, Bag_4 = 4, ReagentBag = 5, CharacterBankTab_1 = 6, CharacterBankTab_9 = 14 },
    ItemQuality = { Poor = 0 },
}
env.C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
env.C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end, GetContainerItemLink = function() return nil end }
env.C_Item = setmetatable({}, { __index = function() return function() return nil end end })
env.C_CVar = { GetCVar = function() return nil end, SetCVar = function() return true end }
env.C_Map = { GetBestMapForUnit = function() return nil end }
env.C_ClassColor = { GetClassColor = function() return { GenerateHexColor = function() return "ffc69b6d" end } end }
env.C_SpecializationInfo = { GetSpecialization = function() return 0 end }
env.C_MerchantFrame = { GetNumJunkItems = function() return 0 end, SellAllJunkItems = function() end }
env.C_UI = { Reload = function() end }
env.TooltipDataProcessor = { AddTooltipPostCall = function() end }
env.TooltipUtil = { GetDisplayedItem = function() return nil end }
env.Settings = setmetatable({ VarType = { Boolean = "boolean", Number = "number", String = "string" } }, {
    __index = function() return function() return mock(), mock() end end,
})
env.CreateSettingsButtonInitializer = function() return mock() end
env.CreateSettingsListSectionHeaderInitializer = function() return mock() end

-- Journey: a fake quest log with two quests (one finished) and a fake position/facing
local function vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
local questLog = {
    { questID = 101, title = "Wolves", level = 3, complete = false, distSq = 400 },
    { questID = 102, title = "Letter", level = 2, complete = true, distSq = 2500 },
}
local calls = {}
local function record(name) return function(...) calls[name] = (calls[name] or 0) + 1 end end
env.C_QuestLog = {
    GetNumQuestLogEntries = function() return #questLog end,
    GetInfo = function(i) local q = questLog[i]; return q and { questID = q.questID, title = q.title, level = q.level } end,
    IsComplete = function(id) for _, q in ipairs(questLog) do if q.questID == id then return q.complete end end return false end,
    ReadyForTurnIn = function() return false end,
    GetQuestObjectives = function() return { { text = "0/5 Wolves slain", finished = false } } end,
    GetDistanceSqToQuest = function(id) for _, q in ipairs(questLog) do if q.questID == id then return q.distSq, true end end end,
    IsOnQuest = function(id) for _, q in ipairs(questLog) do if q.questID == id then return true end end return false end,
    IsQuestFlaggedCompleted = function() return false end,
    GetNextWaypoint = function() return nil end,
    GetQuestsOnMap = function() return { { questID = 102, x = 0.5, y = 0.5 } } end,
    GetTitleForQuestID = function(id) return "Quest " .. id end,
}
env.C_SuperTrack = { SetSuperTrackedQuestID = record("supertrack"), SetSuperTrackedUserWaypoint = record("supertrackwp") }
env.C_Map = {
    GetBestMapForUnit = function() return 1429 end,
    GetPlayerMapPosition = function() return vec(0.4, 0.4) end,
    GetWorldPosFromMapPos = function(_, v) return 0, vec(v.y * 1000, v.x * 1000) end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = record("userwp"), ClearUserWaypoint = record("clearwp"),
}
env.CreateVector2D = vec
env.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
env.GetPlayerFacing = function() return 0 end
env.GetTime = function() return 1000 end
env.UnitXP = function() return 300 end
env.UnitXPMax = function() return 1000 end
env.IsShiftKeyDown = function() return false end
env.QuestGetAutoAccept = function() return false end
env.AcceptQuest = record("accept")
env.AcknowledgeAutoAcceptQuest = record("ack")
env.GetQuestMoneyToGet = function() return 0 end
env.IsQuestCompletable = function() return true end
env.CompleteQuest = record("complete")
env.GetNumQuestChoices = function() return 0 end
env.GetQuestReward = record("reward")
env.C_GossipInfo = { GetActiveQuests = function() return {} end, GetAvailableQuests = function() return {} end }

-- Phase 3: auction house, professions, dates
env.date = os.date
env.UnitFactionGroup = function() return "Alliance", "Alliance" end
env.AuctionHouseFrame = newFrame()
env.GetProfessions = function() return 1, nil, 3 end
env.GetProfessionInfo = function(i) if i == 1 then return "Mining", 136248, 75, 150 end return "Cooking", 133971, 20, 75 end
local replicate = { { 2770, 20, 2000 }, { 2770, 1, 90 }, { 2840, 5, 1500 } }
env.C_AuctionHouse = {
    GetBrowseResults = function() return { { itemKey = { itemID = 2589 }, minPrice = 55 } } end,
    GetCommoditySearchResultInfo = function(id) return { itemID = id, unitPrice = 77 } end,
    GetNumItemSearchResults = function() return 1 end,
    GetItemSearchResultInfo = function() return { buyoutAmount = 5000 } end,
    ReplicateItems = record("replicate"),
    GetNumReplicateItems = function() return #replicate end,
    GetReplicateItemInfo = function(i)
        local r = replicate[i + 1]
        return nil, nil, r[2], 1, true, 1, nil, 0, 0, r[3], 0, nil, nil, nil, nil, 0, r[1], true
    end,
}
-- Phase 4: group finder list, instances, rares, gathering, map canvas
local instance = { "Hawarys Hold", "none" }
env.GetInstanceInfo = function() return instance[1], instance[2] end
env.C_LFGList = {
    GetAvailableCategories = function() return { 2 } end,
    GetLfgCategoryInfo = function() return { name = "Dungeons" } end,
    GetAvailableActivities = function() return { 11, 12, 13 } end,
    GetActivityInfoTable = function(id)
        if id == 11 then return { fullName = "Hawarys Hold", minLevel = 15, minLevelSuggestion = 18, maxLevelSuggestion = 24, maxNumPlayers = 5 } end
        if id == 12 then return { fullName = "Arena", isPvpActivity = true, minLevel = 10 } end
        return { fullName = "Deep Vault", minLevel = 22, minLevelSuggestion = 23, maxLevelSuggestion = 28, maxNumPlayers = 5 }
    end,
}
local targetClass = "normal"
env.UnitClassification = function() return targetClass end
env.UnitExists = function() return false end
env.C_Spell = { GetSpellName = function() return "Herb Gathering" end }
env.C_VignetteInfo = { GetVignetteInfo = function() return nil end }
env.GetInventoryItemDurability = function(slot) if slot == 5 then return 5, 100 end return nil end
env.GetXPExhaustion = function() return 500 end
env.GetZoneText = function() return "Test Valley" end
env.Screenshot = record("screenshot")
env.C_Container.GetContainerNumFreeSlots = function() return 4, 0 end
env.CreateFromMixins = function(...)
    local out = {}
    for _, m in ipairs({ ... }) do for k, v in pairs(m) do out[k] = v end end
    return out
end
env.MapCanvasPinMixin = {}
env.MapCanvasDataProviderMixin = {}
env.WorldMapFrame = newFrame()
env.WorldMapFrame.ScrollContainer = newFrame()
env.WorldMapFrame.AddDataProvider = record("addprovider")
env.WorldMapFrame.IsShown = function() return false end
env.C_Map.GetMapInfo = function() return { name = "Test Valley" } end
-- Quest database (tiny fake copy in the same shape as the bundled data)
env.HawarysQuestData = {
    quest = [[return {
        [500] = { "Wolf Trouble", { { 1 } }, { { 2 } }, 18, 20, 0, 0, { "Kill wolves" }, nil, { { { 10, "Wolf" } }, nil, { { 30 } } } },
        [501] = { "Next Step", { { 1 } }, { { 2 } }, 18, 20, 0, 0, nil, nil, {}, nil, nil, { 500 } },
        [101] = { "Wolves", { { 1 } }, { { 2 } }, 1, 3, 0, 0, nil, nil, { { { 10 } }, { { 20 } } }, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, { { { [12] = { { 70, 70 } } }, 1, "Secret egg", 1 } } },
    }]],
    npc = [[return {
        [1] = { "Ranger Giver", 0, 0, 20, 20, 0, { [12] = { { 41, 41 } } }, nil, 12, { 500 }, nil, 0, "AH" },
        [2] = { "Turnin Guy", 0, 0, 20, 20, 0, { [12] = { { 45, 45 } } }, nil, 12, nil, { 500 }, 0, "AH" },
        [10] = { "Wolf", 0, 0, 5, 6, 0, { [12] = { { 30, 30 }, { 31, 31 } } }, nil, 12 },
    }]],
    object = [[return { [20] = { "Strange Egg", nil, nil, { [12] = { { 35, 35 } } }, 12 } }]],
    item = [[return { [30] = { "Wolf Pelt", { 10 } } }]],
    areaToUiMap = [[return { [12] = 1429 }]],
    areaToUiMapOverride = [[return {}]],
    info = { built = "test" },
}
env.C_AddOns.DoesAddOnExist = function() return false end
env.C_AddOns.LoadAddOn = function() end
env.C_QuestLog.GetAllCompletedQuestIDs = function() return {} end
env.UnitRace = function() return "Orc", "Orc", 2 end
env.UnitIsPlayer = function() return false end
env.C_SkillInfo = { GetSkillLineInfoByID = function() return nil end }
env.IsIndoors = function() return false end
env.C_CVar.GetCVar = function() return nil end
env.Minimap.GetZoom = function() return 0 end
env.Enum.TooltipDataType.Unit = 2
env.Enum.TooltipDataType.Object = 4
-- trainer + macros + spellbook
env.GetNumTrainerServices = function() return 3 end
env.GetTrainerServiceInfo = function(i)
    if i == 1 then return "Heroic Strike", "available", 1, 20, "Rank 3" end
    if i == 2 then return "Cleave", "unavailable", 1, 22, "Rank 2" end
    return "Charge", "used", 1, 4, "" end
env.GetTrainerServiceCost = function(i) return i * 1000, false end
env.C_Trainer = { GetTrainerType = function() return 0 end }
env.GetNumMacros = function() return 0, 3 end
env.CreateMacro = record("createmacro")
env.C_SpellBook = { GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 2 } end,
    GetSpellBookItemName = function(i) return i == 1 and "Heroic Strike" or "Battle Shout" end,
    IsSpellBookItemPassive = function() return false end }
env.C_TradeSkillUI = {
    IsNPCCrafting = function() return false end,
    GetBaseProfessionInfo = function() return { professionName = "Mining" } end,
    GetFilteredRecipeIDs = function() return { 2657 } end,
    GetRecipeInfo = function() return { name = "Smelt Copper", learned = true, icon = 1 } end,
    GetRecipeSchematic = function() return { outputItemID = 2840, quantityMin = 1,
        reagentSlotSchematics = { { required = true, quantityRequired = 1, reagents = { { itemID = 2770 } } } } } end,
}

-- 1.2.0 mocks: tracker, nameplates, sets, flight paths, owned auctions, fun stats
env.C_QuestLog.GetNumQuestWatches = function() return 0 end
env.C_QuestLog.GetQuestIDForQuestWatchIndex = function() return nil end
env.C_QuestLog.IsUnitOnQuest = function(unit) return unit == "party1" end
env.C_NamePlate = { GetNamePlateForUnit = function() return newFrame() end }
env.UnitGUID = function() return "Creature-0-1-2-3-4001-0000ABCD" end
env.C_EquipmentSet = {
    GetEquipmentSetIDs = function() return { 1 } end,
    GetEquipmentSetInfo = function() return "Tank", 123, 1, true, 10, 10, 0, 0, 0 end,
    UseEquipmentSet = record("useset"), CreateEquipmentSet = record("createset"), SaveEquipmentSet = record("saveset"),
}
env.C_TaxiMap = { GetTaxiNodesForMap = function() return {
    { name = "Crossroads", position = vec(0.45, 0.4), faction = 0, isUndiscovered = false },
    { name = "Far Camp", position = vec(0.9, 0.9), faction = 2, isUndiscovered = true },
    { name = "Enemy Roost", position = vec(0.41, 0.41), faction = 1, isUndiscovered = true },
} end }
env.C_Map.GetMapWorldSize = function() return 10000, 8000 end
env.Enum.UIMapType = { Continent = 2, Zone = 3 }
env.Enum.FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 }
env.Enum.ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
    Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Quiver = 11, Questitem = 12 }
env.Enum.AuctionStatus = { Active = 0, Sold = 1 }
env.Enum.AuctionHouseSortOrder = { Price = 0, Name = 1 }
env.IsInInstance = function() return false end
env.UnitOnTaxi = function() return false end
env.UnitIsAFK = function() return true end
env.GetCursorInfo = function() return "item", 2589 end
env.ClearCursor = record("clearcursor")
env.JumpOrAscendStart = function() end
env.C_AuctionHouse.QueryOwnedAuctions = function() end
env.C_AuctionHouse.GetNumOwnedAuctions = function() return 0 end
env.strsplit = function(sep, str)
    local out = {}
    for part in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end

local function loadTOC()
    local addonNS = {}
    local toc = assert(io.open(ADDON .. "HawarysAddon.toc")):read("*a")
    local count = 0
    for line in toc:gmatch("[^\r\n]+") do
        if line:match("%.lua%s*$") and not line:match("^#") then
            local rel = line:gsub("\\", "/"):gsub("%s+$", "")
            local chunk = assert(loadfile(ADDON .. rel))
            setfenv(chunk, env)
            chunk("HawarysAddon", addonNS)
            count = count + 1
        end
    end
    return addonNS, count
end

local A
test("smoke: every TOC file loads in order", function()
    local n
    A, n = loadTOC()
    truthy(n >= 9, "files loaded: " .. n)
    truthy(A.modules.gear and A.modules.bags and A.modules.qol, "modules registered")
end)

test("smoke: ADDON_LOADED + login + entering world", function()
    fire("ADDON_LOADED", "HawarysAddon")
    truthy(env.HawarysAddonDB and env.HawarysAddonCharDB, "saved variables created")
    eq(env.HawarysAddonDB.general.theme, "neon")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", true, false)
    truthy(A.modules.gear:IsEnabled() and A.modules.qol:IsEnabled(), "modules enabled")
end)

test("smoke: open every page", function()
    for _, page in ipairs({ "home", "general", "journey", "gear", "bags", "qol", "talents", "macrohelp", "nonsense" }) do
        A:OpenWindow(page)
    end
end)

test("smoke: toggle modules, change settings, slash commands, toasts, events", function()
    for id in pairs(A.modules) do
        A:SetModuleEnabled(id, false)
        A:SetModuleEnabled(id, true)
    end
    A.modules.gear:Set("profile", "WARRIOR_TANK")
    A.modules.qol:Set("camera", true)
    A.modules.qol:Set("coords", false)
    A.modules.qol:Set("fastLoot", true)
    A.General:Set("scale", 1.2)
    for _, cmd in ipairs({ "", "help", "version", "stats", "gear", "options" }) do env.SlashCmdList.HAWARYSADDON(cmd) end
    A:Toast("Title", "Text")
    A:Toast("Queued", "Second")
    fire("MERCHANT_SHOW")
    fire("BAG_UPDATE_DELAYED")
    fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
    fire("PLAYER_REGEN_ENABLED")
end)

test("smoke: journey auto mode, guide import, next/back, automation guarded", function()
    local Jm = A.modules.journey
    truthy(Jm:IsEnabled(), "journey enabled")
    Jm:Refresh()
    eq(Jm.view.mode, "auto")
    eq(Jm.current.questID, 102, "finished quest comes first")
    eq(Jm.current.type, "turnin")
    truthy(calls.supertrack and calls.supertrack >= 1, "Blizzard supertrack used")
    local dist = Jm:DistanceTo(Jm.target)
    truthy(dist and dist > 0, "distance computed")
    Jm:Next() -- skip in auto mode
    eq(Jm.current.questID, 101)
    Jm:Back() -- un-skip
    eq(Jm.current.questID, 102)

    local name, errors, n = Jm:ImportGuide(SAMPLE_GUIDE)
    eq(name, "Test Valley 1-5"); eq(n, 8); eq(#errors, 0)
    Jm:Set("guide", name)
    eq(Jm.view.mode, "guide")
    eq(Jm.view.index, 1, "quest 100 isn't in the log, so the guide starts at step 1")
    eq(Jm.current.type, "accept")
    truthy(calls.userwp and calls.userwp >= 1, "coordinate step sets Blizzard's own map pin")
    Jm:Next()
    eq(Jm.view.index, 2)
    Jm:Back()
    eq(Jm.view.index, 1)
    Jm:Set("guide", "auto")
    eq(Jm.view.mode, "auto")

    -- automation is off by default
    fire("QUEST_DETAIL"); fire("QUEST_PROGRESS"); fire("QUEST_COMPLETE")
    eq(calls.accept, nil); eq(calls.complete, nil); eq(calls.reward, nil)
    Jm:Set("autoAccept", true); Jm:Set("autoTurnIn", true)
    fire("QUEST_DETAIL"); fire("QUEST_PROGRESS"); fire("QUEST_COMPLETE")
    eq(calls.accept, 1); eq(calls.complete, 1); eq(calls.reward, 1)
    env.IsShiftKeyDown = function() return true end -- Shift pauses it
    fire("QUEST_DETAIL")
    eq(calls.accept, 1)
    env.IsShiftKeyDown = function() return false end
    env.GetNumQuestChoices = function() return 3 end -- several rewards: the player chooses
    fire("QUEST_COMPLETE")
    eq(calls.reward, 1)
    inCombat = true -- never in combat
    fire("QUEST_DETAIL")
    eq(calls.accept, 1)
    inCombat = false
    for _, cmd in ipairs({ "guide", "guide", "journey" }) do env.SlashCmdList.HAWARYSADDON(cmd) end
end)

test("smoke: market prices, full scan, professions, shopping list, alts", function()
    local Mk, Pr, Al = A.modules.market, A.modules.professions, A.modules.alts
    truthy(Mk:IsEnabled() and Pr:IsEnabled() and Al:IsEnabled(), "phase 3 modules enabled")
    fire("AUCTION_HOUSE_SHOW")
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    eq(Mk:Price(2589), 55)
    fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2771)
    eq(Mk:Price(2771), 77)
    Mk:StartScan()
    eq(calls.replicate, 1)
    fire("REPLICATE_ITEM_LIST_UPDATE")
    eq(Mk:Price(2770), 90, "lowest unit price from the full scan")
    eq(Mk:Price(2840), 300)
    Mk:StartScan() -- 15 minute cooldown
    eq(calls.replicate, 1)

    Pr:ScanRanks()
    local me = env.HawarysAddonDB.chars["Tester-Forever"]
    eq(#me.profs, 2); eq(me.profs[2].name, "Mining"); eq(me.profs[2].rank, 75)
    Pr:ScanRecipes()
    eq(me.recipes.Mining[2657].output, 2840)
    Pr:AddToList(2657, 3)
    local rows = Pr:ShoppingRows()
    eq(rows[1].itemID, 2770); eq(rows[1].need, 3)
    Pr:AddToList(2657, -3)
    eq(#env.HawarysAddonDB.shopping, 0)

    Al:Record()
    local today = os.date("%Y-%m-%d")
    truthy(env.HawarysAddonDB.goldHistory[today], "gold history recorded")
    for _, page in ipairs({ "market", "professions", "alts" }) do A:OpenWindow(page) end
    Pr:AddToList(2657, 2)
    A:OpenWindow("professions")
end)

test("smoke: dungeons planner + log, discovery, what now, diary", function()
    local Dg, Ds, Nw, Dy = A.modules.dungeons, A.modules.discovery, A.modules.whatnow, A.modules.diary
    truthy(Dg:IsEnabled() and Ds:IsEnabled() and Nw:IsEnabled() and Dy:IsEnabled(), "phase 4 modules enabled")
    eq(calls.addprovider, 2, "quests + discovery map layers registered with Blizzard's data provider")
    local acts = Dg:Activities()
    eq(#acts, 2, "PvP activity skipped")
    eq(Dg:Suggestion().name, "Hawarys Hold") -- player is level 20

    -- a dungeon run: enter, kill 2 bosses, leave
    instance[1], instance[2] = "Hawarys Hold", "party"
    fire("ZONE_CHANGED_NEW_AREA")
    truthy(Dg.run, "run started")
    Dg.run.start = Dg.run.start - 1200
    fire("ENCOUNTER_END", 1, "Boss A", 1, 5, 1)
    fire("ENCOUNTER_END", 2, "Boss B", 1, 5, 1)
    fire("ENCOUNTER_END", 3, "Wipe", 1, 5, 0)
    instance[1], instance[2] = "Test Valley", "none"
    fire("ZONE_CHANGED_NEW_AREA")
    local stats = Dg:Get("stats")["Hawarys Hold"]
    eq(stats.runs, 1); truthy(stats.best >= 1200)
    eq(Dg:Get("runs")[1].bosses, 2)
    eq(Dg:Suggestion(), nil, "already ran Hawarys Hold; Deep Vault (23+) is not for level 20 yet")

    -- rare
    targetClass = "rare"
    fire("PLAYER_TARGET_CHANGED")
    local rares = Ds:Totals()
    eq(rares, 1)
    targetClass = "normal"

    -- gathering a herb (cast on an object, then loot)
    fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "cast-1", 2366)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 2366)
    fire("LOOT_OPENED")
    local _, nodes = Ds:Totals()
    eq(nodes, 1)

    -- what now: gear at 5% durability -> repair first
    local list = Nw:List()
    eq(list[1].key, "repair")
    for _, cmd in ipairs({ "now" }) do env.SlashCmdList.HAWARYSADDON(cmd) end

    -- diary: level up with screenshots on
    Dy:Set("screenshots", true)
    fire("PLAYER_LEVEL_UP", 21)
    local entries = Dy:Get("entries")
    truthy(#entries >= 3, "dungeon + rare + level in the diary, got " .. #entries)
    eq(entries[#entries].kind, "level")
    eq(calls.screenshot ~= nil, true)
    for _, page in ipairs({ "home", "dungeons", "discovery", "whatnow", "diary" }) do A:OpenWindow(page) end
end)

test("smoke: quest database, pins, tooltips index, smart route, trainer, macros", function()
    local Qm = A.modules.quests
    truthy(Qm:IsEnabled(), "quests enabled")
    Qm:Rebuild()
    eq(Qm.source, "bundled")
    eq(Qm.available[500], "available")
    eq(Qm.available[501], nil, "needs quest 500 first")
    local pins = Qm:PinsFor(1429)
    local kinds = {}
    for _, p in ipairs(pins) do kinds[p.kind] = (kinds[p.kind] or 0) + 1 end
    truthy(kinds.available, "quest giver pin")
    truthy(kinds.npc and kinds.object and kinds.secret, "objective pins incl. hidden egg for active quest 101")
    truthy(Qm.tipByName["Wolf"], "wolf tooltip lines")
    truthy(Qm.tipByName["Ranger Giver"], "giver tooltip line")
    local near = ns and nil
    local nearby = A.QuestProvider.NearbyAvailable(3)
    eq(#nearby, 1); eq(nearby[1].questID, 500)
    truthy(A.QuestProvider.NearestFor(101), "nearest objective spot for an active quest")
    Qm:UpdateMinimap()
    -- journey picks the quest pickup into Auto Journey
    local Jm = A.modules.journey
    Jm:Refresh()
    local hasPickup = false
    for _, s in ipairs(Jm.view.steps) do if s.type == "accept" and s.questID == 500 then hasPickup = true end end
    truthy(hasPickup or #Jm.view.steps == 3, "smart route adds the pickup when there's room")

    local Tr, Mc = A.modules.training, A.modules.macros
    fire("TRAINER_SHOW")
    local now, byLevel, cost, levels = Tr:Plan()
    eq(#now, 1); eq(cost, 1000); eq(levels[1], 22)
    local body, n = Mc.Build(Mc.templates[1].text, "Flash Heal")
    truthy(body:find("@mouseover", 1, true) and body:find("Flash Heal", 1, true)); truthy(n < 255)
    eq(#Mc:Spells(), 2)
    Mc:Create("Heal", body)
    eq(calls.createmacro, 1)
    Mc:Create("", body)
    eq(calls.createmacro, 1, "needs a name")
    for _, page in ipairs({ "quests", "training", "macros", "home" }) do A:OpenWindow(page) end
end)

test("routes: race/class rules, sections/tips, start where you are, chain to next zone", function()
    eq(JD.Matches("Orc,Warrior", { race = "Orc", class = "WARRIOR" }), true)
    eq(JD.Matches("Orc,Warrior", { race = "Troll", class = "WARRIOR" }), false)
    eq(JD.Matches("!Warlock", { class = "WARLOCK" }), false)
    eq(JD.Matches("Undead", { race = "Scourge" }), true)
    local g = JD.ParseGuide("guide: T\nid: t/1\nsection Camp\ntip Look left\naccept 9 only Mage\nobjective 9.2 kill when onquest 9\nlevel 5.5")
    eq(#g.steps, 3); eq(g.steps[1].section, "Camp"); eq(g.steps[1].tip, "Look left"); eq(g.steps[1].only, "Mage")
    eq(g.steps[2].type, "objective"); eq(g.steps[2].obj, 2); eq(g.steps[2].when[1], "onquest"); eq(g.steps[3].level, 5.5)

    env.HawarysGuides = { list = {
        { id = "f/horde/orc/01-start", title = "Start", faction = "Horde", race = "Orc", levels = "1-10", next = "f/horde/02-next" },
        { id = "f/horde/02-next", title = "Next", faction = "Horde", levels = "10-20" },
    }, text = {
        ["f/horde/orc/01-start"] = "guide: Start\nid: f/horde/orc/01-start\naccept 101\naccept 102",
        ["f/horde/02-next"] = "guide: Next\nid: f/horde/02-next\naccept 700\nturnin 700",
    } }
    local Jm = A.modules.journey
    Jm.packIndex = nil
    Jm:StartRoute("Horde", "Orc", "WARRIOR")
    eq(Jm:Get("guide"), "pack:f/horde/02-next", "quests 101/102 are already in the log, so the route starts at the next zone")
    eq(Jm.view.index, 1); eq(Jm.current.questID, 700)
    A:OpenWindow("journey")
    Jm:Set("guide", "auto")
end)

test("extras: settings code round-trip, sort, session, level summary", function()
    local X = A.modules.extras
    local before = env.HawarysAddonDB.modules.qol.repair
    local data = { general = { theme = "neon" }, modules = { qol = { repair = not before } } }
    local code = "HAWARY1:" .. ns.Util.base64encode(ns.Util.serialize(data))
    local back = X.Decode(code)
    truthy(back, "decodes"); eq(X.Decode("garbage"), nil)
    X:Apply(back)
    eq(env.HawarysAddonDB.modules.qol.repair, not before)
    env.C_Container.SortBags = record("sort")
    env.SlashCmdList.HAWARYSADDON("sort"); eq(calls.sort, 1)
    env.SlashCmdList.HAWARYSADDON("session")
    fire("PLAYER_LEVEL_UP", 22)
    A:OpenWindow("extras")
end)

test("1.2.0 pure logic: tracker, BiS, bags, auctions, flights, button bag, fun", function()
    local Tr = A.modules.tracker
    eq(Tr.Yards(100 * 100), 100); eq(Tr.Yards(nil), nil); eq(Tr.Yards(0), nil)
    eq(Tr.FormatYards(250), "250 yd"); eq(Tr.FormatYards(1500), "1.5k yd"); eq(Tr.FormatYards(nil), "")
    eq(Tr.NpcIDFromGUID("Creature-0-1-2-3-4001-0000ABCD"), 4001)
    eq(Tr.NpcIDFromGUID("Player-1-0ABC"), nil); eq(Tr.NpcIDFromGUID(nil), nil)

    local GP = A.modules.gearplus
    local best = GP.Pick({
        { group = "HEAD", pct = 5, minLevel = 18 }, { group = "HEAD", pct = 12, minLevel = 20 },
        { group = "HEAD", pct = 30, minLevel = 24 }, { group = "FEET", pct = 9, minLevel = 40 },
        { group = "NECK", pct = 0, minLevel = 1 },
    }, 20)
    eq(best.now.HEAD.pct, 12, "best usable now"); eq(best.soon.HEAD.pct, 30, "best in the next 5 levels")
    eq(best.soon.FEET, nil, "level 40 is too far"); eq(best.now.NECK, nil, "no gain, no entry")

    local BP = A.modules.bagsplus
    local IC = env.Enum.ItemClass
    eq(BP.Categorize(IC.Armor, 2, 1), "GEAR"); eq(BP.Categorize(IC.Armor, 0, 1), "POOR")
    eq(BP.Categorize(IC.Questitem, 1, 1), "QUEST"); eq(BP.Categorize(IC.Tradegoods, 1, 1), "TRADE")
    eq(BP.Categorize(99, 1, 1), "OTHER")
    env.HawarysAddonDB.junk[777] = true
    eq(BP.Categorize(IC.Armor, 2, 777), "JUNKLIST", "your junk list wins")
    env.HawarysAddonDB.junk[777] = nil

    local AW = A.modules.auctions
    local under = AW.Undercuts({ { itemID = 1, unit = 100 }, { itemID = 2, unit = 50 }, { itemID = 3, unit = 10 } },
        function(id) return ({ [1] = 90, [2] = 50 })[id], 0 end)
    eq(#under, 1, "only cheaper ones count"); eq(under[1].itemID, 1); eq(under[1].lowest, 90)

    local TR = A.modules.travel
    local ranked = TR.Rank({ { name = "A", x = 0.5, y = 0.5 }, { name = "B", x = 0.41, y = 0.4 } }, 0.4, 0.4, 1000, 1000)
    eq(ranked[1].name, "B"); eq(ranked[1].yards, 10)

    local BB = A.modules.buttonbag
    eq(BB.Wants("LibDBIcon10_Questie"), true); eq(BB.Wants("SomeAddonMinimapButton"), true)
    eq(BB.Wants("HawarysAddonMinimapButton"), false); eq(BB.Wants("MiniMapTracking"), false)
    eq(BB.Wants("GameTimeFrame"), false); eq(BB.Wants(nil), false)

    local F = A.Fun
    local new = F.NewBadges({ jumps = 150, deaths = 0, skins = { a = true, b = true, c = true, d = true, e = true } }, { jump100 = 1 })
    local set = {}
    for _, id in ipairs(new) do set[id] = true end
    truthy(set.skins5 and not set.jump100 and not set.death1, "only newly reached badges")
    local p1, p2 = F.DailyPick(20404, 3), F.DailyPick(20404, 3)
    eq(#p1, 3); eq(p1[1], p2[1]); eq(p1[3], p2[3])
    truthy(p1[1] ~= p1[2] and p1[2] ~= p1[3] and p1[1] ~= p1[3], "3 different challenges")
    local outfit = F.RandomOutfit({ { id = 1, equipLoc = "INVTYPE_HEAD" }, { id = 2, equipLoc = "INVTYPE_HEAD" },
        { id = 3, equipLoc = "INVTYPE_FEET" }, { id = 4, equipLoc = "INVTYPE_FINGER" } }, function(a) return a end)
    eq(#outfit, 2, "one per visible slot, rings aren't shown"); eq(outfit[1], 1)
    eq(F.HexPoints(false, 0), 1); eq(F.HexPoints(true, 0), 3); eq(F.HexPoints(false, 10), 3)
    truthy(F.FortuneFor(20404) ~= nil, "a fortune every day")
end)

test("1.2.0 smoke: every new page, tracker, sets, junk seller, flights, profiles, fun moments", function()
    for _, page in ipairs({ "tracker", "gearplus", "bagsplus", "auctions", "travel", "buttonbag", "profiles",
                            "skins", "fashion", "funstats", "hexhop", "moments" }) do
        truthy(A.modules[page], "module " .. page)
        A:OpenWindow(page)
    end
    -- tracker + party + click-to-arrow
    local Tr = A.modules.tracker
    env.UnitExists = function(u) return u == "party1" end
    local rows = Tr:List()
    truthy(#rows >= 1, "tracker lists quests")
    eq(rows[1].party[1], "Tester", "party member on the same quest")
    Tr:Focus(rows[1].id)
    eq(A.modules.journey.focusQuest, rows[1].id, "arrow follows the clicked quest")
    env.UnitExists = function() return false end
    env.SlashCmdList.HAWARYSADDON("tracker")
    fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    -- equipment sets: one click = one Blizzard call, never in combat
    local GP = A.modules.gearplus
    eq(GP:Sets()[1].name, "Tank")
    GP:UseSet(1); eq(calls.useset, 1)
    inCombat = true; GP:UseSet(1); eq(calls.useset, 1); inCombat = false
    GP:SaveSet("Fishing"); eq(calls.createset, 1)
    GP:Scan()
    -- junk: one stack per click, only at a merchant
    local BP = A.modules.bagsplus
    local used = 0
    env.C_Container.UseContainerItem = function() used = used + 1 end
    env.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
    env.C_Container.GetContainerItemInfo = function(_, slot) return { itemID = 2589, stackCount = 5, quality = 1, iconFileID = 1 } end
    BP:AddJunk(2589)
    fire("MERCHANT_CLOSED") -- an earlier smoke test opened a merchant
    BP:SellOne(); eq(used, 0, "not without a merchant")
    fire("MERCHANT_SHOW")
    BP:SellOne(); eq(used, 1, "one stack per click")
    inCombat = true; BP:SellOne(); eq(used, 1, "never in combat"); inCombat = false
    fire("MERCHANT_CLOSED")
    A:OpenWindow("bagsplus")
    BP:RemoveJunk(2589)
    env.C_Container.GetContainerNumSlots = function() return 0 end
    -- flights: own faction + neutral only, nearest known first
    env.C_Map.GetMapInfo = function(id) return { name = "Kalimdor", mapType = 2 } end
    local list = A.modules.travel:Nodes()
    eq(#list, 2, "enemy flight masters left out")
    eq(list[1].name, "Crossroads")
    env.SlashCmdList.HAWARYSADDON("fly")
    -- auction watch
    env.C_AuctionHouse.GetNumOwnedAuctions = function() return 1 end
    env.C_AuctionHouse.GetOwnedAuctionInfo = function() return { status = 0, itemKey = { itemID = 2589 }, buyoutAmount = 999, quantity = 1 } end
    env.C_AuctionHouse.QueryOwnedAuctions = record("ownedquery")
    fire("AUCTION_HOUSE_SHOW")
    fire("OWNED_AUCTIONS_UPDATED")
    eq(#A.modules.auctions.last.list, 1, "undercut found (55 < 999)")
    -- profiles
    local PF = A.modules.profiles
    truthy(PF:Save("Main"), "profile saved")
    truthy(PF:Load("Main"), "profile loaded")
    PF:Set("auto", "Main"); A:Fire("DB_READY"); PF:Delete("Main"); eq(PF:Get("auto"), "")
    -- fun
    fire("PLAYER_DEAD")
    fire("QUEST_TURNED_IN", 101, 100, 0)
    fire("PLAYER_LEVEL_UP", 23)
    fire("PLAYER_FLAGS_CHANGED", "player")
    fire("PLAYER_REGEN_DISABLED")
    env.SlashCmdList.HAWARYSADDON("fortune")
    A.modules.moments:Party()
    A.Fun:CheckBadges()
    truthy(env.HawarysAddonDB.funStats.badges.death1, "first death badge")
    eq(#A.Fun:Daily(), 3)
    env.SlashCmdList.HAWARYSADDON("bis")
    A:Fire("BUTTONBAG_TOGGLE")
end)

test("smoke: native theme builds too", function()
    env.HawarysAddonDB.general.theme = "native"
    local B = loadTOC()
    fire("ADDON_LOADED", "HawarysAddon")
    fire("PLAYER_LOGIN")
    for _, page in ipairs({ "home", "general", "journey", "gear", "bags", "qol", "market", "professions", "alts", "dungeons", "discovery", "whatnow", "diary", "quests", "training", "macros" }) do B:OpenWindow(page) end
end)

test("1.2.0 smoke: Arabic language and every skin load", function()
    env.HawarysAddonDB.general.theme = "terminal"
    env.HawarysAddonDB.general.language = "ar"
    local B = loadTOC()
    fire("ADDON_LOADED", "HawarysAddon")
    fire("PLAYER_LOGIN")
    truthy(B.arabic, "Arabic applied")
    truthy(B.L.NAV_HOME ~= "Home" and B.L.NAV_HOME:find("\239\187", 1, true), "shaped Arabic (presentation forms)")
    truthy(B.modules.skins.title ~= "Skins", "module titles swapped")
    eq(B.L.QUESTS_PIN_LOOT, "Contains a quest item", "untranslated keys stay English")
    for _, page in ipairs({ "home", "general", "skins", "funstats", "gearplus", "tracker", "journey" }) do B:OpenWindow(page) end
    env.HawarysAddonDB.general.language = "en"
    env.HawarysAddonDB.general.theme = "neon"
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
