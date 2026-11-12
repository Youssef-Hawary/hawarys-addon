-- Hawary's Addon: Discovery – your own world-map layer (Overwolf-map / RareScanner /
-- GatherMate2 ideas, done the safe way):
--   * rares you target or mouse over (out of combat), and rares Blizzard shows on your minimap
--   * herbs, ore, chests and other objects recorded WHEN YOU gather/open them
-- Forever blocks reading minimap herb/ore dots, so we never try.
local _, ns = ...
local L, T, W, A, M = ns.L, ns.Theme, ns.W, ns.AdventureData, ns.MarketData

local Discovery = ns:NewModule("discovery", {
    title = L.MOD_DISCOVERY,
    desc = L.MOD_DISCOVERY_DESC,
    order = 8,
    defaults = { rareAlert = true, rareSound = true, nodes = true, pins = true, showRares = true, showNodes = true },
})

Discovery.options = {
    { type = "toggle", key = "rareAlert", label = L.DISC_RAREALERT, desc = L.DISC_RAREALERT_DESC },
    { type = "toggle", key = "rareSound", label = L.DISC_RARESOUND, desc = L.DISC_RARESOUND_DESC, parent = "rareAlert" },
    { type = "toggle", key = "nodes", label = L.DISC_NODES, desc = L.DISC_NODES_DESC },
    { type = "toggle", key = "pins", label = L.DISC_PINS, desc = L.DISC_PINS_DESC },
    { type = "toggle", key = "showRares", label = L.DISC_SHOWRARES, desc = L.DISC_SHOWRARES_DESC, parent = "pins" },
    { type = "toggle", key = "showNodes", label = L.DISC_SHOWNODES, desc = L.DISC_SHOWNODES_DESC, parent = "pins" },
}

local NODE_COLORS = {
    { 0.29, 0.87, 0.50 }, { 1.00, 0.62, 0.25 }, { 1.00, 0.82, 0.24 }, { 0.70, 0.55, 1.00 }, { 0.22, 0.78, 0.96 },
}
local RARE_COLOR = { 1, 0.35, 0.40 }

local function PlayerSpot()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or ns.IsSecret(x) or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

function Discovery:Store(mapID)
    ns.db.discovery[mapID] = ns.db.discovery[mapID] or {}
    return ns.db.discovery[mapID]
end

-- Stable colour per gathering spell (the page legend shows which is which)
function Discovery:SpellColor(spell)
    local spells = {}
    for _, store in pairs(ns.db.discovery) do
        for _, e in pairs(store) do
            if e.kind == "node" and e.spell then spells[e.spell] = true end
        end
    end
    for i, s in ipairs(ns.Util.sortedKeys(spells)) do
        if s == spell then return NODE_COLORS[((i - 1) % #NODE_COLORS) + 1] end
    end
    return NODE_COLORS[1]
end

---------------------------------------------------------------------------
-- Rares
---------------------------------------------------------------------------
Discovery.seenSession = {}

function Discovery:RareSeen(name, mapID, x, y)
    if not (name and mapID and x) then return end
    local _, isNew = A.AddSighting(self:Store(mapID), "rare", name, x, y, time())
    if isNew then ns:Fire("MILESTONE", "rare", name) end
    if not self.seenSession[name] then
        self.seenSession[name] = true
        if self:Get("rareAlert") then
            ns:Toast(L.DISC_RARE_TOAST, name, "star")
            if self:Get("rareSound") and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
    self:RefreshPins()
end

function Discovery:CheckUnit(unit)
    if ns.InCombat() then return end
    local c = UnitClassification(unit)
    if ns.IsSecret(c) or (c ~= "rare" and c ~= "rareelite") then return end
    local name = UnitName(unit)
    if not name or ns.IsSecret(name) then return end
    local mapID, x, y = PlayerSpot()
    self:RareSeen(name, mapID, x, y)
end

function Discovery:OnVignette(_, guid, onMinimap)
    if not onMinimap or ns.InCombat() then return end
    local info = C_VignetteInfo.GetVignetteInfo(guid)
    if not info or not info.name or ns.IsSecret(info.name) then return end
    local atlas = info.atlasName or ""
    if not (atlas:find("Kill") or atlas:find("Elite") or atlas:find("Rare")) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_VignetteInfo.GetVignettePosition(guid, mapID)
    if not pos then return end
    local x, y = pos:GetXY()
    self:RareSeen(info.name, mapID, x, y)
end

---------------------------------------------------------------------------
-- Gathering / opening objects (your own casts only)
---------------------------------------------------------------------------
function Discovery:OnCastSent(_, unit, target, castGUID, spellID)
    if unit ~= "player" or not target or target == "" or ns.IsSecret(target) then return end
    if UnitExists("target") and UnitName("target") == target then return end -- a creature, not an object
    local mapID, x, y = PlayerSpot()
    if not mapID then return end
    self.pending = { target = target, castGUID = castGUID, spellID = spellID, t = GetTime(), mapID = mapID, x = x, y = y }
end

function Discovery:OnCastSucceeded(_, unit, castGUID)
    if unit == "player" and self.pending and self.pending.castGUID == castGUID then self.pending.success = true end
end

function Discovery:OnLootOpened()
    local p = self.pending
    self.pending = nil
    if not (p and p.success and GetTime() - p.t < 8 and self:Get("nodes")) then return end
    local e = A.AddSighting(self:Store(p.mapID), "node", p.target, p.x, p.y, time())
    e.spell = C_Spell.GetSpellName(p.spellID)
    self:RefreshPins()
end

---------------------------------------------------------------------------
-- World map layer (Blizzard's own data provider + pin system, like HandyNotes)
---------------------------------------------------------------------------
-- Created at login: Blizzard_MapCanvas is load-on-demand, and the mixin is only looked up
-- when a pin is created from the XML template.
local Provider
local function SetupMapLayer()
    if Provider or not (MapCanvasPinMixin and MapCanvasDataProviderMixin and WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
    HawarysDiscoveryPinMixin = CreateFromMixins(MapCanvasPinMixin)

    function HawarysDiscoveryPinMixin:OnLoad()
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        self:SetScalingLimits(1, 1.0, 1.3)
    end

    function HawarysDiscoveryPinMixin:OnAcquired(entry)
        self.entry = entry
        self:SetPosition(entry.x, entry.y)
        local color = entry.kind == "rare" and RARE_COLOR or Discovery:SpellColor(entry.spell)
        self.Icon:SetTexture(ns.media .. (entry.kind == "rare" and "star" or "dot"))
        self.Icon:SetVertexColor(color[1], color[2], color[3])
        self.Glow:SetVertexColor(color[1], color[2], color[3], 0.45)
    end

    function HawarysDiscoveryPinMixin:OnMouseEnter()
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.name, 1, 1, 1)
        GameTooltip:AddLine(e.kind == "rare" and L.DISC_RARE or (e.spell or L.DISC_NODE), T.color("accent"))
        GameTooltip:AddLine(L.DISC_SEEN:format(e.count, M.Age(time() - (e.last or time()))), 0.68, 0.72, 0.78)
        GameTooltip:AddLine("|cff38c6f4Hawary's|r " .. L.MOD_DISCOVERY, 0.47, 0.5, 0.56)
        GameTooltip:Show()
    end

    function HawarysDiscoveryPinMixin:OnMouseLeave()
        GameTooltip:Hide()
    end

    Provider = CreateFromMixins(MapCanvasDataProviderMixin)

    function Provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate("HawarysDiscoveryPinTemplate")
    end

    function Provider:RefreshAllData()
        self:RemoveAllData()
        if not (Discovery.enabled and Discovery:Get("pins")) then return end
        local mapID = self:GetMap():GetMapID()
        local store = mapID and ns.db.discovery[mapID]
        if not store then return end
        for _, e in pairs(store) do
            if (e.kind == "rare" and Discovery:Get("showRares")) or (e.kind == "node" and Discovery:Get("showNodes")) then
                self:GetMap():AcquirePin("HawarysDiscoveryPinTemplate", e)
            end
        end
    end
    WorldMapFrame:AddDataProvider(Provider)
    Discovery.providerAdded = true
end

function Discovery:RefreshPins()
    if Provider and WorldMapFrame:IsShown() then Provider:RefreshAllData() end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Discovery:Totals()
    local rares, nodes, recent = 0, 0, {}
    for mapID, store in pairs(ns.db.discovery) do
        for _, e in pairs(store) do
            if e.kind == "rare" then rares = rares + 1 else nodes = nodes + 1 end
            recent[#recent + 1] = { e = e, mapID = mapID }
        end
    end
    table.sort(recent, function(a, b) return (a.e.last or 0) > (b.e.last or 0) end)
    return rares, nodes, recent
end

function Discovery:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 74)
    local rares = W.Label(card, "", "number", "accent")
    rares:SetPoint("TOPLEFT", 18, -14)
    W.Label(card, L.DISC_RARES_FOUND, "small", "text3"):SetPoint("TOPLEFT", rares, "BOTTOMLEFT", 0, -4)
    local nodes = W.Label(card, "", "number", "text")
    nodes:SetPoint("TOPLEFT", width / 2, -14)
    W.Label(card, L.DISC_NODES_FOUND, "small", "text3"):SetPoint("TOPLEFT", nodes, "BOTTOMLEFT", 0, -4)
    y = y - 74 - 16
    y = ns:BuildOptions(self, content, width, y)

    local listTop = y
    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", 0, y)
    list:SetWidth(width)
    list.title = W.Label(list, L.DISC_RECENT, "h2", "accent")
    list.title:SetPoint("TOPLEFT")
    list.rows = {}
    function list:Refresh()
        local r, n, recent = Discovery:Totals()
        rares:SetText(r)
        nodes:SetText(n)
        for _, row in ipairs(self.rows) do row:Hide() end
        local ly = -26
        if #recent == 0 then
            self.emptyLabel = self.emptyLabel or W.Label(self, L.DISC_EMPTY, "small", "text3")
            self.emptyLabel:SetPoint("TOPLEFT", 0, ly)
            self.emptyLabel:SetWidth(width)
            self.emptyLabel:SetWordWrap(true)
            self.emptyLabel:Show()
            ly = ly - self.emptyLabel:GetStringHeight() - 6
        elseif self.emptyLabel then
            self.emptyLabel:Hide()
        end
        for i = 1, math.min(#recent, 15) do
            local item = recent[i]
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, self)
                row:SetHeight(22)
                row.bg = T.Shape(row, "round_sm", "card", "BACKGROUND")
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(14, 14)
                row.icon:SetPoint("LEFT", 8, 0)
                row.name = W.Label(row, "", "small", "text")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.where = W.Label(row, "", "small", "text3", "RIGHT")
                row.where:SetPoint("RIGHT", -8, 0)
                self.rows[i] = row
            end
            local e = item.e
            local color = e.kind == "rare" and RARE_COLOR or Discovery:SpellColor(e.spell)
            row.icon:SetTexture(ns.media .. (e.kind == "rare" and "star" or "dot"))
            row.icon:SetVertexColor(color[1], color[2], color[3])
            row.name:SetText(e.name .. "  |cff77808f" .. (e.kind == "rare" and L.DISC_RARE or (e.spell or "")) .. "|r")
            local mapInfo = C_Map.GetMapInfo(item.mapID)
            row.where:SetText(string.format("%s  %.1f, %.1f  ·  %s", mapInfo and mapInfo.name or "?", e.x * 100, e.y * 100, M.Age(time() - (e.last or time()))))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, ly)
            row:SetPoint("TOPRIGHT", 0, ly)
            row:Show()
            ly = ly - 26
        end
        self:SetHeight(-ly)
        content:SetHeight(-listTop - ly + 20)
        return ly
    end
    content:HookScript("OnShow", function() list:Refresh() end)
    return listTop + list:Refresh()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Discovery:OnEnable()
    SetupMapLayer()
    self:RegisterEvent("ADDON_LOADED", function() SetupMapLayer() end) -- in case the map loads later
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function() self:CheckUnit("target") end)
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() self:CheckUnit("mouseover") end)
    self:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", "OnVignette")
    self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnCastSent")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnCastSucceeded")
    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RefreshPins()
end

function Discovery:OnDisable()
    self:RefreshPins()
end

function Discovery:OnSettingChanged()
    self:RefreshPins()
end
