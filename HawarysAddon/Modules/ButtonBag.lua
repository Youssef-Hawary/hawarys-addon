-- Hawary's Addon: Minimap Button Bag – tucks other addons' minimap buttons into one
-- drawer (middle-click or Shift-click the Hawary minimap button). Only addon buttons
-- made with LibDBIcon or named "...MinimapButton"; Blizzard's own minimap buttons stay.
local _, ns = ...
local L, T, W = ns.L, ns.Theme, ns.W

local BB = ns:NewModule("buttonbag", {
    title = L.MOD_BUTTONBAG,
    desc = L.MOD_BUTTONBAG_DESC,
    order = 19,
    defaults = { perRow = 6 },
})

BB.options = {
    { type = "slider", key = "perRow", label = L.BB_PERROW, desc = L.BB_PERROW_DESC, min = 3, max = 10, step = 1 },
    { type = "button", label = L.BB_OPEN, desc = L.BB_OPEN_DESC, buttonText = L.OPEN, onClick = function() BB:Toggle() end },
}

-- Pure: should a minimap child with this name be collected? Unit-tested.
function BB.Wants(name)
    if type(name) ~= "string" then return false end
    if name == "HawarysAddonMinimapButton" then return false end
    if name:match("^LibDBIcon10_") then return true end
    if name:match("^MiniMap") or name:match("^Minimap") or name:match("^GameTime") or name:match("^QueueStatus")
        or name:match("^ExpansionLanding") or name:match("^AddonCompartment") or name:match("^TimeManager") then
        return false
    end
    return name:match("[Mm]inimap_?[Bb]utton$") ~= nil
end

local drawer
local collected, order = {}, {}
local placing = false

local function Layout()
    if not drawer then return end
    local per = BB:Get("perRow")
    placing = true
    for i, b in ipairs(order) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", drawer, "TOPLEFT", 8 + ((i - 1) % per) * 34, -8 - math.floor((i - 1) / per) * 34)
    end
    placing = false
    local rows = math.max(1, math.ceil(#order / per))
    drawer:SetSize(16 + math.min(#order, per) * 34, 16 + rows * 34)
    drawer.empty:SetShown(#order == 0)
    if #order == 0 then drawer:SetSize(200, 40) end
end

local function Build()
    drawer = CreateFrame("Frame", "HawarysButtonBag", UIParent)
    drawer:SetFrameStrata("HIGH")
    drawer:SetClampedToScreen(true)
    drawer.bg = T.Shape(drawer, "round", T.native() and { 0, 0, 0, 0.7 } or "window", "BACKGROUND")
    drawer.border = T.Shape(drawer, "round_line", "accent2", "BORDER")
    drawer.empty = W.Label(drawer, L.BB_EMPTY, "small", "text3", "CENTER")
    drawer.empty:SetPoint("CENTER")
    drawer:Hide()
    tinsert(UISpecialFrames, "HawarysButtonBag")
end

function BB:Collect()
    if not drawer then Build() end
    if ns.InCombat() then return end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        local name = child.GetName and child:GetName()
        if not collected[child] and BB.Wants(name) and child:IsObjectType("Button") then
            collected[child] = true
            order[#order + 1] = child
            child:SetParent(drawer)
            child:SetFrameStrata("HIGH")
            -- LibDBIcon moves its buttons back around the minimap; keep them in the drawer
            hooksecurefunc(child, "SetPoint", function() if not placing then Layout() end end)
        end
    end
    table.sort(order, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
    Layout()
end

function BB:Toggle(anchor)
    if not drawer then Build() end
    if drawer:IsShown() then drawer:Hide(); return end
    self:Collect()
    drawer:ClearAllPoints()
    if anchor then
        drawer:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
    else
        drawer:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 0, -10)
    end
    drawer:Show()
end

function BB:OnEnable()
    C_Timer.After(5, function() if BB.enabled then ns.Safe(BB.Collect, BB) end end)
    C_Timer.After(20, function() if BB.enabled then ns.Safe(BB.Collect, BB) end end) -- late addons
end

function BB:OnDisable()
    if drawer then drawer:Hide() end
    if #order > 0 then ns:Print(L.BB_RELOAD) end
end

function BB:OnSettingChanged() Layout() end

ns:On("BUTTONBAG_TOGGLE", function(anchor)
    if BB.enabled then BB:Toggle(anchor) else ns:Print(L.BB_OFF) end
end)
