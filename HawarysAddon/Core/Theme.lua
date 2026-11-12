-- Hawary's Addon: themes (Hawary Neon / Blizzard + Hawary) and the branded widget kit
local _, ns = ...
local L = ns.L

local T = {}
ns.Theme = T
local W = {}
ns.W = W

local MEDIA = ns.media
local BRAND_FONT = MEDIA .. "ChakraPetch-Bold.ttf"

---------------------------------------------------------------------------
-- Palettes
---------------------------------------------------------------------------
T.palettes = {
    neon = {
        window = { 0.067, 0.082, 0.110, 0.98 },  -- #11151C
        sidebar = { 0.055, 0.067, 0.090, 1 },
        card = { 0.090, 0.106, 0.141, 1 },      -- #171B24
        card2 = { 0.114, 0.133, 0.176, 1 },     -- #1D222D
        hover = { 0.150, 0.175, 0.230, 1 },
        line = { 0.165, 0.192, 0.251, 1 },      -- #2A3140
        accent = { 0.220, 0.776, 0.957, 1 },    -- #38C6F4
        accent2 = { 0.055, 0.604, 0.788, 1 },   -- #0E9AC9
        onAccent = { 0.040, 0.070, 0.100, 1 },
        text = { 0.949, 0.961, 0.976, 1 },
        text2 = { 0.682, 0.718, 0.780, 1 },
        text3 = { 0.467, 0.502, 0.561, 1 },
        title = { 0.949, 0.961, 0.976, 1 },
        good = { 0.290, 0.870, 0.500, 1 },
        bad = { 0.970, 0.440, 0.440, 1 },
        warn = { 1.000, 0.780, 0.300, 1 },
        shadow = { 0, 0, 0, 0.55 },
    },
    native = {
        window = { 0, 0, 0, 0 },
        sidebar = { 0, 0, 0, 0.35 },
        card = { 0, 0, 0, 0.40 },
        card2 = { 0.10, 0.08, 0.05, 0.65 },
        hover = { 1, 0.82, 0, 0.12 },
        line = { 0.55, 0.45, 0.25, 0.70 },
        accent = { 0.220, 0.776, 0.957, 1 },
        accent2 = { 0.055, 0.604, 0.788, 1 },
        onAccent = { 0.040, 0.070, 0.100, 1 },
        text = { 1, 1, 1, 1 },
        text2 = { 0.86, 0.86, 0.86, 1 },
        text3 = { 0.62, 0.62, 0.62, 1 },
        title = { 1, 0.82, 0, 1 },
        good = { 0.250, 0.900, 0.350, 1 },
        bad = { 1, 0.35, 0.35, 1 },
        warn = { 1, 0.82, 0, 1 },
        shadow = { 0, 0, 0, 0 },
    },
}

function T.name() return (ns.db and ns.db.general.theme) or "neon" end
function T.native() return T.name() == "native" end
function T.color(key) return unpack(T.palettes[T.name()][key]) end
function T.hex(key)
    local r, g, b = T.color(key)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

---------------------------------------------------------------------------
-- Fonts: brand font for titles; the game's own font for body text so every
-- language's letters render.
---------------------------------------------------------------------------
local function MakeFont(name, file, size, flags)
    local f = CreateFont(name)
    if not f:SetFont(file, size, flags or "") then
        f:SetFont(STANDARD_TEXT_FONT, size, flags or "")
    end
    f:SetShadowOffset(1, -1)
    f:SetShadowColor(0, 0, 0, 0.6)
    return f
end

local fonts = {
    brand = MakeFont("HawarysFontBrand", BRAND_FONT, 18),
    brandBig = MakeFont("HawarysFontBrandBig", BRAND_FONT, 24),
    h1 = MakeFont("HawarysFontH1", BRAND_FONT, 16),
    h2 = MakeFont("HawarysFontH2", BRAND_FONT, 13),
    number = MakeFont("HawarysFontNumber", BRAND_FONT, 20),
    tag = MakeFont("HawarysFontTag", BRAND_FONT, 9),
    body = MakeFont("HawarysFontBody", STANDARD_TEXT_FONT, 12),
    small = MakeFont("HawarysFontSmall", STANDARD_TEXT_FONT, 11),
}

local nativeFonts = { h1 = "GameFontNormalLarge", h2 = "GameFontNormal", body = "GameFontHighlight", small = "GameFontHighlightSmall" }

function T.font(key)
    if T.native() and nativeFonts[key] then return _G[nativeFonts[key]] or fonts[key] end
    return fonts[key] or fonts.body
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
local SLICE = { round = 16, round_line = 16, round_sm = 8, round_sm_line = 8, pill = 15, shadow = 44 }

-- A 9-sliced rounded texture filling `frame` (or positioned by the caller when noPoints).
function T.Shape(frame, shape, colorKeyOrTable, layer, sublevel, noPoints)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetTexture(MEDIA .. shape)
    local m = SLICE[shape]
    if m then
        t:SetTextureSliceMargins(m, m, m, m)
        t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
    if not noPoints then t:SetAllPoints() end
    T.Tint(t, colorKeyOrTable)
    return t
end

function T.Tint(texture, colorKeyOrTable)
    if not colorKeyOrTable then return end
    if type(colorKeyOrTable) == "table" then
        texture:SetVertexColor(unpack(colorKeyOrTable))
    else
        texture:SetVertexColor(T.color(colorKeyOrTable))
    end
end

function T.TextColor(fs, colorKey)
    fs:SetTextColor(T.color(colorKey))
end

function T.Sound(kind)
    if not (PlaySound and SOUNDKIT) then return end
    local id = (kind == "on" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        or (kind == "off" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        or (kind == "open" and SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        or (kind == "close" and SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        or SOUNDKIT.U_CHAT_SCROLL_BUTTON
    if id then PlaySound(id) end
end

---------------------------------------------------------------------------
-- Basic pieces
---------------------------------------------------------------------------
function W.Label(parent, text, fontKey, colorKey, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(T.font(fontKey or "body"))
    if colorKey then T.TextColor(fs, colorKey) end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text or "")
    return fs
end

-- file: a Media texture name ("arrow") or a full path / file ID
function W.Icon(parent, file, size, colorKey, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    if type(file) == "string" and not file:find("\\", 1, true) then file = MEDIA .. file end
    t:SetTexture(file)
    t:SetSize(size, size)
    if colorKey then T.Tint(t, colorKey) end
    return t
end

function W.Divider(parent, colorKey)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(T.color(colorKey or "line"))
    t:SetHeight(1)
    return t
end

function W.Card(parent, colorKey)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = T.Shape(f, "round", colorKey or "card", "BACKGROUND", 0)
    f.border = T.Shape(f, "round_line", "line", "BORDER", 0)
    return f
end

-- Small rounded tag, e.g. "SOON" or "NEW"
function W.Tag(parent, text, colorKey)
    local f = CreateFrame("Frame", nil, parent)
    local r, g, b = T.color(colorKey or "accent")
    f.bg = T.Shape(f, "pill", { r, g, b, 0.16 }, "BACKGROUND")
    f.text = W.Label(f, text, "tag", nil, "CENTER")
    f.text:SetTextColor(r, g, b)
    f.text:SetPoint("CENTER", 0, 0)
    f:SetSize(f.text:GetStringWidth() + 14, 15)
    return f
end

function W.Tooltip(frame, title, text)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title() or title, T.color("accent"))
        if text then GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Button. kind: "primary" | "secondary" | "ghost" | "danger"
---------------------------------------------------------------------------
function W.Button(parent, text, kind, width, height)
    kind = kind or "secondary"
    height = height or 24
    local b
    if T.native() then
        b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetText(text or "")
        b:SetSize(width or math.max(80, b:GetFontString():GetStringWidth() + 30), height)
        b.SetLabel = function(self, t) self:SetText(t) end
        return b
    end

    b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 80, height)
    b.bg = T.Shape(b, "round_sm", nil, "BACKGROUND")
    b.border = T.Shape(b, "round_sm_line", nil, "BORDER")
    b.label = W.Label(b, text, "h2", nil, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.kind = kind

    local function paint(self, hover)
        local k = self.kind
        if not self:IsEnabled() then
            T.Tint(self.bg, "card2"); T.Tint(self.border, "line"); T.TextColor(self.label, "text3")
            return
        end
        if k == "primary" then
            T.Tint(self.bg, hover and { 0.42, 0.85, 1, 1 } or "accent")
            T.Tint(self.border, hover and { 0.6, 0.9, 1, 1 } or "accent")
            T.TextColor(self.label, "onAccent")
        elseif k == "danger" then
            T.Tint(self.bg, hover and { 0.97, 0.44, 0.44, 0.28 } or { 0.97, 0.44, 0.44, 0.14 })
            T.Tint(self.border, "bad")
            T.TextColor(self.label, "bad")
        elseif k == "ghost" then
            T.Tint(self.bg, hover and "hover" or { 0, 0, 0, 0 })
            T.Tint(self.border, hover and "line" or { 0, 0, 0, 0 })
            T.TextColor(self.label, hover and "text" or "text2")
        else
            T.Tint(self.bg, hover and "hover" or "card2")
            T.Tint(self.border, hover and "accent" or "line")
            T.TextColor(self.label, hover and "text" or "text2")
        end
    end
    b.Paint = paint

    b:SetScript("OnEnter", function(self) paint(self, true) end)
    b:SetScript("OnLeave", function(self) paint(self, false) end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 0, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnEnable", function(self) paint(self, false) end)
    b:SetScript("OnDisable", function(self) paint(self, false) end)
    b.SetLabel = function(self, t)
        self.label:SetText(t)
        if not width then self:SetWidth(math.max(64, self.label:GetStringWidth() + 26)) end
    end
    b:SetLabel(text or "")
    paint(b, false)
    return b
end

---------------------------------------------------------------------------
-- Toggle: animated switch (neon) / checkbox (native)
---------------------------------------------------------------------------
function W.Toggle(parent, checked, onChange)
    local t
    if T.native() then
        t = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        t:SetSize(26, 26)
        t:SetChecked(checked and true or false)
        t:SetScript("OnClick", function(self)
            T.Sound(self:GetChecked() and "on" or "off")
            if self.onChange then self.onChange(self:GetChecked() and true or false) end
        end)
        t.onChange = onChange
        t.SetValue = function(self, v) self:SetChecked(v and true or false) end
        return t
    end

    t = CreateFrame("Button", nil, parent)
    t:SetSize(38, 20)
    t.glow = t:CreateTexture(nil, "BACKGROUND", nil, -1)
    t.glow:SetTexture(MEDIA .. "glow")
    t.glow:SetPoint("CENTER")
    t.glow:SetSize(70, 44)
    T.Tint(t.glow, { 0.22, 0.78, 0.96, 0.30 })
    t.track = T.Shape(t, "pill", "line", "BACKGROUND")
    t.knob = t:CreateTexture(nil, "ARTWORK")
    t.knob:SetTexture(MEDIA .. "circle")
    t.knob:SetSize(14, 14)
    t.onChange = onChange
    t.pos = checked and 1 or 0

    local function place(self)
        self.knob:ClearAllPoints()
        self.knob:SetPoint("LEFT", 3 + self.pos * 18, 0)
    end
    local function paint(self, hover)
        if self.checked then
            T.Tint(self.track, "accent")
            T.Tint(self.knob, "onAccent")
            self.glow:Show()
        else
            T.Tint(self.track, hover and "hover" or "line")
            T.Tint(self.knob, hover and "text" or "text2")
            self.glow:Hide()
        end
    end

    t.SetValue = function(self, v)
        self.checked = v and true or false
        self.pos = self.checked and 1 or 0
        place(self); paint(self, false)
    end
    t.GetChecked = function(self) return self.checked end
    t.SetChecked = t.SetValue

    t:SetScript("OnClick", function(self)
        self.checked = not self.checked
        T.Sound(self.checked and "on" or "off")
        paint(self, true)
        local target = self.checked and 1 or 0
        self:SetScript("OnUpdate", function(s, elapsed)
            local step = elapsed / 0.12
            if s.pos < target then s.pos = math.min(target, s.pos + step) else s.pos = math.max(target, s.pos - step) end
            place(s)
            if s.pos == target then s:SetScript("OnUpdate", nil) end
        end)
        if self.onChange then self.onChange(self.checked) end
    end)
    t:SetScript("OnEnter", function(self) paint(self, true) end)
    t:SetScript("OnLeave", function(self) paint(self, false) end)
    t:SetValue(checked)
    return t
end

---------------------------------------------------------------------------
-- Slider (Blizzard's minimal slider in both themes)
---------------------------------------------------------------------------
function W.Slider(parent, minV, maxV, step, value, format, onChange)
    local s = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
    s:SetSize(200, 20)
    local steps = math.floor((maxV - minV) / step + 0.5)
    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Right] = function(v) return format and format(v) or tostring(v) end,
    }
    s:Init(value, minV, maxV, steps, formatters)
    s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
        if onChange then onChange(v) end
    end, s)
    s.SetValue = function(self, v) self.Slider:SetValue(v) end
    return s
end

---------------------------------------------------------------------------
-- Dropdown (Blizzard menu system). getOptions() -> { {value=, text=}, ... }
---------------------------------------------------------------------------
function W.Dropdown(parent, width, getOptions, getValue, setValue)
    local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    d:SetWidth(width or 180)
    d:SetupMenu(function(_, root)
        for _, opt in ipairs(getOptions()) do
            root:CreateRadio(opt.text,
                function() return getValue() == opt.value end,
                function() setValue(opt.value) end,
                opt.value)
        end
    end)
    d.Refresh = function(self) self:GenerateMenu() end
    return d
end

---------------------------------------------------------------------------
-- Edit box (single or multi line)
---------------------------------------------------------------------------
function W.EditBox(parent, width, height, multiline)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height or 26)
    box.bg = T.Shape(box, "round_sm", T.native() and { 0, 0, 0, 0.5 } or "window", "BACKGROUND")
    box.border = T.Shape(box, "round_sm_line", "line", "BORDER")

    local edit
    if multiline then
        local scroll = CreateFrame("ScrollFrame", nil, box, "ScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -6)
        scroll:SetPoint("BOTTOMRIGHT", -24, 6)
        edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetWidth(width - 36)
        edit:SetHeight(height)
        scroll:SetScrollChild(edit)
        box.scroll = scroll
        box:EnableMouse(true)
        box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    else
        edit = CreateFrame("EditBox", nil, box)
        edit:SetPoint("TOPLEFT", 8, 0)
        edit:SetPoint("BOTTOMRIGHT", -8, 0)
    end
    edit:SetAutoFocus(false)
    edit:SetFontObject(T.font("body"))
    edit:SetTextColor(T.color("text"))
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function() T.Tint(box.border, "accent") end)
    edit:SetScript("OnEditFocusLost", function() T.Tint(box.border, "line") end)
    if not multiline then
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end
    box.edit = edit
    box.SetText = function(self, t) self.edit:SetText(t or "") end
    box.GetText = function(self) return self.edit:GetText() end
    return box
end

---------------------------------------------------------------------------
-- Scrolling page
---------------------------------------------------------------------------
function W.ScrollPage(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -18, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    scroll.content = content
    return scroll
end

---------------------------------------------------------------------------
-- Settings row: label + description on the left, control on the right
---------------------------------------------------------------------------
function W.OptionRow(parent, width, label, desc, control, controlWidth)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(width)
    controlWidth = controlWidth or (control and control:GetWidth()) or 0
    row.label = W.Label(row, label, "body", "text")
    row.label:SetPoint("TOPLEFT", 0, 0)
    row.label:SetWidth(width - controlWidth - 24)
    local h = row.label:GetStringHeight()
    if desc and desc ~= "" then
        row.desc = W.Label(row, desc, "small", "text3")
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        row.desc:SetWidth(width - controlWidth - 24)
        row.desc:SetWordWrap(true)
        h = h + 3 + row.desc:GetStringHeight()
    end
    if control then
        control:SetParent(row)
        control:ClearAllPoints()
        control:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        h = math.max(h, control:GetHeight())
    end
    row:SetHeight(h)
    row.control = control
    return row
end

---------------------------------------------------------------------------
-- Window shell with the Hawary header
---------------------------------------------------------------------------
function W.Window(name, width, height)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, name)

    if T.native() then
        local border = CreateFrame("Frame", nil, f, "DialogBorderTranslucentTemplate")
        border:SetAllPoints()
        border:SetFrameLevel(f:GetFrameLevel())
        f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.close:SetPoint("TOPRIGHT", -4, -4)
    else
        f.shadow = T.Shape(f, "shadow", "shadow", "BACKGROUND", -8, true)
        f.shadow:SetPoint("TOPLEFT", -26, 26)
        f.shadow:SetPoint("BOTTOMRIGHT", 26, -26)
        f.bg = T.Shape(f, "round", "window", "BACKGROUND", 0)
        f.border = T.Shape(f, "round_line", "line", "BORDER", 0)
        f.close = CreateFrame("Button", nil, f)
        f.close:SetSize(28, 28)
        f.close:SetPoint("TOPRIGHT", -10, -12)
        f.close.icon = W.Icon(f.close, "x", 20, "text3")
        f.close.icon:SetPoint("CENTER")
        f.close:SetScript("OnEnter", function(self) T.Tint(self.icon, "bad") end)
        f.close:SetScript("OnLeave", function(self) T.Tint(self.icon, "text3") end)
    end
    f.close:SetScript("OnClick", function() f:Hide() end)

    -- Header: hex logo + HAWARY'S ADDON wordmark (drag to move)
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", -44, 0)
    header:SetHeight(52)
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then f:StartMoving() end end)
    header:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint(1)
        if f.savePosition then ns.db.general.window = { point = point, relPoint = relPoint, x = x, y = y } end
    end)
    f.header = header

    f.logo = header:CreateTexture(nil, "ARTWORK")
    f.logo:SetTexture(MEDIA .. "logo")
    f.logo:SetSize(32, 32)
    f.logo:SetPoint("LEFT", 16, -2)

    f.brand1 = W.Label(header, L.BRAND_FIRST, "brand")
    f.brand1:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
    T.TextColor(f.brand1, T.native() and "title" or "text")
    f.brand2 = W.Label(header, L.BRAND_SECOND, "brand", "accent")
    f.brand2:SetPoint("LEFT", f.brand1, "RIGHT", 6, 0)
    f.underline = header:CreateTexture(nil, "ARTWORK")
    f.underline:SetColorTexture(T.color("accent"))
    f.underline:SetSize(28, 2)
    f.underline:SetPoint("TOPLEFT", f.brand1, "BOTTOMLEFT", 0, -3)
    f.versionTag = W.Tag(header, "v" .. ns.version, "accent")
    f.versionTag:SetPoint("LEFT", f.brand2, "RIGHT", 10, 0)

    f.headerLine = W.Divider(f)
    f.headerLine:SetPoint("TOPLEFT", 1, -52)
    f.headerLine:SetPoint("TOPRIGHT", -1, -52)
    if T.native() then f.headerLine:SetAlpha(0.6) end

    -- Fade in
    f.fade = f:CreateAnimationGroup()
    local a = f.fade:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.14)
    f.fade:SetToFinalAlpha(true)
    f:HookScript("OnShow", function(self) self.fade:Restart(); T.Sound("open") end)
    f:HookScript("OnHide", function() T.Sound("close") end)
    return f
end

---------------------------------------------------------------------------
-- Text dialog (import / export)
---------------------------------------------------------------------------
local dialog
function W.TextDialog(title, text, readOnly, onAccept)
    if not dialog then
        dialog = W.Window("HawarysAddonTextDialog", 460, 300)
        dialog:SetFrameStrata("DIALOG")
        dialog.title = W.Label(dialog, "", "h2", "text2")
        dialog.title:SetPoint("TOPLEFT", 18, -66)
        dialog.box = W.EditBox(dialog, 424, 160, true)
        dialog.box:SetPoint("TOPLEFT", 18, -88)
        dialog.ok = W.Button(dialog, L.SAVE, "primary", 100)
        dialog.ok:SetPoint("BOTTOMRIGHT", -18, 16)
        dialog.cancel = W.Button(dialog, L.CLOSE, "secondary", 100)
        dialog.cancel:SetPoint("RIGHT", dialog.ok, "LEFT", -8, 0)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() end)
    end
    dialog.title:SetText(title)
    dialog.box:SetText(text or "")
    dialog.ok:SetShown(not readOnly)
    dialog.ok:SetScript("OnClick", function()
        if onAccept then onAccept(dialog.box:GetText()) end
        dialog:Hide()
    end)
    dialog:Show()
    dialog.box.edit:SetFocus()
    if readOnly then dialog.box.edit:HighlightText() end
end
