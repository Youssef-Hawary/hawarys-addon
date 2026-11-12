-- Hawary's Addon: Profiles – save your settings under a name, load them on any
-- character, and let a character load its own profile automatically at login.
-- Settings only; character data (bags, gold, routes) is never touched.
local _, ns = ...
local L, U, W = ns.L, ns.Util, ns.W

local PF = ns:NewModule("profiles", {
    title = L.MOD_PROFILES,
    desc = L.MOD_PROFILES_DESC,
    order = 20,
    charDefaults = { auto = "" },
})

-- Snapshot of the current settings (same shape as the Extras export code)
function PF.Collect()
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
    return data
end

function PF:Save(name)
    name = U.trim(name or "")
    if name == "" then return false end
    ns.db.profiles[name] = { data = PF.Collect(), saved = time(), by = ns:CharKey() }
    ns:Print(L.PROFILE_SAVED:format(name))
    return true
end

function PF:Load(name, silent)
    local p = ns.db.profiles[name]
    if not p then return false end
    ns.modules.extras:Apply(p.data) -- also copies each module's on/off switch
    if not silent then
        -- switch modules now; at login (silent) the startup reads the switches itself
        for id, settings in pairs(p.data.modules or {}) do
            if ns.modules[id] and settings.enabled ~= nil then ns:SetModuleEnabled(id, settings.enabled) end
        end
        ns:Print(L.PROFILE_LOADED:format(name))
        StaticPopup_Show("HAWARYS_ADDON_RELOAD")
    end
    return true
end

function PF:Delete(name)
    ns.db.profiles[name] = nil
    if self:Get("auto") == name then self:Set("auto", "") end
end

-- A character's own profile is applied as soon as settings load, before any module starts
ns:On("DB_READY", function()
    if not ns.db.modules.profiles.enabled then return end
    local auto = PF:Get("auto")
    if auto ~= "" and ns.db.profiles[auto] then PF:Load(auto, true) end
end)

function PF:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetWidth(width)
    local head = W.Label(card, L.PROFILE_TITLE, "h2", "text")
    head:SetPoint("TOPLEFT", 16, -14)
    local box = W.EditBox(card, 200, 24)
    box:SetPoint("TOPRIGHT", -140, -10)
    local save = W.Button(card, L.PROFILE_SAVE, "primary", 120)
    save:SetPoint("LEFT", box, "RIGHT", 8, 0)
    local autoLabel = W.Label(card, L.PROFILE_AUTO, "small", "text2")
    autoLabel:SetPoint("TOPLEFT", 16, -48)
    local autoDD = W.Dropdown(card, 220, function()
        local out = { { value = "", text = L.PROFILE_AUTO_NONE } }
        for _, n in ipairs(U.sortedKeys(ns.db.profiles)) do out[#out + 1] = { value = n, text = n } end
        return out
    end, function() return PF:Get("auto") end, function(v) PF:Set("auto", v) end)
    autoDD:SetPoint("LEFT", autoLabel, "RIGHT", 10, 0)
    local rows = {}
    local function fill()
        for _, r in ipairs(rows) do r:Hide() end
        local yy, i = -84, 0
        for _, name in ipairs(U.sortedKeys(ns.db.profiles)) do
            i = i + 1
            local p = ns.db.profiles[name]
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, card)
                r:SetHeight(26)
                r.name = W.Label(r, "", "body", "text")
                r.name:SetPoint("LEFT", 0, 0)
                r.load = W.Button(r, L.PROFILE_LOAD, "primary", 80, 22)
                r.load:SetPoint("RIGHT", -86, 0)
                r.del = W.Button(r, L.DELETE, "secondary", 80, 22)
                r.del:SetPoint("RIGHT", 0, 0)
                rows[i] = r
            end
            r:SetPoint("TOPLEFT", 16, yy); r:SetPoint("RIGHT", card, "RIGHT", -16, 0)
            r.name:SetText(name .. "  |cff77808f" .. (p.by or "") .. " · " .. date("%Y-%m-%d", p.saved or 0) .. "|r")
            r.load:SetScript("OnClick", function() PF:Load(name) end)
            r.del:SetScript("OnClick", function() PF:Delete(name); fill() end)
            r:Show()
            yy = yy - 28
        end
        if i == 0 then
            rows.empty = rows.empty or W.Label(card, L.PROFILE_EMPTY, "small", "text3")
            rows.empty:SetPoint("TOPLEFT", 16, yy); rows.empty:Show()
            yy = yy - 22
        elseif rows.empty then rows.empty:Hide() end
        card:SetHeight(-yy + 10)
        if autoDD.Refresh then autoDD:Refresh() end
    end
    save:SetScript("OnClick", function() if PF:Save(box:GetText()) then box:SetText(""); fill() end end)
    fill()
    return y - 360
end
