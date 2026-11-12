-- Hawary's Addon: Journey UI – floating guide window (Zygor style), direction arrow
-- (TomTom style) and the Journey page in the main window.
local _, ns = ...
local L, T, W, J = ns.L, ns.Theme, ns.W, ns.JourneyData
local Journey = ns.modules.journey

local WIDTH = 304
local frame, arrow, ticker
local collapsed = false

local GOLD = { 1, 0.82, 0.24, 1 }
local ICONS = {
    accept = { "quest_new", GOLD }, turnin = { "quest_done", GOLD }, complete = { "dot", "accent" },
    ["goto"] = { "pin", "accent" }, level = { "star", "accent" }, train = { "book", "text2" },
    hearth = { "pin", "text2" }, fly = { "pin", "text2" }, note = { "dot", "text3" },
}

local function QuestName(step)
    if step.text and step.text ~= "" then return step.text end
    if step.questID then
        return C_QuestLog.GetTitleForQuestID(step.questID) or ("#" .. step.questID)
    end
    return ""
end

local function StepTitle(step)
    local t, name = step.type, QuestName(step)
    if t == "accept" then return L.STEP_ACCEPT:format(name)
    elseif t == "turnin" then return L.STEP_TURNIN:format(name)
    elseif t == "complete" then return name
    elseif t == "goto" then return L.STEP_GOTO:format(name ~= "" and name or string.format("%.1f, %.1f", step.x, step.y))
    elseif t == "level" then return L.STEP_LEVEL:format(step.level) .. (name ~= "" and ("  ·  " .. name) or "")
    elseif t == "train" then return name ~= "" and name or L.STEP_TRAIN
    elseif t == "hearth" then return L.STEP_HEARTH:format(name)
    elseif t == "fly" then return L.STEP_FLY:format(name)
    end
    return name
end

local CHECK = "|T" .. ns.media .. "check:12:12:0:0:32:32:0:32:0:32:74:222:128|t "
local BULLET = "|T" .. ns.media .. "dot:10:10:0:0:32:32:0:32:0:32:119:128:143|t "

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function IconButton(parent, icon, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b.icon = W.Icon(b, icon, 14, "text3")
    b.icon:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        T.Tint(self.icon, "accent")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) T.Tint(self.icon, "text3"); GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    return b
end

local function SavePos(f, key)
    local point, _, relPoint, x, y = f:GetPoint(1)
    Journey:DB()[key] = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePos(f, key, ...)
    local p = Journey:DB()[key]
    f:ClearAllPoints()
    if p and p.point then
        f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        f:SetPoint(...)
    end
end

local function Draggable(f, handle, key)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() if not Journey:Get("lock") then f:StartMoving() end end)
    handle:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePos(f, key) end)
end

---------------------------------------------------------------------------
-- Guide window
---------------------------------------------------------------------------
local function BuildFrame()
    frame = CreateFrame("Frame", "HawarysJourneyFrame", UIParent)
    frame:SetSize(WIDTH, 160)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    RestorePos(frame, "windowPos", "RIGHT", UIParent, "RIGHT", -60, 120)

    if T.native() then
        local border = CreateFrame("Frame", nil, frame, "DialogBorderTranslucentTemplate")
        border:SetAllPoints()
        border:SetFrameLevel(frame:GetFrameLevel())
    else
        frame.shadow = T.Shape(frame, "shadow", "shadow", "BACKGROUND", -8, true)
        frame.shadow:SetPoint("TOPLEFT", -20, 20)
        frame.shadow:SetPoint("BOTTOMRIGHT", 20, -20)
        frame.bg = T.Shape(frame, "round", "window", "BACKGROUND")
        frame.border = T.Shape(frame, "round_line", "line", "BORDER")
    end

    -- header (drag to move)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(32)
    Draggable(frame, header, "windowPos")
    frame.mark = W.Icon(header, "mark", 18)
    frame.mark:SetPoint("LEFT", 10, 0)
    frame.title = W.Label(header, L.MOD_JOURNEY:upper(), "h2", "accent")
    frame.title:SetPoint("LEFT", frame.mark, "RIGHT", 7, 0)
    frame.close = IconButton(header, "x", L.CLOSE, function() Journey:Set("window", false) end)
    frame.close:SetPoint("RIGHT", -6, 0)
    frame.collapse = IconButton(header, "chevron", L.JOURNEY_COLLAPSE, function()
        collapsed = not collapsed
        ns.Safe(ns.JourneyUI.Update)
    end)
    frame.collapse:SetPoint("RIGHT", frame.close, "LEFT", -2, 0)
    frame.open = IconButton(header, "book", L.JOURNEY_OPEN_PAGE, function() ns:OpenWindow("journey") end)
    frame.open:SetPoint("RIGHT", frame.collapse, "LEFT", -2, 0)
    frame.mode = W.Label(header, "", "small", "text3")
    frame.mode:SetPoint("LEFT", frame.title, "RIGHT", 8, 0)
    frame.mode:SetPoint("RIGHT", frame.open, "LEFT", -6, 0)
    frame.mode:SetWordWrap(false)
    local line = W.Divider(frame)
    line:SetPoint("TOPLEFT", 1, -32)
    line:SetPoint("TOPRIGHT", -1, -32)
    if T.native() then line:SetAlpha(0.5) end

    -- current step card
    local card = W.Card(frame, "card2")
    card:SetPoint("TOPLEFT", 8, -40)
    card:SetPoint("TOPRIGHT", -8, -40)
    card.bar = card:CreateTexture(nil, "ARTWORK")
    card.bar:SetColorTexture(T.color("accent"))
    card.bar:SetWidth(3)
    card.bar:SetPoint("TOPLEFT", 0, -10)
    card.bar:SetPoint("BOTTOMLEFT", 0, 10)
    card.iconBg = W.Icon(card, "circle", 28, nil, "ARTWORK")
    card.iconBg:SetPoint("TOPLEFT", 12, -10)
    card.icon = W.Icon(card, "dot", 18, nil, "OVERLAY")
    card.icon:SetPoint("CENTER", card.iconBg, "CENTER")
    card.nav = W.Icon(card, "nav", 26, "accent", "OVERLAY")
    card.nav:SetPoint("TOPRIGHT", -16, -10)
    card.dist = W.Label(card, "", "small", "accent", "CENTER")
    card.dist:SetPoint("TOP", card.nav, "BOTTOM", 0, -3)
    card.title = W.Label(card, "", "h2", "text")
    card.title:SetPoint("TOPLEFT", card.iconBg, "TOPRIGHT", 10, -1)
    card.title:SetPoint("RIGHT", card, "RIGHT", -58, 0)
    card.title:SetWordWrap(true)
    card.title:SetMaxLines(2)
    card.lines = {}
    frame.card = card

    -- upcoming steps
    frame.upcoming = {}
    for i = 1, 2 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetHeight(18)
        row.icon = W.Icon(row, "dot", 12, "text3")
        row.icon:SetPoint("LEFT", 0, 0)
        row.text = W.Label(row, "", "small", "text3")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", 0, 0)
        row.text:SetWordWrap(false)
        frame.upcoming[i] = row
    end

    -- footer
    frame.progBg = T.Shape(frame, "pill", "line", "ARTWORK", 0, true)
    frame.progBg:SetHeight(5)
    frame.progFill = T.Shape(frame, "pill", "accent", "ARTWORK", 1, true)
    frame.progFill:SetHeight(5)
    frame.progText = W.Label(frame, "", "small", "text2")
    frame.session = W.Label(frame, "", "small", "text3", "RIGHT")
    frame.back = W.Button(frame, L.JOURNEY_PREV, "ghost", 70, 22)
    frame.back:SetScript("OnClick", function() Journey:Back() end)
    frame.nextBtn = W.Button(frame, L.JOURNEY_NEXT, "secondary", 84, 22)
    frame.nextBtn:SetScript("OnClick", function() Journey:Next() end)
    W.Tooltip(frame.nextBtn, function()
        return Journey.view and Journey.view.mode == "auto" and L.JOURNEY_SKIP or L.JOURNEY_NEXT
    end, function()
        return Journey.view and Journey.view.mode == "auto" and L.JOURNEY_SKIP_DESC or L.JOURNEY_NEXT_DESC
    end)
    W.Tooltip(frame.back, function()
        return Journey.view and Journey.view.mode == "auto" and L.JOURNEY_UNSKIP or L.JOURNEY_PREV
    end, function()
        return Journey.view and Journey.view.mode == "auto" and L.JOURNEY_UNSKIP_DESC or L.JOURNEY_PREV_DESC
    end)
end

local function SetIcon(card, stepType)
    local def = ICONS[stepType] or ICONS.note
    card.icon:SetTexture(ns.media .. def[1])
    T.Tint(card.icon, def[2])
    local r, g, b = T.color("accent")
    if def[2] == GOLD then r, g, b = GOLD[1], GOLD[2], GOLD[3] end
    card.iconBg:SetVertexColor(r, g, b, 0.16)
end

local function CardLine(card, i)
    local fs = card.lines[i]
    if not fs then
        fs = W.Label(card, "", "small", "text2")
        fs:SetWordWrap(true)
        card.lines[i] = fs
    end
    return fs
end

local function Update()
    if not frame then return end
    local view = Journey.view
    if not view then return end
    local card = frame.card
    frame:SetScale(Journey:Get("scale") or 1)
    frame.mode:SetText(view.title or "")
    frame.collapse.icon:SetRotation(collapsed and -math.pi / 2 or math.pi / 2)

    -- current step
    local step = view.steps and view.steps[1]
    local lines = {}
    if view.finished then
        SetIcon(card, "level")
        card.title:SetText(L.JOURNEY_FINISHED)
        lines[1] = L.JOURNEY_FINISHED_SUB
    elseif view.empty or not step then
        SetIcon(card, "accept")
        card.title:SetText(L.JOURNEY_EMPTY)
        lines[1] = L.JOURNEY_EMPTY_SUB
    else
        SetIcon(card, step.type)
        card.title:SetText(StepTitle(step))
        if step.objectives and step.type ~= "turnin" then
            for _, o in ipairs(step.objectives) do
                lines[#lines + 1] = (o.finished and CHECK or BULLET) .. o.text
            end
        end
        if step.type == "turnin" and view.mode == "auto" then lines[#lines + 1] = L.JOURNEY_READY end
        if step.done then lines[#lines + 1] = CHECK .. L.JOURNEY_STEP_DONE end
    end
    local textWidth = WIDTH - 16 - 50 - 58
    local y = -10 - math.max(card.title:GetStringHeight(), 16) - 4
    for i, text in ipairs(lines) do
        local fs = CardLine(card, i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", card.title, "TOPLEFT", 0, y + 10)
        fs:SetWidth(textWidth)
        fs:SetText(text)
        fs:SetShown(not collapsed or i <= 1)
        if fs:IsShown() then y = y - fs:GetStringHeight() - 3 end
    end
    for i = #lines + 1, #card.lines do card.lines[i]:Hide() end
    local cardH = math.max(56, -y + 12)
    card:SetHeight(cardH)

    -- upcoming
    local fy = -40 - cardH - 8
    for i, row in ipairs(frame.upcoming) do
        local s = view.steps and view.steps[i + 1]
        if s and not collapsed then
            local def = ICONS[s.type] or ICONS.note
            row.icon:SetTexture(ns.media .. def[1])
            row.text:SetText(StepTitle(s))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 16, fy)
            row:SetPoint("TOPRIGHT", -12, fy)
            row:Show()
            fy = fy - 18
        else
            row:Hide()
        end
    end

    -- footer
    local showFooter = not collapsed
    for _, r in ipairs({ frame.progBg, frame.progFill, frame.progText, frame.session, frame.back, frame.nextBtn }) do
        r:SetShown(showFooter)
    end
    if showFooter then
        fy = fy - 6
        frame.progBg:ClearAllPoints()
        frame.progBg:SetPoint("TOPLEFT", 12, fy)
        frame.progBg:SetPoint("TOPRIGHT", -12, fy)
        frame.progFill:ClearAllPoints()
        frame.progFill:SetPoint("TOPLEFT", frame.progBg, "TOPLEFT")
        frame.progFill:SetWidth(math.max(5, (WIDTH - 24) * (view.progress or 0)))
        fy = fy - 11
        frame.progText:ClearAllPoints()
        frame.progText:SetPoint("TOPLEFT", 12, fy)
        frame.progText:SetText(view.progressText or "")
        local s = view.session
        frame.session:ClearAllPoints()
        frame.session:SetPoint("TOPRIGHT", -12, fy)
        if s and s.elapsed and s.elapsed >= 60 then
            frame.session:SetText(L.JOURNEY_SESSION:format(J.Short(s.xph), J.FormatDuration(s.ttl)))
        else
            frame.session:SetText("")
        end
        fy = fy - 20
        frame.back:ClearAllPoints()
        frame.back:SetPoint("TOPLEFT", 10, fy)
        frame.nextBtn:ClearAllPoints()
        frame.nextBtn:SetPoint("TOPRIGHT", -10, fy)
        frame.nextBtn:SetLabel(view.mode == "auto" and L.JOURNEY_SKIP or L.JOURNEY_NEXT)
        frame.back:SetLabel(view.mode == "auto" and L.JOURNEY_UNSKIP or L.JOURNEY_PREV)
        fy = fy - 22
    end
    frame:SetHeight(-fy + 10)
end

---------------------------------------------------------------------------
-- Direction arrow
---------------------------------------------------------------------------
local function BuildArrow()
    arrow = CreateFrame("Frame", "HawarysJourneyArrow", UIParent)
    arrow:SetSize(96, 100)
    arrow:SetFrameStrata("MEDIUM")
    arrow:SetClampedToScreen(true)
    arrow:SetMovable(true)
    RestorePos(arrow, "arrowPos", "TOP", UIParent, "TOP", 0, -170)
    Draggable(arrow, arrow, "arrowPos")
    arrow.glow = W.Icon(arrow, "glow", 92, nil, "BACKGROUND")
    arrow.glow:SetPoint("CENTER", 0, 12)
    arrow.glow:SetVertexColor(0.22, 0.78, 0.96, 0.25)
    arrow.nav = W.Icon(arrow, "nav", 52, "accent")
    arrow.nav:SetPoint("CENTER", 0, 12)
    arrow.dist = W.Label(arrow, "", "h2", "text", "CENTER")
    arrow.dist:SetPoint("TOP", arrow.nav, "BOTTOM", 0, -8)
    arrow.label = W.Label(arrow, "", "small", "text3", "CENTER")
    arrow.label:SetPoint("TOP", arrow.dist, "BOTTOM", 0, -2)
    arrow.label:SetWidth(180)
    arrow.label:SetWordWrap(false)
    arrow:Hide()
end

local function Tick()
    if not Journey.enabled then return end
    local dist, rot = Journey:DistanceTo(Journey.target)
    local near = dist and dist <= 30
    if frame and frame:IsShown() then
        local card = frame.card
        card.nav:SetShown(rot ~= nil)
        if rot then card.nav:SetRotation(rot) end
        card.dist:SetText(dist and J.FormatDistance(dist) or "")
        if near then card.nav:SetVertexColor(0.29, 0.87, 0.5) else T.Tint(card.nav, "accent") end
    end
    if arrow then
        local show = Journey:Get("arrow") and rot ~= nil
        arrow:SetShown(show)
        if show then
            arrow:SetScale(Journey:Get("scale") or 1)
            arrow.nav:SetRotation(rot)
            arrow.dist:SetText(J.FormatDistance(dist))
            local step = Journey.current
            arrow.label:SetText(step and StepTitle(step) or "")
            if near then
                arrow.nav:SetVertexColor(0.29, 0.87, 0.5)
                arrow.glow:SetVertexColor(0.29, 0.87, 0.5, 0.3)
            else
                T.Tint(arrow.nav, "accent")
                arrow.glow:SetVertexColor(0.22, 0.78, 0.96, 0.25)
            end
        end
    end
    -- "go to" steps finish when you arrive
    local step = Journey.current
    if step and step.type == "goto" and dist and dist <= J.ARRIVE_YARDS then Journey:QueueRefresh() end
end

local function ApplyVisibility()
    local on = Journey.enabled
    if on and not frame then BuildFrame() end
    if on and not arrow then BuildArrow() end
    if frame then frame:SetShown(on and Journey:Get("window")) end
    if arrow and not (on and Journey:Get("arrow")) then arrow:Hide() end
    if on and not ticker then
        ticker = C_Timer.NewTicker(0.1, function() ns.Safe(Tick) end)
    elseif not on and ticker then
        ticker:Cancel()
        ticker = nil
    end
    if on then ns.Safe(Update) end
end

ns.JourneyUI = { Update = Update, ApplyVisibility = ApplyVisibility }

ns:On("JOURNEY_UPDATED", function() if frame then Update() end end)
ns:On("JOURNEY_ENABLED", ApplyVisibility)
ns:On("JOURNEY_SETTINGS", function(key)
    if key == "window" or key == "arrow" then ApplyVisibility()
    elseif key == "scale" and frame then Update() end
end)
ns:On("JOURNEY_TOGGLE", function()
    if not Journey.enabled then ns:SetModuleEnabled("journey", true) end
    Journey:Set("window", not Journey:Get("window"))
end)

---------------------------------------------------------------------------
-- Journey page in the main window: intro, options, guide library
---------------------------------------------------------------------------
local TEMPLATE = table.concat({
    "# Hawary's Addon guide – one step per line (see docs/GUIDE-FORMAT.md).",
    "# guide: My route 1-10",
    "# accept 1234 Quest name @ 45.2 60.1",
    "# complete 1234",
    "# turnin 1234",
    "# goto 52.0 41.3 The inn",
    "",
}, "\n")

function Journey:BuildPage(content, width, y)
    -- intro card
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 112)
    local glow = W.Icon(card, "glow", 150, nil, "ARTWORK")
    glow:SetPoint("CENTER", card, "LEFT", 46, 6)
    glow:SetVertexColor(0.22, 0.78, 0.96, 0.22)
    local icon = W.Icon(card, "nav", 38, "accent")
    icon:SetPoint("TOPLEFT", 26, -18)
    local title = W.Label(card, L.JOURNEY_AUTO, "h2", "text")
    title:SetPoint("TOPLEFT", 82, -16)
    local text = W.Label(card, L.JOURNEY_AUTO_DESC, "small", "text2")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    text:SetWidth(width - 100)
    text:SetWordWrap(true)
    local show = W.Button(card, L.JOURNEY_SHOW, "primary", 130)
    show:SetPoint("BOTTOMLEFT", 82, 14)
    show:SetScript("OnClick", function() Journey:Set("window", true) end)
    local import = W.Button(card, L.JOURNEY_IMPORT, "secondary", 120)
    import:SetPoint("LEFT", show, "RIGHT", 8, 0)
    local restart = W.Button(card, L.JOURNEY_RESTART, "ghost", 110)
    restart:SetPoint("LEFT", import, "RIGHT", 8, 0)
    restart:SetScript("OnClick", function() Journey:RestartGuide() end)
    y = y - 112 - 18

    y = ns:BuildOptions(self, content, width, y)

    -- guide library
    local h = W.Label(content, L.JOURNEY_GUIDES, "h2", "accent")
    h:SetPoint("TOPLEFT", 0, y - 6)
    y = y - 30
    local listTop = y
    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", 0, y)
    list:SetWidth(width)
    list.rows = {}

    function list:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        local names = ns.Util.sortedKeys(ns.db.guides)
        local ly = 0
        if #names == 0 then
            if not self.emptyLabel then
                self.emptyLabel = W.Label(self, L.JOURNEY_NO_GUIDES, "small", "text3")
                self.emptyLabel:SetPoint("TOPLEFT", 0, 0)
                self.emptyLabel:SetWidth(width)
                self.emptyLabel:SetWordWrap(true)
            end
            self.emptyLabel:Show()
            ly = -self.emptyLabel:GetStringHeight() - 6
        elseif self.emptyLabel then
            self.emptyLabel:Hide()
        end
        for i, name in ipairs(names) do
            local row = self.rows[i]
            if not row then
                row = W.Card(self)
                row:SetHeight(40)
                row.name = W.Label(row, "", "body", "text")
                row.name:SetPoint("LEFT", 14, 6)
                row.info = W.Label(row, "", "small", "text3")
                row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
                row.del = W.Button(row, L.DELETE, "danger", 70, 22)
                row.del:SetPoint("RIGHT", -10, 0)
                row.use = W.Button(row, L.JOURNEY_USE, "secondary", 70, 22)
                row.use:SetPoint("RIGHT", row.del, "LEFT", -6, 0)
                self.rows[i] = row
            end
            local guide = Journey:Guide(name)
            local active = Journey:Get("guide") == name
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, ly)
            row:SetWidth(width)
            row.name:SetText(name)
            row.info:SetText(L.JOURNEY_GUIDE_INFO:format(guide and #guide.steps or 0)
                .. (active and ("  ·  |cff38c6f4" .. L.JOURNEY_ACTIVE .. "|r") or ""))
            if row.border then T.Tint(row.border, active and "accent" or "line") end
            row.use:SetEnabled(not active)
            row.use:SetScript("OnClick", function() Journey:Set("guide", name); list:Refresh() end)
            row.del:SetScript("OnClick", function() Journey:DeleteGuide(name); list:Refresh() end)
            row:Show()
            ly = ly - 48
        end
        self:SetHeight(math.max(1, -ly))
        content:SetHeight(-listTop - ly + 30)
    end

    import:SetScript("OnClick", function()
        W.TextDialog(L.JOURNEY_IMPORT_PROMPT, TEMPLATE, false, function(textValue)
            local name, errors, count = Journey:ImportGuide(textValue)
            if name then
                ns:Print(L.JOURNEY_IMPORTED, name, count)
                Journey:Set("guide", name)
            else
                ns:Print(L.JOURNEY_IMPORT_ERRORS)
            end
            for i = 1, math.min(#(errors or {}), 6) do ns:Print("  %s", errors[i]) end
            list:Refresh()
        end)
    end)

    list:Refresh()
    return y - list:GetHeight() - 10
end
