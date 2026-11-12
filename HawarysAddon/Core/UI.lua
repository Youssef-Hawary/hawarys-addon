-- Hawary's Addon: main window (sidebar, Home dashboard, module pages), Blizzard
-- options menu registration, minimap button and toast notices.
local _, ns = ...
local L, T, W = ns.L, ns.Theme, ns.W

local WIDTH, HEIGHT, SIDEBAR = 840, 560, 196

---------------------------------------------------------------------------
-- General settings behave like a module so both menus share the same code
---------------------------------------------------------------------------
local General = {
    id = "general",
    title = L.NAV_GENERAL,
    desc = L.GENERAL_DESC,
    defaults = { theme = "neon", welcome = true, toasts = true, scale = 1, minimapShow = true },
    noToggle = true,
    options = {
        { type = "dropdown", key = "theme", label = L.THEME, desc = L.THEME_DESC,
          values = function() return { { value = "neon", text = L.THEME_NEON }, { value = "native", text = L.THEME_NATIVE } } end },
        { type = "toggle", key = "minimapShow", label = L.MINIMAP_BUTTON, desc = L.MINIMAP_BUTTON_DESC },
        { type = "toggle", key = "welcome", label = L.WELCOME_TOAST, desc = L.WELCOME_TOAST_DESC },
        { type = "toggle", key = "toasts", label = L.TOASTS, desc = L.TOASTS_DESC },
        { type = "slider", key = "scale", label = L.UI_SCALE, desc = L.UI_SCALE_DESC, min = 0.7, max = 1.4, step = 0.05,
          format = function(v) return string.format("%d%%", v * 100 + 0.5) end },
    },
}
ns.General = General

function General:Get(key)
    if key == "minimapShow" then return ns.db.general.minimap.show end
    return ns.db.general[key]
end

function General:Set(key, value)
    if key == "minimapShow" then
        ns.db.general.minimap.show = value
        ns:UpdateMinimapButton()
    elseif key == "theme" then
        if ns.db.general.theme ~= value then
            ns.db.general.theme = value
            StaticPopup_Show("HAWARYS_ADDON_RELOAD")
        end
    else
        ns.db.general[key] = value
        if key == "scale" and ns.window then ns.window:SetScale(value) end
    end
    ns:Fire("SETTING_CHANGED", "general", key, value)
end

StaticPopupDialogs.HAWARYS_ADDON_RELOAD = {
    text = L.THEME_RELOAD,
    button1 = L.RELOAD_UI,
    button2 = L.CANCEL,
    OnAccept = function() C_UI.Reload() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Roadmap entries shown in the sidebar until their modules ship
ns.roadmap = {
    { id = "talents", title = L.MOD_TALENTS, desc = L.MOD_TALENTS_DESC },
    { id = "professions", title = L.MOD_PROFESSIONS, desc = L.MOD_PROFESSIONS_DESC },
    { id = "market", title = L.MOD_MARKET, desc = L.MOD_MARKET_DESC },
    { id = "dungeons", title = L.MOD_DUNGEONS, desc = L.MOD_DUNGEONS_DESC },
    { id = "discovery", title = L.MOD_DISCOVERY, desc = L.MOD_DISCOVERY_DESC },
    { id = "alts", title = L.MOD_ALTS, desc = L.MOD_ALTS_DESC },
    { id = "whatnow", title = L.MOD_WHATNOW, desc = L.MOD_WHATNOW_DESC },
    { id = "macrohelp", title = L.MOD_MACROHELP, desc = L.MOD_MACROHELP_DESC },
}

-- Home dashboard numbers, registered by modules: fn() -> display text
ns.stats = {}
function ns:RegisterStat(id, label, fn, order)
    table.insert(ns.stats, { id = id, label = label, fn = fn, order = order or 50 })
    table.sort(ns.stats, function(a, b) return a.order < b.order end)
end

---------------------------------------------------------------------------
-- Option controls (shared by module pages); kept in sync on SETTING_CHANGED
---------------------------------------------------------------------------
local liveControls = {} -- ["module:key"] = control

local function MakeControl(mod, opt)
    local value = mod:Get(opt.key)
    local control
    if opt.type == "toggle" then
        control = W.Toggle(nil, value, function(v) mod:Set(opt.key, v) end)
    elseif opt.type == "slider" then
        control = W.Slider(nil, opt.min, opt.max, opt.step, value, opt.format, function(v) mod:Set(opt.key, v) end)
    elseif opt.type == "dropdown" then
        control = W.Dropdown(nil, 190, opt.values, function() return mod:Get(opt.key) end, function(v) mod:Set(opt.key, v) end)
    elseif opt.type == "button" then
        control = W.Button(nil, opt.buttonText or opt.label, opt.kind or "secondary")
        control:SetScript("OnClick", function() opt.onClick(mod) end)
    end
    if control and opt.key then liveControls[mod.id .. ":" .. opt.key] = control end
    return control
end

ns:On("SETTING_CHANGED", function(modId, key, value)
    local c = liveControls[modId .. ":" .. key]
    if not c then return end
    if c.Refresh then c:Refresh() elseif c.SetValue then c:SetValue(value) end
end)

-- Lays out a module's options in `content` starting at y; returns the new y.
function ns:BuildOptions(mod, content, width, y)
    for _, opt in ipairs(mod.options) do
        if opt.type == "header" then
            local h = W.Label(content, opt.label, "h2", "accent")
            h:SetPoint("TOPLEFT", 0, y - 6)
            y = y - 6 - h:GetStringHeight() - 10
        else
            local control = MakeControl(mod, opt)
            local indent = opt.parent and 18 or 0
            local row = W.OptionRow(content, width - indent, opt.label, opt.desc, control)
            row:SetPoint("TOPLEFT", indent, y)
            y = y - row:GetHeight() - 16
        end
    end
    return y
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local pages, navButtons = {}, {}
local window

local function PageHeader(content, width, title, desc, mod)
    local titleFs = W.Label(content, title, "h1", "title")
    titleFs:SetPoint("TOPLEFT", 0, 0)
    local y = -titleFs:GetStringHeight() - 8
    if mod and not mod.noToggle then
        local tog = W.Toggle(content, mod:IsEnabled(), function(v) ns:SetModuleEnabled(mod.id, v) end)
        tog:SetPoint("TOPRIGHT", 0, 2)
        local state = W.Label(content, mod:IsEnabled() and L.ENABLED or L.DISABLED, "small", "text3", "RIGHT")
        state:SetPoint("RIGHT", tog, "LEFT", -8, 0)
        ns:On("MODULE_TOGGLED", function(id, on)
            if id == mod.id then state:SetText(on and L.ENABLED or L.DISABLED); tog:SetValue(on) end
        end)
    end
    if desc then
        local d = W.Label(content, desc, "body", "text2")
        d:SetPoint("TOPLEFT", 0, y)
        d:SetWidth(width)
        d:SetWordWrap(true)
        y = y - d:GetStringHeight() - 14
    end
    local line = W.Divider(content)
    line:SetPoint("TOPLEFT", 0, y)
    line:SetPoint("TOPRIGHT", 0, y)
    return y - 18
end

local function BuildOptionsPage(parent, mod)
    local scroll = W.ScrollPage(parent)
    local content = scroll.content
    local width = parent:GetWidth() - 30
    content:SetWidth(width)
    local y = PageHeader(content, width, mod.title, mod.desc, mod)
    if mod.BuildPage then
        y = mod:BuildPage(content, width, y)
    else
        y = ns:BuildOptions(mod, content, width, y)
    end
    content:SetHeight(-y + 20)
    return scroll
end

local function BuildRoadmapPage(parent, item)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    local width = parent:GetWidth() - 30
    local y = PageHeader(f, width, item.title, nil)
    local card = W.Card(f)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 120)
    local glow = card:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(ns.media .. "glow")
    glow:SetSize(170, 170)
    glow:SetPoint("CENTER", card, "LEFT", 62, 0)
    T.Tint(glow, { 0.22, 0.78, 0.96, 0.25 })
    local mark = W.Icon(card, "mark", 56)
    mark:SetPoint("LEFT", 34, 0)
    local tag = W.Tag(card, L.SOON, "accent")
    tag:SetPoint("TOPLEFT", mark, "TOPRIGHT", 24, -4)
    local txt = W.Label(card, item.desc, "body", "text")
    txt:SetPoint("TOPLEFT", tag, "BOTTOMLEFT", 0, -8)
    txt:SetWidth(width - 150)
    txt:SetWordWrap(true)
    return f
end

---------------------------------------------------------------------------
-- Home dashboard
---------------------------------------------------------------------------
local function ClassColorHex()
    local _, classFile = UnitClass("player")
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    if c then return c:GenerateHexColor():sub(3) end
    return T.hex("accent")
end

local function BuildHome(parent)
    local scroll = W.ScrollPage(parent)
    local content = scroll.content
    local width = parent:GetWidth() - 30
    content:SetWidth(width)
    local gap = 12

    -- Hero card
    local hero = W.Card(content)
    hero:SetPoint("TOPLEFT", 0, 0)
    hero:SetSize(width, 104)
    local glow = hero:CreateTexture(nil, "ARTWORK", nil, -1)
    glow:SetTexture(ns.media .. "glow")
    glow:SetSize(220, 220)
    glow:SetPoint("CENTER", hero, "LEFT", 62, 0)
    T.Tint(glow, { 0.22, 0.78, 0.96, T.native() and 0.15 or 0.28 })
    local logo = W.Icon(hero, "logo", 64)
    logo:SetPoint("LEFT", 28, 0)
    hero.welcome = W.Label(hero, "", "h1", "title")
    hero.welcome:SetPoint("TOPLEFT", logo, "TOPRIGHT", 20, -6)
    hero.sub = W.Label(hero, "", "body", "text2")
    hero.sub:SetPoint("TOPLEFT", hero.welcome, "BOTTOMLEFT", 0, -6)
    local tagline = W.Label(hero, L.TAGLINE, "small", "text3")
    tagline:SetPoint("TOPLEFT", hero.sub, "BOTTOMLEFT", 0, -6)
    local tag = W.Tag(hero, "FOREVER", "accent")
    tag:SetPoint("TOPRIGHT", -16, -14)
    local y = -104 - 16

    -- Stat tiles
    local tiles = {}
    local count = math.max(#ns.stats, 1)
    local tileW = (width - gap * (count - 1)) / count
    for i, stat in ipairs(ns.stats) do
        local tile = W.Card(content, "card")
        tile:SetSize(tileW, 74)
        tile:SetPoint("TOPLEFT", (i - 1) * (tileW + gap), y)
        tile.value = W.Label(tile, "–", "number", "accent")
        tile.value:SetPoint("TOPLEFT", 14, -14)
        tile.label = W.Label(tile, stat.label, "small", "text3")
        tile.label:SetPoint("BOTTOMLEFT", 14, 13)
        tile.label:SetWidth(tileW - 20)
        tile.stat = stat
        tiles[#tiles + 1] = tile
    end
    y = y - 74 - 22

    -- Modules grid
    local mh = W.Label(content, L.HOME_MODULES, "h2", "text2")
    mh:SetPoint("TOPLEFT", 0, y)
    y = y - 22
    local cols, cardH = 2, 70
    local cardW = (width - gap) / cols
    local i = 0
    for _, mod in ipairs(ns.moduleOrder) do
        local col, rowIdx = i % cols, math.floor(i / cols)
        local card = W.Card(content)
        card:SetSize(cardW, cardH)
        card:SetPoint("TOPLEFT", col * (cardW + gap), y - rowIdx * (cardH + gap))
        local title = W.Label(card, mod.title, "h2", "text")
        title:SetPoint("TOPLEFT", 14, -12)
        local desc = W.Label(card, mod.desc, "small", "text3")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
        desc:SetPoint("RIGHT", card, "RIGHT", -64, 0)
        desc:SetWordWrap(true)
        desc:SetMaxLines(2)
        local tog = W.Toggle(card, mod:IsEnabled(), function(v) ns:SetModuleEnabled(mod.id, v) end)
        tog:SetPoint("TOPRIGHT", -12, -12)
        ns:On("MODULE_TOGGLED", function(id, on) if id == mod.id then tog:SetValue(on) end end)
        local hit = CreateFrame("Button", nil, card) -- the card itself opens the module page
        hit:SetPoint("TOPLEFT")
        hit:SetPoint("BOTTOMRIGHT", -60, 0)
        hit:SetScript("OnClick", function() ns:OpenWindow(mod.id) end)
        hit:SetScript("OnEnter", function() T.Tint(card.border, "accent") end)
        hit:SetScript("OnLeave", function() T.Tint(card.border, "line") end)
        i = i + 1
    end
    y = y - math.ceil(i / cols) * (cardH + gap) - 12

    -- Roadmap chips
    local rh = W.Label(content, L.HOME_ROADMAP, "h2", "text2")
    rh:SetPoint("TOPLEFT", 0, y)
    y = y - 22
    local x = 0
    for _, item in ipairs(ns.roadmap) do
        local chip = CreateFrame("Button", nil, content)
        chip.bg = T.Shape(chip, "pill", "card2", "BACKGROUND")
        chip.text = W.Label(chip, item.title, "small", "text2", "CENTER")
        chip.text:SetPoint("CENTER")
        local w = chip.text:GetStringWidth() + 26
        if x + w > width then x = 0; y = y - 30 end
        chip:SetSize(w, 22)
        chip:SetPoint("TOPLEFT", x, y)
        chip:SetScript("OnClick", function() ns:OpenWindow(item.id) end)
        chip:SetScript("OnEnter", function(self) T.Tint(self.bg, "hover"); T.TextColor(self.text, "accent") end)
        chip:SetScript("OnLeave", function(self) T.Tint(self.bg, "card2"); T.TextColor(self.text, "text2") end)
        x = x + w + 8
    end
    y = y - 22 - 18

    local tip = W.Label(content, L.HOME_TIP, "small", "text3")
    tip:SetPoint("TOPLEFT", 0, y)
    tip:SetWidth(width)
    tip:SetWordWrap(true)
    y = y - tip:GetStringHeight() - 10
    content:SetHeight(-y)

    scroll.Refresh = function()
        local name = UnitName("player") or ""
        local className = UnitClass("player") or ""
        hero.welcome:SetText(L.HOME_WELCOME:format("|cff" .. ClassColorHex() .. name .. "|r"))
        hero.sub:SetText(L.HOME_SUB:format(UnitLevel("player") or 0, className))
        for _, tile in ipairs(tiles) do
            local ok, v = ns.Safe(tile.stat.fn)
            tile.value:SetText(ok and v ~= nil and tostring(v) or "–")
        end
    end
    return scroll
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------
local function NavButton(parent, id, label, isSoon)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(30)
    b.bg = T.Shape(b, "round_sm", { 0, 0, 0, 0 }, "BACKGROUND")
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetColorTexture(T.color("accent"))
    b.bar:SetSize(3, 16)
    b.bar:SetPoint("LEFT", 0, 0)
    b.bar:Hide()
    b.text = W.Label(b, label, "body", isSoon and "text3" or "text2")
    b.text:SetPoint("LEFT", 14, 0)
    if isSoon then
        b.tag = W.Tag(b, L.SOON, "text3")
        b.tag:SetPoint("RIGHT", -8, 0)
    end
    b.id, b.soon = id, isSoon
    b.SetActive = function(self, active)
        self.active = active
        self.bar:SetShown(active)
        T.Tint(self.bg, active and "card2" or { 0, 0, 0, 0 })
        T.TextColor(self.text, active and "text" or (self.soon and "text3" or "text2"))
    end
    b:SetScript("OnEnter", function(self) if not self.active then T.Tint(self.bg, "hover") end end)
    b:SetScript("OnLeave", function(self) if not self.active then T.Tint(self.bg, { 0, 0, 0, 0 }) end end)
    b:SetScript("OnClick", function(self) T.Sound("nav"); ns:ShowPage(self.id) end)
    navButtons[id] = b
    return b
end

local function BuildWindow()
    window = W.Window("HawarysAddonWindow", WIDTH, HEIGHT)
    window.savePosition = true
    ns.window = window
    local pos = ns.db.general.window
    if pos and pos.point then
        window:ClearAllPoints()
        window:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
    window:SetScale(ns.db.general.scale or 1)
    window:Hide()

    local side = CreateFrame("Frame", nil, window)
    side:SetPoint("TOPLEFT", 1, -53)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR)
    if not T.native() then
        side.bg = side:CreateTexture(nil, "BACKGROUND", nil, 1)
        side.bg:SetColorTexture(T.color("sidebar"))
        side.bg:SetPoint("TOPLEFT")
        side.bg:SetPoint("BOTTOMRIGHT", 0, 14)
    end
    local sline = window:CreateTexture(nil, "ARTWORK")
    sline:SetColorTexture(T.color("line"))
    sline:SetWidth(1)
    sline:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    sline:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", 0, 14)
    if T.native() then sline:SetAlpha(0.5) end

    local y = -14
    local function add(btn)
        btn:SetPoint("TOPLEFT", side, "TOPLEFT", 10, y)
        btn:SetPoint("RIGHT", side, "RIGHT", -10, 0)
        y = y - 32
    end
    local function section(text)
        y = y - 8
        local fs = W.Label(side, text:upper(), "tag", "text3")
        fs:SetPoint("TOPLEFT", 22, y)
        y = y - 18
    end
    add(NavButton(side, "home", L.NAV_HOME))
    add(NavButton(side, "general", L.NAV_GENERAL))
    section(L.HOME_MODULES)
    for _, mod in ipairs(ns.moduleOrder) do add(NavButton(side, mod.id, mod.title)) end
    section(L.NAV_COMING)
    for _, item in ipairs(ns.roadmap) do add(NavButton(side, item.id, item.title, true)) end

    local area = CreateFrame("Frame", nil, window)
    area:SetPoint("TOPLEFT", side, "TOPRIGHT", 24, -20)
    area:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 18)
    window.area = area
end

function ns:ShowPage(id)
    if not window then BuildWindow() end
    if not navButtons[id] then id = "home" end
    for pid, page in pairs(pages) do page:SetShown(pid == id) end
    if not pages[id] then
        local area = window.area
        if id == "home" then
            pages[id] = BuildHome(area)
        elseif id == "general" then
            pages[id] = BuildOptionsPage(area, General)
        elseif ns.modules[id] then
            pages[id] = BuildOptionsPage(area, ns.modules[id])
        else
            for _, item in ipairs(ns.roadmap) do
                if item.id == id then pages[id] = BuildRoadmapPage(area, item) end
            end
        end
    end
    local page = pages[id]
    page:Show()
    if page.Refresh then page.Refresh() end
    for bid, b in pairs(navButtons) do b:SetActive(bid == id) end
    ns.db.general.lastPage = id
end

function ns:OpenWindow(page)
    if not window then BuildWindow() end
    window:Show()
    ns:ShowPage(page or ns.db.general.lastPage or "home")
end

function ns:ToggleWindow()
    if window and window:IsShown() then window:Hide() else ns:OpenWindow() end
end

---------------------------------------------------------------------------
-- Blizzard options menu (Options -> AddOns -> Hawary's Addon)
---------------------------------------------------------------------------
local rootCategory

local function RegisterProxy(category, mod, opt)
    local variable = "HAWARYS_" .. mod.id:upper() .. "_" .. opt.key:upper()
    local default = mod.defaults[opt.key]
    if default == nil and mod.charDefaults then default = mod.charDefaults[opt.key] end
    local varType = (opt.type == "toggle" and Settings.VarType.Boolean)
        or (opt.type == "slider" and Settings.VarType.Number)
        or Settings.VarType.String
    local setting = Settings.RegisterProxySetting(category, variable, varType, opt.label, default,
        function() return mod:Get(opt.key) end,
        function(value) mod:Set(opt.key, value) end)
    if opt.type == "toggle" then
        Settings.CreateCheckbox(category, setting, opt.desc)
    elseif opt.type == "slider" then
        local options = Settings.CreateSliderOptions(opt.min, opt.max, opt.step)
        if opt.format then options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, opt.format) end
        Settings.CreateSlider(category, setting, options, opt.desc)
    elseif opt.type == "dropdown" then
        Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, v in ipairs(opt.values()) do container:Add(v.value, v.text) end
            return container:GetData()
        end, opt.desc)
    end
end

local function RegisterModuleCategory(parent, mod)
    local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, mod.title)
    if not mod.noToggle then
        local enabled = Settings.RegisterProxySetting(category, "HAWARYS_" .. mod.id:upper() .. "_ENABLED",
            Settings.VarType.Boolean, L.MODULE_ENABLE, mod.enabledByDefault,
            function() return mod:IsEnabled() end,
            function(v) ns:SetModuleEnabled(mod.id, v) end)
        Settings.CreateCheckbox(category, enabled, L.MODULE_ENABLE_DESC)
    end
    for _, opt in ipairs(mod.options) do
        if opt.type == "header" then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(opt.label))
        elseif opt.type ~= "button" and opt.key then
            RegisterProxy(category, mod, opt)
        end
    end
    return category
end

local function RegisterBlizzardSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON_TITLE)
    rootCategory = category
    layout:AddInitializer(CreateSettingsButtonInitializer("", L.OPEN_WINDOW, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns:OpenWindow()
    end, L.TAGLINE, true))
    for _, opt in ipairs(General.options) do RegisterProxy(category, General, opt) end
    for _, mod in ipairs(ns.moduleOrder) do RegisterModuleCategory(category, mod) end
    Settings.RegisterAddOnCategory(category)
end

function ns:OpenBlizzardSettings()
    if ns.InCombat() then ns:Print(L.NOT_IN_COMBAT); return end
    if rootCategory then Settings.OpenToCategory(rootCategory:GetID()) end
end

---------------------------------------------------------------------------
-- Minimap button (drag around the minimap)
---------------------------------------------------------------------------
local mini

local function PlaceMinimap()
    local angle = math.rad(ns.db.general.minimap.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 8
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function BuildMinimap()
    mini = CreateFrame("Button", "HawarysAddonMinimapButton", Minimap)
    mini:SetSize(32, 32)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mini:RegisterForDrag("LeftButton")
    mini.glow = mini:CreateTexture(nil, "BACKGROUND")
    mini.glow:SetTexture(ns.media .. "glow")
    mini.glow:SetSize(58, 58)
    mini.glow:SetPoint("CENTER")
    mini.glow:SetVertexColor(0.22, 0.78, 0.96, 0)
    mini.icon = W.Icon(mini, "mark", 30)
    mini.icon:SetPoint("CENTER")
    mini:SetScript("OnEnter", function(self)
        self.glow:SetVertexColor(0.22, 0.78, 0.96, 0.55)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.ADDON_TITLE, T.color("accent"))
        GameTooltip:AddLine(L.MINIMAP_BUTTON_DESC, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function(self)
        self.glow:SetVertexColor(0.22, 0.78, 0.96, 0)
        GameTooltip:Hide()
    end)
    mini:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then ns:OpenBlizzardSettings() else ns:ToggleWindow() end
    end)
    mini:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.general.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimap()
        end)
    end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceMinimap()
end

function ns:UpdateMinimapButton()
    if not mini then BuildMinimap() end
    mini:SetShown(ns.db.general.minimap.show)
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------
local toast, queue = nil, {}

local function BuildToast()
    toast = CreateFrame("Frame", "HawarysAddonToast", UIParent)
    toast:SetSize(360, 60)
    toast:SetPoint("TOP", 0, -110)
    toast:SetFrameStrata("DIALOG")
    toast:Hide()
    if T.native() then
        local border = CreateFrame("Frame", nil, toast, "DialogBorderTranslucentTemplate")
        border:SetAllPoints()
    else
        toast.shadow = T.Shape(toast, "shadow", "shadow", "BACKGROUND", -8, true)
        toast.shadow:SetPoint("TOPLEFT", -22, 22)
        toast.shadow:SetPoint("BOTTOMRIGHT", 22, -22)
        toast.bg = T.Shape(toast, "round", "window", "BACKGROUND")
        toast.border = T.Shape(toast, "round_line", "accent2", "BORDER")
    end
    toast.icon = W.Icon(toast, "logo", 36)
    toast.icon:SetPoint("LEFT", 12, 0)
    toast.title = W.Label(toast, "", "h2", "accent")
    toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, -1)
    toast.text = W.Label(toast, "", "small", "text")
    toast.text:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
    toast.text:SetPoint("RIGHT", -12, 0)
    toast.text:SetWordWrap(true)
    toast.text:SetMaxLines(2)

    toast.anim = toast:CreateAnimationGroup()
    local fadeIn = toast.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.2); fadeIn:SetOrder(1)
    local slide = toast.anim:CreateAnimation("Translation")
    slide:SetOffset(0, -10); slide:SetDuration(0.2); slide:SetOrder(1)
    local hold = toast.anim:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(3.4); hold:SetOrder(2)
    local fadeOut = toast.anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.35); fadeOut:SetOrder(3)
    toast.anim:SetScript("OnFinished", function()
        toast:Hide()
        local nextOne = table.remove(queue, 1)
        if nextOne then ns:Toast(nextOne[1], nextOne[2], nextOne[3]) end
    end)
end

-- title, text, optional icon (Media name, texture path or file ID)
function ns:Toast(title, text, icon)
    if not ns.db.general.toasts then
        ns:Print("%s %s", title or "", text or "")
        return
    end
    if not toast then BuildToast() end
    if toast:IsShown() then
        if #queue < 5 then table.insert(queue, { title, text, icon }) end
        return
    end
    toast.title:SetText(title or L.ADDON_TITLE)
    toast.text:SetText(text or "")
    if type(icon) == "string" and not icon:find("\\", 1, true) then icon = ns.media .. icon end
    toast.icon:SetTexture(icon or (ns.media .. "logo"))
    toast:SetAlpha(0)
    toast:Show()
    toast.anim:Restart()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
ns:On("LOGIN", function()
    ns:UpdateMinimapButton()
    ns.Safe(RegisterBlizzardSettings)
end)

ns:On("FIRST_LOGIN", function()
    if ns.db.general.welcome then
        ns:Toast(L.ADDON_TITLE .. "  v" .. ns.version, (L.LOADED:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end
    ns:Print("%s %s", ns.version, L.LOADED)
end)
