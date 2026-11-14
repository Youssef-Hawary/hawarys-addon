-- Hawary's Addon: DPS Meter (Details! / Skada style window)
-- Reads ONLY Blizzard's own damage meter data (C_DamageMeter), the same numbers the built-in
-- meter shows. No combat log, no automation. In combat the numbers are "secret": we only pass
-- them straight to the game's own text and bar functions (AbbreviateLargeNumbers, SetText,
-- StatusBar:SetValue), never compare or do math on them.
local _, ns = ...
local L, T, W = ns.L, ns.Theme, ns.W

local Meter = ns:NewModule("meter", {
    title = L.MOD_METER,
    desc = L.MOD_METER_DESC,
    order = 21,
    defaults = { show = true, mode = 1, rows = 8, width = 250, rowHeight = 18, alpha = 0.9,
        onlyInGroup = false, locked = false, pos = {} },
})

-- Display modes, in the order the arrows cycle through them
Meter.MODES = {
    { type = "DamageDone", label = L.METER_DAMAGE, perSec = true },
    { type = "Dps", label = L.METER_DPS },
    { type = "HealingDone", label = L.METER_HEALING, perSec = true },
    { type = "Hps", label = L.METER_HPS },
    { type = "Absorbs", label = L.METER_ABSORBS },
    { type = "DamageTaken", label = L.METER_TAKEN },
    { type = "AvoidableDamageTaken", label = L.METER_AVOIDABLE },
    { type = "Interrupts", label = L.METER_INTERRUPTS, count = true },
    { type = "Dispels", label = L.METER_DISPELS, count = true },
    { type = "Deaths", label = L.METER_DEATHS, count = true },
    { type = "EnemyDamageTaken", label = L.METER_ENEMY },
}

Meter.options = {
    { type = "toggle", key = "show", label = L.METER_SHOW, desc = L.METER_SHOW_DESC },
    { type = "toggle", key = "onlyInGroup", label = L.METER_GROUP, desc = L.METER_GROUP_DESC },
    { type = "slider", key = "rows", label = L.METER_ROWS, desc = L.METER_ROWS_DESC, min = 3, max = 25, step = 1 },
    { type = "slider", key = "rowHeight", label = L.METER_ROWH, desc = L.METER_ROWH_DESC, min = 14, max = 28, step = 1 },
    { type = "slider", key = "alpha", label = L.METER_ALPHA, desc = L.METER_ALPHA_DESC, min = 0.3, max = 1, step = 0.05, format = "%.2f" },
    { type = "toggle", key = "locked", label = L.METER_LOCK, desc = L.METER_LOCK_DESC },
    { type = "button", label = L.METER_RESET, desc = L.METER_RESET_DESC, buttonText = L.RESET, kind = "danger",
      onClick = function() Meter:ResetData() end },
}

local frame
local rows = {}
local view = { segment = "current", sessionID = nil, offset = 0, source = nil }

-- Pure: next index in a list, wrapping around. Unit-tested.
function Meter.Cycle(i, n, step)
    i = (i or 1) + (step or 1)
    if i > n then i = 1 elseif i < 1 then i = n end
    return i
end

-- Pure: clamp the scroll offset so the window never scrolls past the list. Unit-tested.
function Meter.ClampOffset(total, offset, visible)
    local maxOffset = math.max(0, total - visible)
    if offset > maxOffset then return maxOffset end
    if offset < 0 then return 0 end
    return offset
end

local function Mode() return Meter.MODES[Meter:Get("mode")] or Meter.MODES[1] end
local function MeterType(name) return Enum.DamageMeterType and Enum.DamageMeterType[name] end

function Meter:Available()
    if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then return false, L.METER_NO_API end
    return C_DamageMeter.IsDamageMeterAvailable()
end

local function SessionType()
    return view.segment == "overall" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
end

-- The combat session for the chosen segment and mode (nil if none yet)
function Meter:Session()
    local t = MeterType(Mode().type)
    if not t then return nil end
    if view.segment == "id" and view.sessionID then
        return C_DamageMeter.GetCombatSessionFromID(view.sessionID, t)
    end
    return C_DamageMeter.GetCombatSessionFromType(SessionType(), t)
end

local function SourceSession()
    local t = MeterType(Mode().type)
    local src = view.source
    if not (t and src) then return nil end
    if view.segment == "id" and view.sessionID then
        return C_DamageMeter.GetCombatSessionSourceFromID(view.sessionID, t, src.guid, src.creature)
    end
    return C_DamageMeter.GetCombatSessionSourceFromType(SessionType(), t, src.guid, src.creature)
end

function Meter:SegmentLabel()
    if view.segment == "overall" then return L.METER_OVERALL end
    if view.segment == "id" and view.sessionName then return view.sessionName end
    return L.METER_CURRENT
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function ClassColor(classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
    return T.color("accent")
end

local function MakeRow(i)
    local r = CreateFrame("Button", nil, frame.body)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.04)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetAllPoints()
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    r.bar:SetMinMaxValues(0, 1)
    r.icon = r.bar:CreateTexture(nil, "OVERLAY")
    r.icon:SetPoint("LEFT", 2, 0)
    r.rank = W.Label(r.bar, "", "small", "text3")
    r.name = W.Label(r.bar, "", "small", "text")
    r.value = W.Label(r.bar, "", "small", "text", "RIGHT")
    r.value:SetPoint("RIGHT", -4, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
    r:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then Meter:Back() else Meter:OpenSource(self.entry) end
    end)
    r:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.10)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(Mode().label)
        GameTooltip:AddLine(view.source and L.METER_TIP_BACK or L.METER_TIP_ROW, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.04); GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function LayoutRows()
    local h = Meter:Get("rowHeight")
    local n = Meter:Get("rows")
    for i = 1, math.max(n, #rows) do
        local r = rows[i] or MakeRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * (h + 1))
        r:SetPoint("RIGHT", 0, 0)
        r:SetHeight(h)
        r.icon:SetSize(h - 2, h - 2)
        r.rank:ClearAllPoints()
        r.rank:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.name:SetPoint("LEFT", r.rank, "RIGHT", 4, 0)
        if i > n then r:Hide() end
    end
    frame:SetHeight(32 + n * (h + 1) + 4)
end

local function HeaderButton(parent, text, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.text = W.Label(b, text, "h2", "text3", "CENTER")
    b.text:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        T.TextColor(self.text, "accent")
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) T.TextColor(self.text, "text3"); GameTooltip:Hide() end)
    return b
end

function Meter:Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "HawarysAddonMeter", UIParent)
    frame:SetSize(self:Get("width"), 200)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(160, 80, 600, 800)
    frame:EnableMouse(true)
    local pos = self:Get("pos")
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("BOTTOMRIGHT", -260, 180)
    end
    frame.bg = T.Shape(frame, "round_sm", "window", "BACKGROUND", 0)
    frame.border = T.Shape(frame, "round_sm_line", "line", "BORDER", 0)

    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(26)
    head:EnableMouse(true)
    head:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and not Meter:Get("locked") then frame:StartMoving() end
    end)
    head:SetScript("OnMouseUp", function(_, btn)
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint(1)
        Meter:DB().pos = { point = p, relPoint = rp, x = x, y = y }
        if btn == "RightButton" then Meter:SegmentMenu(head) end
    end)
    head:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.MOD_METER)
        GameTooltip:AddLine(L.METER_TIP_HEAD, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.logo = head:CreateTexture(nil, "ARTWORK")
    frame.logo:SetTexture(ns.media .. "logo")
    frame.logo:SetSize(16, 16)
    frame.logo:SetPoint("LEFT", 6, 0)
    frame.title = W.Label(head, "", "small", "text")
    frame.title:SetPoint("LEFT", frame.logo, "RIGHT", 5, 0)
    frame.title:SetPoint("RIGHT", -98, 0)
    frame.title:SetWordWrap(false)

    local close = HeaderButton(head, "x", L.CLOSE, function() Meter:Set("show", false) end)
    close:SetPoint("RIGHT", -4, 0)
    local reset = HeaderButton(head, "R", L.METER_RESET, function() Meter:ResetData() end)
    reset:SetPoint("RIGHT", close, "LEFT", -2, 0)
    local report = HeaderButton(head, "»", L.METER_REPORT, function() Meter:Report() end)
    report:SetPoint("RIGHT", reset, "LEFT", -2, 0)
    local nextB = HeaderButton(head, ">", L.METER_NEXT, function() Meter:SetMode(1) end)
    nextB:SetPoint("RIGHT", report, "LEFT", -2, 0)
    local prevB = HeaderButton(head, "<", L.METER_PREV, function() Meter:SetMode(-1) end)
    prevB:SetPoint("RIGHT", nextB, "LEFT", 0, 0)

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", 4, -28)
    frame.body:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.body:EnableMouseWheel(true)
    frame.body:SetScript("OnMouseWheel", function(_, delta)
        view.offset = view.offset - delta
        Meter:Refresh()
    end)

    frame.empty = W.Label(frame.body, "", "small", "text3", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 6, -8)
    frame.empty:SetPoint("TOPRIGHT", -6, -8)
    frame.empty:SetWordWrap(true)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() if not Meter:Get("locked") then frame:StartSizing("RIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        Meter:DB().width = math.floor(frame:GetWidth() + 0.5)
    end)

    LayoutRows()
    frame:SetAlpha(self:Get("alpha"))
    return frame
end

function Meter:SegmentMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.METER_SEGMENT)
        root:CreateRadio(L.METER_CURRENT, function() return view.segment == "current" end,
            function() view.segment, view.sessionID, view.source = "current", nil, nil; Meter:Refresh() end)
        root:CreateRadio(L.METER_OVERALL, function() return view.segment == "overall" end,
            function() view.segment, view.sessionID, view.source = "overall", nil, nil; Meter:Refresh() end)
        local list = C_DamageMeter.GetAvailableCombatSessions() or {}
        for i = #list, math.max(1, #list - 9), -1 do
            local s = list[i]
            local label = s.name or ("#" .. tostring(s.sessionID))
            if not ns.IsSecret(s.durationSeconds) and s.durationSeconds then
                label = label .. "  [" .. SecondsToClock(s.durationSeconds) .. "]"
            end
            root:CreateRadio(label, function() return view.segment == "id" and view.sessionID == s.sessionID end,
                function()
                    view.segment, view.sessionID, view.sessionName, view.source = "id", s.sessionID, label, nil
                    Meter:Refresh()
                end)
        end
        root:CreateDivider()
        root:CreateTitle(L.METER_MODE)
        for i, m in ipairs(Meter.MODES) do
            root:CreateRadio(m.label, function() return Meter:Get("mode") == i end, function() Meter:Set("mode", i) end)
        end
    end)
end

function Meter:SetMode(step)
    self:Set("mode", Meter.Cycle(self:Get("mode"), #Meter.MODES, step))
end

function Meter:Back()
    if view.source then view.source = nil; view.offset = 0; self:Refresh() end
end

-- Spell breakdown for one player. Only out of combat: the player id is secret in combat.
function Meter:OpenSource(entry)
    if not entry or view.source then return end
    if ns.IsSecret(entry.sourceGUID) or ns.IsSecret(entry.name) then
        ns:Print(L.METER_AFTER_COMBAT)
        return
    end
    view.source = { guid = entry.sourceGUID, creature = entry.sourceCreatureID, name = entry.name, class = entry.classFilename }
    view.offset = 0
    self:Refresh()
end

-- In combat these numbers are secret: never test them (no `or`, `if`, `==`), only hand them to
-- the game's own functions, which accept secret values.
local function SetValueText(fs, value, perSec, showPerSec)
    if showPerSec then
        fs:SetFormattedText("%s (%s)", AbbreviateLargeNumbers(value), AbbreviateLargeNumbers(perSec))
    else
        fs:SetText(AbbreviateLargeNumbers(value))
    end
end

local function Plain(v) return not ns.IsSecret(v) and v ~= nil end

local function SpellName(e)
    if Plain(e.spellID) and e.spellID ~= 0 then return C_Spell.GetSpellName(e.spellID) or "?" end
    return e.creatureName
end

function Meter:Refresh()
    if not (frame and frame:IsShown()) then return end
    local mode = Mode()
    local ok, why = self:Available()
    local list, maxAmount = {}, 1
    if ok then
        local s
        if view.source then s = SourceSession() else s = self:Session() end
        if s then
            list = (view.source and s.combatSpells or s.combatSources) or {}
            maxAmount = s.maxAmount
        end
    end

    if view.source then
        frame.title:SetText((view.source.name or "?") .. " · " .. mode.label)
    else
        frame.title:SetText(mode.label .. " · " .. self:SegmentLabel())
    end

    local visible = self:Get("rows")
    view.offset = Meter.ClampOffset(#list, view.offset, visible)
    local shown = 0
    for i = 1, visible do
        local r = rows[i]
        local e = list[view.offset + i]
        if r and e then
            shown = shown + 1
            r.entry = e
            r.rank:SetText((view.offset + i) .. ".")
            -- maxAmount / totalAmount / name may be secret: passed straight through, never tested
            r.bar:SetMinMaxValues(0, maxAmount)
            r.bar:SetValue(e.totalAmount)
            if view.source then
                r.name:SetText(SpellName(e))
                local tex = Plain(e.spellID) and e.spellID ~= 0 and C_Spell.GetSpellTexture(e.spellID) or 134400
                r.icon:SetTexture(tex)
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local cr, cg, cb = ClassColor(view.source.class)
                r.bar:SetStatusBarColor(cr, cg, cb, 0.55)
            else
                r.name:SetText(e.name)
                local cr, cg, cb = ClassColor(e.classFilename)                      -- NeverSecret
                r.bar:SetStatusBarColor(cr, cg, cb, e.isLocalPlayer and 0.85 or 0.6) -- NeverSecret
                r.icon:SetTexture(e.specIconID)
                r.icon:SetTexCoord(0, 1, 0, 1)
            end
            SetValueText(r.value, e.totalAmount, e.amountPerSecond, mode.perSec and not mode.count)
            r:Show()
        elseif r then
            r.entry = nil
            r:Hide()
        end
    end
    if shown == 0 then
        local text = ok and L.METER_EMPTY or L.METER_UNAVAILABLE
        if not ok and type(why) == "string" and why ~= "" then text = text .. "\n" .. why end
        frame.empty:SetText(text)
        frame.empty:Show()
    else
        frame.empty:Hide()
    end
end

function Meter:ResetData()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then C_DamageMeter.ResetAllCombatSessions() end
    view.segment, view.sessionID, view.source, view.offset = "current", nil, nil, 0
    self:Refresh()
end

-- Post the top 5 to group chat (or /say when solo). Out of combat only: in combat the numbers are secret.
function Meter:Report()
    if ns.InCombat() then ns:Print(L.METER_AFTER_COMBAT); return end
    local s = self:Session()
    local list = s and s.combatSources
    if not list or #list == 0 then ns:Print(L.METER_EMPTY); return end
    local channel = UnitInRaid("player") and "RAID" or (UnitInParty("player") and "PARTY" or "SAY")
    local mode = Mode()
    local lines = { "Hawary's Addon – " .. mode.label .. " (" .. self:SegmentLabel() .. ")" }
    for i = 1, math.min(5, #list) do
        local e = list[i]
        if ns.IsSecret(e.totalAmount) or ns.IsSecret(e.name) then ns:Print(L.METER_AFTER_COMBAT); return end
        local line = string.format("%d. %s  %s", i, e.name or "?", AbbreviateLargeNumbers(e.totalAmount or 0))
        if mode.perSec and e.amountPerSecond and not ns.IsSecret(e.amountPerSecond) then
            line = line .. " (" .. AbbreviateLargeNumbers(e.amountPerSecond) .. ")"
        end
        lines[#lines + 1] = line
    end
    for _, line in ipairs(lines) do C_ChatInfo.SendChatMessage(line, channel) end
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
function Meter:UpdateShown()
    local want = self.enabled and self:Get("show") and not (self:Get("onlyInGroup") and not UnitInParty("player"))
    if want then
        self:Build()
        frame:SetWidth(self:Get("width"))
        frame:Show()
        self:Refresh()
    elseif frame then
        frame:Hide()
    end
end

function Meter:Toggle()
    if not self.enabled then ns:SetModuleEnabled("meter", true) end
    self:Set("show", not self:Get("show"))
end

local pending = false
local function Throttled()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = false; ns.Safe(Meter.Refresh, Meter) end)
end

function Meter:OnInitialize()
    ns:RegisterSlash("dps", L.METER_SLASH, function() Meter:Toggle() end)
end

function Meter:OnEnable()
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", Throttled)
    self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", Throttled)
    self:RegisterEvent("DAMAGE_METER_RESET", function() view.sessionID, view.source = nil, nil; Throttled() end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateShown")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", Throttled)
    self:UpdateShown()
end

function Meter:OnDisable()
    if frame then frame:Hide() end
end

function Meter:OnSettingChanged(key)
    if key == "rows" or key == "rowHeight" then
        if frame then LayoutRows() end
    elseif key == "alpha" then
        if frame then frame:SetAlpha(self:Get("alpha")) end
    elseif key == "mode" then
        view.source, view.offset = nil, 0
    end
    self:UpdateShown()
end
