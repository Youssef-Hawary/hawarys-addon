-- Hawary's Addon: core (modules, events, saved settings, combat queue, slash commands)
local ADDON, ns = ...
local L, U = ns.L, ns.Util

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
ns.media = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.CYAN = "38c6f4"
ns.PREFIX = "|cff38c6f4Hawary's|r"

local InCombatLockdown = InCombatLockdown or (C_RestrictedActions and C_RestrictedActions.InCombatLockdown)
ns.InCombat = function() return InCombatLockdown() and true or false end

---------------------------------------------------------------------------
-- Messages and safety helpers
---------------------------------------------------------------------------
function ns:Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. " " .. tostring(msg))
end

-- Run fn; if it errors, pass the error to the normal error handler (BugSack etc.)
-- instead of breaking whatever called us.
function ns.Safe(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(a) end
        return false
    end
    return true, a, b, c, d
end

-- True when a value can't be used by addon code right now (Midnight/Forever secret values).
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

---------------------------------------------------------------------------
-- Internal callbacks (UI refreshes etc.)
---------------------------------------------------------------------------
local callbacks = {}
function ns:On(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end
function ns:Fire(event, ...)
    local list = callbacks[event]
    if not list then return end
    for _, fn in ipairs(list) do ns.Safe(fn, ...) end
end

---------------------------------------------------------------------------
-- Combat-safe queue: protected changes wait until combat ends.
---------------------------------------------------------------------------
local combatQueue, combatOrder = {}, {}
function ns:RunOutOfCombat(key, fn)
    if not InCombatLockdown() then
        ns.Safe(fn)
        return true
    end
    if not combatQueue[key] then table.insert(combatOrder, key) end
    combatQueue[key] = fn
    return false
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
ns.defaults = {
    version = 1,
    general = {
        theme = "neon",
        language = "en",
        controller = true,
        minimap = { show = true, angle = 215 },
        welcome = true,
        toasts = true,
        scale = 1,
        window = {},
        lastPage = "home",
    },
    modules = {},
    chars = {},
    guides = {},
    prices = {},
    goldHistory = {},
    shopping = {},
    discovery = {},
    junk = {},
    profiles = {},
    funStats = {},
}
ns.charDefaults = {
    modules = {},
    bindings = {},
}

function ns:CharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return (name or "?") .. "-" .. (realm or "?")
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
ns.modules, ns.moduleOrder = {}, {}
local Module = {}
Module.__index = Module

-- info = { title, desc, icon, order, defaults = {}, charDefaults = {}, options = {...}, enabledByDefault }
function ns:NewModule(id, info)
    local m = setmetatable(info or {}, Module)
    m.id = id
    m.defaults = m.defaults or {}
    m.charDefaults = m.charDefaults or {}
    m.options = m.options or {}
    m.order = m.order or (#ns.moduleOrder + 1)
    if m.enabledByDefault == nil then m.enabledByDefault = true end
    ns.modules[id] = m
    table.insert(ns.moduleOrder, m)
    table.sort(ns.moduleOrder, function(a, b) return a.order < b.order end)
    return m
end

function Module:DB() return ns.db.modules[self.id] end
function Module:CharDB() return ns.cdb.modules[self.id] end

function Module:Get(key)
    if self.charDefaults[key] ~= nil then return self:CharDB()[key] end
    return self:DB()[key]
end

function Module:Set(key, value)
    if self.charDefaults[key] ~= nil then
        self:CharDB()[key] = value
    else
        self:DB()[key] = value
    end
    if self.enabled and self.OnSettingChanged then ns.Safe(self.OnSettingChanged, self, key, value) end
    ns:Fire("SETTING_CHANGED", self.id, key, value)
end

function Module:IsEnabled() return self.enabled == true end

function Module:RegisterEvent(event, handler)
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.handlers = {}
        local mod = self
        self.eventFrame:SetScript("OnEvent", function(_, e, ...)
            local h = mod.handlers[e]
            if type(h) == "string" then h = mod[h] end
            if h and not ns.Safe(h, mod, e, ...) then
                -- Lesson from other Forever addons: a module that keeps failing pauses itself
                -- for this session instead of flooding the player with errors.
                mod.errors = (mod.errors or 0) + 1
                if mod.errors >= 5 and mod.enabled then
                    mod.enabled = false
                    mod:UnregisterAllEvents()
                    if mod.OnDisable then ns.Safe(mod.OnDisable, mod) end
                    ns:Print(L.MODULE_ERRORS, mod.title or mod.id)
                end
            end
        end)
    end
    self.handlers[event] = handler or event
    self.eventFrame:RegisterEvent(event)
end

function Module:UnregisterEvent(event)
    if self.eventFrame then
        self.eventFrame:UnregisterEvent(event)
        self.handlers[event] = nil
    end
end

function Module:UnregisterAllEvents()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        wipe(self.handlers)
    end
end

function ns:SetModuleEnabled(id, on)
    local m = ns.modules[id]
    if not m then return end
    on = on and true or false
    ns.db.modules[id].enabled = on
    if on and not m.enabled then
        m.enabled = true
        if m.OnEnable then ns.Safe(m.OnEnable, m) end
    elseif not on and m.enabled then
        m.enabled = false
        m:UnregisterAllEvents()
        if m.OnDisable then ns.Safe(m.OnDisable, m) end
    end
    ns:Fire("MODULE_TOGGLED", id, on)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
core:RegisterEvent("PLAYER_REGEN_ENABLED")

local function InitDB()
    HawarysAddonDB = U.mergeDefaults(HawarysAddonDB, ns.defaults)
    HawarysAddonCharDB = U.mergeDefaults(HawarysAddonCharDB, ns.charDefaults)
    ns.db, ns.cdb = HawarysAddonDB, HawarysAddonCharDB
    for id, m in pairs(ns.modules) do
        local d = U.copy(m.defaults)
        d.enabled = m.enabledByDefault
        ns.db.modules[id] = U.mergeDefaults(ns.db.modules[id], d)
        ns.cdb.modules[id] = U.mergeDefaults(ns.cdb.modules[id], m.charDefaults)
    end
    if not ns.Theme.palettes[ns.db.general.theme] then ns.db.general.theme = "neon" end
    if ns.db.general.language == "ar" and ns.ApplyArabic then ns.Safe(ns.ApplyArabic) end
end

core:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        InitDB()
        for _, m in ipairs(ns.moduleOrder) do
            if m.OnInitialize then ns.Safe(m.OnInitialize, m) end
        end
        ns:Fire("DB_READY")
    elseif event == "PLAYER_LOGIN" then
        for _, m in ipairs(ns.moduleOrder) do
            if ns.db.modules[m.id].enabled then
                m.enabled = true
                if m.OnEnable then ns.Safe(m.OnEnable, m) end
            end
        end
        ns:Fire("LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReload = arg1, arg2
        if isInitialLogin and not isReload then ns:Fire("FIRST_LOGIN") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local order = combatOrder
        combatOrder = {}
        for _, key in ipairs(order) do
            local fn = combatQueue[key]
            combatQueue[key] = nil
            if fn then ns.Safe(fn) end
        end
        ns:Fire("COMBAT_ENDED")
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Modules add their own sub-commands: ns:RegisterSlash("dps", "show or hide the DPS meter", fn)
ns.slash, ns.slashOrder = {}, {}
function ns:RegisterSlash(cmd, help, fn)
    if not ns.slash[cmd] then table.insert(ns.slashOrder, cmd) end
    ns.slash[cmd] = { help = help, fn = fn }
end

SLASH_HAWARYSADDON1 = "/ha"
SLASH_HAWARYSADDON2 = "/hawary"
SLASH_HAWARYSADDON3 = "/hawarys"
SlashCmdList.HAWARYSADDON = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns:ToggleWindow()
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns:OpenBlizzardSettings()
    elseif cmd == "help" then
        ns:Print("/ha – open the window")
        ns:Print("/ha options – Blizzard options menu")
        ns:Print("/ha home | journey | gear | bags | qol | general – open a page")
        ns:Print("/ha guide – show or hide the guide window")
        ns:Print("/ha now – what should I do next?")
        ns:Print("/ha session – XP, gold and quests this session")
        ns:Print("/ha sort – sort your bags")
        ns:Print("/ha fly – point to the nearest flight master")
        ns:Print("/ha tracker – show or hide the quest tracker")
        ns:Print("/ha bis – best-in-slot finder")
        ns:Print("/ha fortune – today's fortune")
        ns:Print("/ha stats – print the raw stats of the item under your mouse")
        for _, c in ipairs(ns.slashOrder) do ns:Print("/ha %s – %s", c, ns.slash[c].help) end
        ns:Print("/ha version")
    elseif ns.slash[cmd] then
        ns.Safe(ns.slash[cmd].fn, (msg or ""):match("^%s*%S+%s*(.-)%s*$"))
    elseif cmd == "version" then
        ns:Print("%s %s", L.ADDON_TITLE, ns.version)
    elseif cmd == "stats" then
        ns:Fire("DEBUG_STATS")
    elseif cmd == "guide" then
        ns:Fire("JOURNEY_TOGGLE")
    elseif cmd == "now" then
        ns:Fire("WHATNOW_PRINT")
    elseif cmd == "session" then
        ns:Fire("EXTRAS_SESSION")
    elseif cmd == "sort" then
        ns:Fire("EXTRAS_SORT")
    elseif cmd == "fly" then
        ns:Fire("TRAVEL_NEAREST")
    elseif cmd == "fortune" then
        ns:Fire("FUN_FORTUNE")
    elseif cmd == "bis" then
        ns:OpenWindow("gearplus")
    elseif cmd == "tracker" then
        ns:Fire("TRACKER_TOGGLE")
    else
        ns:OpenWindow(cmd)
    end
end

---------------------------------------------------------------------------
-- Addon compartment (minimap addon menu); names are referenced by the TOC
---------------------------------------------------------------------------
function HawarysAddon_OnAddonCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        ns:OpenBlizzardSettings()
    else
        ns:ToggleWindow()
    end
end

-- Key bindings (Bindings.xml): bindable to a keyboard key or a controller button
BINDING_HEADER_HAWARYSADDON = "Hawary's Addon"
BINDING_NAME_HAWARYSADDON_TOGGLE = "Open / close Hawary's Addon"
BINDING_NAME_HAWARYSADDON_GUIDE = "Show / hide the guide window"
BINDING_NAME_HAWARYSADDON_TRACKER = "Show / hide the quest tracker"
function HawarysAddon_Toggle() ns:ToggleWindow() end
function HawarysAddon_ToggleGuide() ns:Fire("JOURNEY_TOGGLE") end
function HawarysAddon_ToggleTracker() ns:Fire("TRACKER_TOGGLE") end

function HawarysAddon_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText(L.ADDON_TITLE, 0.22, 0.78, 0.96)
    GameTooltip:AddLine(L.TAGLINE, 1, 1, 1, true)
    GameTooltip:Show()
end

function HawarysAddon_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
