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
env.InCombatLockdown = function() return false end
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
    for _, page in ipairs({ "home", "general", "gear", "bags", "qol", "journey", "macrohelp", "nonsense" }) do
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

test("smoke: native theme builds too", function()
    env.HawarysAddonDB.general.theme = "native"
    local B = loadTOC()
    fire("ADDON_LOADED", "HawarysAddon")
    fire("PLAYER_LOGIN")
    for _, page in ipairs({ "home", "general", "gear", "bags", "qol" }) do B:OpenWindow(page) end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
