-- Hawary's Addon: Map+ (OpenMap / Leatrix Maps / Mapster style extras for Blizzard's world map)
-- Movable and scalable world map that remembers its place, fades while you run, a zone/city/dungeon
-- search, a "Find me" button, reopen-where-you-left-it and mouse-wheel zoom on the minimap.
-- Coordinates are in the QoL module. When the OpenMap addon is loaded, Map+ leaves the world map
-- alone (OpenMap asks for other map addons to stay off it) and only keeps the minimap zoom.
local _, ns = ...
local L, T, W, U = ns.L, ns.Theme, ns.W, ns.Util

local MP = ns:NewModule("mapplus", {
    title = L.MOD_MAPPLUS,
    desc = L.MOD_MAPPLUS_DESC,
    order = 24,
    defaults = { move = true, scale = 1, fade = true, fadeAlpha = 0.45, search = true, remember = false,
        wheelZoom = true, pos = {} },
})

MP.options = {
    { type = "toggle", key = "move", label = L.MP_MOVE, desc = L.MP_MOVE_DESC },
    { type = "slider", key = "scale", label = L.MP_SCALE, desc = L.MP_SCALE_DESC, min = 0.5, max = 1.5, step = 0.05, format = "%.2f" },
    { type = "toggle", key = "fade", label = L.MP_FADE, desc = L.MP_FADE_DESC },
    { type = "slider", key = "fadeAlpha", label = L.MP_FADE_ALPHA, desc = L.MP_FADE_ALPHA_DESC, min = 0.1, max = 1, step = 0.05, format = "%.2f", parent = "fade" },
    { type = "toggle", key = "search", label = L.MP_SEARCH, desc = L.MP_SEARCH_DESC },
    { type = "toggle", key = "remember", label = L.MP_REMEMBER, desc = L.MP_REMEMBER_DESC },
    { type = "toggle", key = "wheelZoom", label = L.MP_WHEEL, desc = L.MP_WHEEL_DESC },
    { type = "button", label = L.MP_RESET_POS, desc = L.MP_RESET_POS_DESC, buttonText = L.RESET,
      onClick = function() MP:DB().pos = {}; ns:Print(L.MP_RESET_DONE) end },
}

local hooked, bar, lastMap

---------------------------------------------------------------------------
-- Pure helpers (unit-tested)
---------------------------------------------------------------------------
-- Map search: names that contain the text (case-insensitive), starts-with first, max n.
function MP.FindMaps(list, text, n)
    text = U.trim(text or ""):lower()
    if text == "" then return {} end
    local starts, contains, seen = {}, {}, {}
    for _, m in ipairs(list) do
        local name = m.name and m.name:lower()
        if name and not seen[m.name] then
            local at = name:find(text, 1, true)
            if at == 1 then starts[#starts + 1] = m; seen[m.name] = true
            elseif at then contains[#contains + 1] = m; seen[m.name] = true end
        end
    end
    local byName = function(a, b) return a.name < b.name end
    table.sort(starts, byName)
    table.sort(contains, byName)
    local out = {}
    for _, m in ipairs(starts) do if #out < (n or 12) then out[#out + 1] = m end end
    for _, m in ipairs(contains) do if #out < (n or 12) then out[#out + 1] = m end end
    return out
end

-- New minimap zoom level for a wheel step, kept within 0..max
function MP.ZoomStep(current, delta, max)
    local z = (current or 0) + (delta > 0 and 1 or -1)
    if z < 0 then z = 0 elseif z > max then z = max end
    return z
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local function OpenMapLoaded()
    local _, loaded = C_AddOns.IsAddOnLoaded("OpenMap")
    return loaded and true or false
end

local function WorldMapActive()
    return MP.enabled and WorldMapFrame ~= nil and not OpenMapLoaded()
end

local function Maximized()
    return WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() and true or false
end

function MP:ApplyLayout()
    if not WorldMapActive() then return end
    ns:RunOutOfCombat("mapplus-layout", function()
        if Maximized() then
            WorldMapFrame:SetScale(1)
            return
        end
        WorldMapFrame:SetScale(MP:Get("scale"))
        local pos = MP:Get("pos")
        if MP:Get("move") and pos and pos.point then
            WorldMapFrame:ClearAllPoints()
            WorldMapFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        end
    end)
end

-- All zones, cities, continents and dungeons under the world map, for the search box
local mapList
local function MapList()
    if mapList then return mapList end
    mapList = {}
    local root = C_Map.GetFallbackWorldMapID()
    for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
        if info.mapType == Enum.UIMapType.Continent or info.mapType == Enum.UIMapType.Zone
            or info.mapType == Enum.UIMapType.Dungeon then
            mapList[#mapList + 1] = { name = info.name, mapID = info.mapID }
        end
    end
    return mapList
end

local function BuildBar()
    if bar then return bar end
    bar = CreateFrame("Frame", nil, WorldMapFrame)
    bar:SetHeight(26)
    bar:SetPoint("TOPLEFT", WorldMapFrame, "BOTTOMLEFT", 0, -2)
    bar:SetPoint("TOPRIGHT", WorldMapFrame, "BOTTOMRIGHT", 0, -2)
    bar.bg = T.Shape(bar, "round_sm", "window", "BACKGROUND", 0)
    bar.border = T.Shape(bar, "round_sm_line", "line", "BORDER", 0)

    bar.find = W.Button(bar, L.MP_FIND_ME, "secondary", 90, 20)
    bar.find:SetPoint("LEFT", 4, 0)
    bar.find:SetScript("OnClick", function()
        local id = C_Map.GetBestMapForUnit("player")
        if id then WorldMapFrame:SetMapID(id) end
    end)

    bar.search = W.EditBox(bar, 200, 20)
    bar.search:SetPoint("LEFT", bar.find, "RIGHT", 6, 0)
    bar.hint = W.Label(bar.search, L.MP_SEARCH_HINT, "small", "text3")
    bar.hint:SetPoint("LEFT", 8, 0)
    bar.search.edit:HookScript("OnEditFocusGained", function() bar.hint:Hide() end)
    bar.search.edit:HookScript("OnEditFocusLost", function(self) bar.hint:SetShown(self:GetText() == "") end)
    bar.search.edit:SetScript("OnEnterPressed", function(self)
        local matches = MP.FindMaps(MapList(), self:GetText(), 12)
        if #matches == 0 then return end
        if #matches == 1 then
            WorldMapFrame:SetMapID(matches[1].mapID)
            self:ClearFocus()
            return
        end
        MenuUtil.CreateContextMenu(bar.search, function(_, root)
            for _, m in ipairs(matches) do
                root:CreateButton(m.name, function() WorldMapFrame:SetMapID(m.mapID) end)
            end
        end)
    end)

    bar.drag = W.Label(bar, L.MP_DRAG_HINT, "small", "text3", "RIGHT")
    bar.drag:SetPoint("RIGHT", -8, 0)
    return bar
end

local function UpdateBar()
    if not bar then return end
    bar:SetShown(WorldMapActive() and MP:Get("search") and not Maximized())
    bar.drag:SetShown(MP:Get("move") and true or false)
end

-- Fading while you move (OpenMap / Leatrix "fade while moving")
local fadeElapsed = 0
local function FadeTick(_, elapsed)
    fadeElapsed = fadeElapsed + elapsed
    if fadeElapsed < 0.15 then return end
    fadeElapsed = 0
    if not (WorldMapActive() and MP:Get("fade")) then WorldMapFrame:SetAlpha(1); return end
    local moving = IsPlayerMoving() and not WorldMapFrame:IsMouseOver()
    WorldMapFrame:SetAlpha(moving and MP:Get("fadeAlpha") or 1)
end

local function HookWorldMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    -- drag handle over the title bar (out of combat only)
    local handle = CreateFrame("Frame", nil, WorldMapFrame)
    handle:SetPoint("TOPLEFT", 60, 0)
    handle:SetPoint("TOPRIGHT", -110, 0)
    handle:SetHeight(24)
    handle:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 20)
    handle:EnableMouse(true)
    handle:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" or not (WorldMapActive() and MP:Get("move")) or Maximized() or ns.InCombat() then return end
        WorldMapFrame:SetMovable(true)
        WorldMapFrame:StartMoving()
        handle.moving = true
    end)
    handle:SetScript("OnMouseUp", function()
        if not handle.moving then return end
        handle.moving = false
        WorldMapFrame:StopMovingOrSizing()
        local p, _, rp, x, y = WorldMapFrame:GetPoint(1)
        MP:DB().pos = { point = p, relPoint = rp, x = x, y = y }
    end)
    -- Ctrl + mouse wheel over the title: change the map size
    handle:EnableMouseWheel(true)
    handle:SetScript("OnMouseWheel", function(_, delta)
        if not IsControlKeyDown() then return end
        local s = U.clamp((MP:Get("scale") or 1) + delta * 0.05, 0.5, 1.5)
        MP:Set("scale", math.floor(s * 100 + 0.5) / 100)
    end)

    WorldMapFrame:HookScript("OnShow", function()
        if not WorldMapActive() then return end
        BuildBar()
        UpdateBar()
        C_Timer.After(0, function() ns.Safe(MP.ApplyLayout, MP) end)
        if MP:Get("remember") and lastMap then
            local id = lastMap
            C_Timer.After(0, function() WorldMapFrame:SetMapID(id) end)
        end
    end)
    WorldMapFrame:HookScript("OnHide", function()
        if WorldMapFrame.GetMapID then lastMap = WorldMapFrame:GetMapID() end
        WorldMapFrame:SetAlpha(1)
    end)
    WorldMapFrame:HookScript("OnUpdate", FadeTick)
    if WorldMapFrame.Maximize then
        hooksecurefunc(WorldMapFrame, "Maximize", function() UpdateBar(); MP:ApplyLayout() end)
        hooksecurefunc(WorldMapFrame, "Minimize", function() UpdateBar(); MP:ApplyLayout() end)
    end
end

---------------------------------------------------------------------------
-- Minimap mouse-wheel zoom
---------------------------------------------------------------------------
local wheelHooked = false
local function HookMinimapWheel()
    if wheelHooked or not Minimap then return end
    wheelHooked = true
    Minimap:EnableMouseWheel(true)
    Minimap:HookScript("OnMouseWheel", function(self, delta)
        if not (MP.enabled and MP:Get("wheelZoom")) then return end
        self:SetZoom(MP.ZoomStep(self:GetZoom(), delta, self:GetZoomLevels() - 1))
    end)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function MP:OnEnable()
    HookWorldMap()
    HookMinimapWheel()
    if OpenMapLoaded() and not self.toldOpenMap then
        self.toldOpenMap = true
        ns:Print(L.MP_OPENMAP)
    end
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if WorldMapFrame and WorldMapFrame:IsShown() then self:ApplyLayout() end
    end)
end

function MP:OnDisable()
    if WorldMapFrame then WorldMapFrame:SetAlpha(1) end
    UpdateBar()
end

function MP:OnSettingChanged(key)
    if key == "scale" or key == "move" then self:ApplyLayout() end
    UpdateBar()
end
