-- Hawary's Addon: Flight Path Finder – the nearest flight master you know, the flight
-- paths on this continent you haven't found yet, and a map pin to any of them.
-- Read only: it uses Blizzard's own flight map data and map pin.
local _, ns = ...
local L, T, W = ns.L, ns.Theme, ns.W

local TR = ns:NewModule("travel", {
    title = L.MOD_TRAVEL,
    desc = L.MOD_TRAVEL_DESC,
    order = 18,
    defaults = { zoneAlert = true },
})

TR.options = {
    { type = "toggle", key = "zoneAlert", label = L.TRAVEL_ALERT, desc = L.TRAVEL_ALERT_DESC },
}

local function Continent(mapID)
    local guard = 0
    while mapID and guard < 10 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then return nil end
        if info.mapType == Enum.UIMapType.Continent then return mapID end
        mapID = info.parentMapID
        guard = guard + 1
    end
    return nil
end
TR.Continent = Continent

-- Pure: sort nodes by distance (yards) from px, py on a map of size w x h. Unit-tested.
function TR.Rank(nodes, px, py, w, h)
    local out = {}
    for _, n in ipairs(nodes) do
        local dx, dy = (n.x - px) * w, (n.y - py) * h
        out[#out + 1] = { name = n.name, x = n.x, y = n.y, known = n.known, yards = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5) }
    end
    table.sort(out, function(a, b) return a.yards < b.yards end)
    return out
end

function TR:Nodes()
    local here = C_Map.GetBestMapForUnit("player")
    local cont = here and Continent(here)
    if not cont then return nil end
    local pos = C_Map.GetPlayerMapPosition(cont, "player")
    if not pos then return nil end
    local px, py = pos:GetXY()
    if not px or ns.IsSecret(px) then return nil end
    local myFaction = UnitFactionGroup("player") == "Horde" and Enum.FlightPathFaction.Horde or Enum.FlightPathFaction.Alliance
    local nodes = {}
    for _, n in ipairs(C_TaxiMap.GetTaxiNodesForMap(cont) or {}) do
        if n.position and (n.faction == Enum.FlightPathFaction.Neutral or n.faction == myFaction) then
            local x, y = n.position:GetXY()
            nodes[#nodes + 1] = { name = n.name, x = x, y = y, known = not n.isUndiscovered }
        end
    end
    local w, h = C_Map.GetMapWorldSize(cont)
    if not w or w == 0 then w, h = 1000, 1000 end
    return TR.Rank(nodes, px, py, w, h), cont
end

function TR:PointTo(node, mapID)
    if not (node and mapID) then return end
    ns:RunOutOfCombat("travel-pin", function()
        if C_Map.CanSetUserWaypointOnMap(mapID) then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, node.x, node.y))
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    ns:Print(L.TRAVEL_POINTING:format(node.name, node.yards))
end

function TR:Nearest()
    local list, cont = self:Nodes()
    if not list then ns:Print(L.TRAVEL_NO_DATA); return end
    for _, n in ipairs(list) do
        if n.known then self:PointTo(n, cont); return end
    end
    ns:Print(L.TRAVEL_NONE_KNOWN)
end

function TR:OnZone()
    if not self:Get("zoneAlert") then return end
    local zone = C_Map.GetBestMapForUnit("player")
    if not zone or zone == self.lastZone then return end
    self.lastZone = zone
    local list = self:Nodes()
    if not list then return end
    for _, n in ipairs(list) do
        if not n.known and n.yards < 1500 then
            ns:Toast(L.MOD_TRAVEL, L.TRAVEL_NEW_NEARBY:format(n.name, n.yards), "Interface\\Icons\\Ability_Mount_Wyvern_01")
            return
        end
    end
end

function TR:BuildPage(content, width, y)
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetWidth(width)
    local head = W.Label(card, L.TRAVEL_TITLE, "h2", "text")
    head:SetPoint("TOPLEFT", 16, -14)
    local near = W.Button(card, L.TRAVEL_NEAREST, "primary", 180)
    near:SetPoint("TOPRIGHT", -14, -10)
    near:SetScript("OnClick", function() TR:Nearest() end)
    local rows = {}
    local function fill()
        for _, r in ipairs(rows) do r:Hide() end
        local list, cont = TR:Nodes()
        local yy = -46
        if not list then
            rows.msg = rows.msg or W.Label(card, "", "small", "text3")
            rows.msg:SetText(L.TRAVEL_NO_DATA); rows.msg:SetPoint("TOPLEFT", 16, yy); rows.msg:Show()
            card:SetHeight(80)
            return
        elseif rows.msg then rows.msg:Hide() end
        for i = 1, math.min(#list, 14) do
            local n = list[i]
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, card)
                r:SetHeight(24)
                r.name = W.Label(r, "", "body", "text")
                r.name:SetPoint("LEFT", 0, 0)
                r.dist = W.Label(r, "", "small", "text2")
                r.dist:SetPoint("RIGHT", -96, 0)
                r.go = W.Button(r, L.TRAVEL_PIN, "secondary", 84, 20)
                r.go:SetPoint("RIGHT", 0, 0)
                rows[i] = r
            end
            r:SetPoint("TOPLEFT", 16, yy); r:SetPoint("RIGHT", card, "RIGHT", -16, 0)
            r.name:SetText(n.name .. "  " .. (n.known and ("|cff" .. T.hex("good") .. L.TRAVEL_KNOWN .. "|r")
                or ("|cff" .. T.hex("warn") .. L.TRAVEL_UNKNOWN .. "|r")))
            r.dist:SetText(n.yards .. " yd")
            r.go:SetScript("OnClick", function() TR:PointTo(n, cont) end)
            r:Show()
            yy = yy - 26
        end
        card:SetHeight(-yy + 10)
    end
    card.Refresh = fill
    fill()
    content:SetScript("OnShow", fill)
    return y - 420
end

function TR:OnEnable()
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(2, function() ns.Safe(TR.OnZone, TR) end) end)
end

ns:On("TRAVEL_NEAREST", function() if TR.enabled then TR:Nearest() end end)
