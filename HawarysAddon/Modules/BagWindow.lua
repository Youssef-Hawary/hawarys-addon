-- Hawary's Addon: Bag Window (Bagnon / Baganator style)
-- All your bags in one window, with search, sorting, item levels, upgrade arrows, junk marks,
-- and an offline view of every character's bags and bank. The live slots are Blizzard's own
-- item buttons (ContainerFrameItemButtonTemplate), so right-click to use, drag, shift-click to
-- link and selling work exactly like the default bags. It never moves or uses items by itself
-- (the Sort button calls Blizzard's own sort when YOU click it).
local _, ns = ...
local L, T, W, U = ns.L, ns.Theme, ns.W, ns.Util

local BW = ns:NewModule("bagwindow", {
    title = L.MOD_BAGWIN,
    desc = L.MOD_BAGWIN_DESC,
    order = 22,
    defaults = { replace = true, columns = 10, size = 37, ilvl = true, upgrades = true, junk = true,
        scale = 1, pos = {} },
})

BW.options = {
    { type = "toggle", key = "replace", label = L.BW_REPLACE, desc = L.BW_REPLACE_DESC },
    { type = "slider", key = "columns", label = L.BW_COLUMNS, desc = L.BW_COLUMNS_DESC, min = 6, max = 20, step = 1 },
    { type = "slider", key = "size", label = L.BW_SIZE, desc = L.BW_SIZE_DESC, min = 28, max = 46, step = 1 },
    { type = "slider", key = "scale", label = L.BW_SCALE, desc = L.BW_SCALE_DESC, min = 0.6, max = 1.5, step = 0.05, format = "%.2f" },
    { type = "toggle", key = "ilvl", label = L.BW_ILVL, desc = L.BW_ILVL_DESC },
    { type = "toggle", key = "upgrades", label = L.BW_UPGRADES, desc = L.BW_UPGRADES_DESC },
    { type = "toggle", key = "junk", label = L.BW_JUNK, desc = L.BW_JUNK_DESC },
    { type = "button", label = L.BW_OPEN, desc = L.BW_OPEN_DESC, buttonText = L.OPEN, onClick = function() BW:Toggle() end },
}

local BAGS = { 0, 1, 2, 3, 4, 5 }                 -- backpack, 4 bags, reagent bag
local BANK = { 6, 7, 8, 9, 10, 11, 12, 13, 14 }   -- character bank tabs
local PAD, HEAD, FOOT, GAP = 12, 92, 40, 4

local win
local holders, live = {}, {}      -- live[bag][slot] = Blizzard item button
local offline = {}                 -- plain buttons for the offline view
local view = { char = nil, bank = false, search = "" }
local hiddenParent

---------------------------------------------------------------------------
-- Pure helpers (unit-tested)
---------------------------------------------------------------------------
-- Item name from a link: "|cff...|Hitem:...|h[Linen Cloth]|h|r" -> "Linen Cloth"
function BW.LinkName(link)
    if type(link) ~= "string" then return nil end
    return link:match("|h%[(.-)%]|h")
end

-- Does an item match the search text? Plain, case-insensitive part of the name.
function BW.Matches(search, name)
    if not search or search == "" then return true end
    if not name then return false end
    return name:lower():find(search:lower(), 1, true) ~= nil
end

-- Grid position (1-based index) -> x, y offsets
function BW.GridPos(i, columns, size)
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    return col * (size + GAP), -row * (size + GAP)
end

-- Pack a bag snapshot into saved data: { size = n, [slot] = { link, count } }
function BW.Pack(size, read)
    local out = { size = size }
    for slot = 1, size do
        local link, count = read(slot)
        if link then out[slot] = { link, count or 1 } end
    end
    return out
end

---------------------------------------------------------------------------
-- Saved snapshots (for the offline view of other characters)
---------------------------------------------------------------------------
local function CharRecord(key)
    key = key or ns:CharKey()
    local rec = ns.db.chars[key]
    if not rec then
        local _, classFile = UnitClass("player")
        rec = { name = UnitName("player"), class = classFile, bags = {}, bank = {}, worn = {} }
        ns.db.chars[key] = rec
    end
    rec.slots = rec.slots or { bags = {}, bank = {} }
    return rec
end

local function Snapshot(list, into)
    for _, bag in ipairs(list) do
        local size = C_Container.GetContainerNumSlots(bag)
        into[bag] = BW.Pack(size, function(slot)
            local info = C_Container.GetContainerItemInfo(bag, slot)
            return info and info.hyperlink, info and info.stackCount
        end)
    end
end

function BW:SaveBags() Snapshot(BAGS, CharRecord().slots.bags) end
function BW:SaveBank() if self.bankOpen then Snapshot(BANK, CharRecord().slots.bank) end end

---------------------------------------------------------------------------
-- Slot decorations shared by live and offline buttons
---------------------------------------------------------------------------
local function Decorate(b, link, quality)
    if not b.hwIlvl then
        b.hwIlvl = b:CreateFontString(nil, "OVERLAY")
        b.hwIlvl:SetFontObject(T.font("tag"))
        b.hwIlvl:SetPoint("TOPLEFT", 2, -2)
        b.hwArrow = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.hwArrow:SetTexture(ns.media .. "arrow")
        b.hwArrow:SetSize(14, 14)
        b.hwArrow:SetPoint("TOPRIGHT", -1, -1)
        b.hwArrow:SetVertexColor(0.29, 0.87, 0.5)
        b.hwJunk = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.hwJunk:SetTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up")
        b.hwJunk:SetSize(14, 14)
        b.hwJunk:SetPoint("BOTTOMLEFT", 2, 2)
    end
    local ilvlText, arrow, junk = nil, false, false
    if link then
        local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(link)
        if BW:Get("ilvl") and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" and (classID == 2 or classID == 4) then
            local lvl = C_Item.GetDetailedItemLevelInfo(link)
            if lvl and lvl > 1 then ilvlText = tostring(lvl) end
        end
        local gear = ns.modules.gear
        if BW:Get("upgrades") and gear and gear.enabled then
            local ok, r = pcall(gear.Evaluate, gear, link)
            arrow = ok and r and (r.kind == "upgrade" or r.kind == "empty") or false
        end
        junk = BW:Get("junk") and quality == Enum.ItemQuality.Poor
    end
    b.hwIlvl:SetText(ilvlText or "")
    if quality and ilvlText then
        local r, g, bl = C_Item.GetItemQualityColor(quality)
        b.hwIlvl:SetTextColor(r or 1, g or 1, bl or 1)
    end
    b.hwArrow:SetShown(arrow and true or false)
    b.hwJunk:SetShown(junk and true or false)
end

local function Fade(b, name)
    b:SetAlpha(BW.Matches(view.search, name) and 1 or 0.18)
end

---------------------------------------------------------------------------
-- Live bag slots (Blizzard item buttons; only created/moved out of combat)
---------------------------------------------------------------------------
local function call(obj, method, ...)
    local fn = obj[method]
    if fn then pcall(fn, obj, ...) end
end

local function LiveButton(bag, slot)
    live[bag] = live[bag] or {}
    local b = live[bag][slot]
    if b then return b end
    local holder = holders[bag]
    if not holder then
        holder = CreateFrame("Frame", nil, win.grid)
        holder:SetID(bag)       -- the item button reads its bag from the parent's ID
        holder:SetAllPoints()
        holders[bag] = holder
    end
    b = CreateFrame("ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
    b:SetID(slot)
    live[bag][slot] = b
    return b
end

local function UpdateLive(b, bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local texture = info and info.iconFileID
    local link = info and info.hyperlink
    local quality = info and info.quality
    call(b, "SetHasItem", texture)
    call(b, "SetItemButtonTexture", texture)
    call(b, "SyncAppearanceWithHasItem")
    SetItemButtonQuality(b, quality, link, false, info and info.isBound)
    SetItemButtonCount(b, info and info.stackCount)
    SetItemButtonDesaturated(b, info and info.isLocked)
    local q = C_Container.GetContainerItemQuestInfo(bag, slot)
    if q then call(b, "UpdateQuestItem", q.isQuestItem, q.questID, q.isActive) end
    call(b, "UpdateCooldown", texture)
    call(b, "SetReadable", info and info.isReadable)
    Decorate(b, link, quality)
    Fade(b, BW.LinkName(link))
end

---------------------------------------------------------------------------
-- Offline slots (plain buttons with an icon, count and tooltip)
---------------------------------------------------------------------------
local function OfflineButton(i)
    local b = offline[i]
    if b then return b end
    b = CreateFrame("Button", nil, win.grid)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.border:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) if self.link then HandleModifiedItemClick(self.link) end end)
    offline[i] = b
    return b
end

local function UpdateOffline(b, entry)
    local link, count = entry and entry[1], entry and entry[2]
    b.link = link
    local itemID = link and C_Item.GetItemInfoInstant(link)
    b.icon:SetTexture(itemID and C_Item.GetItemIconByID(itemID) or nil)
    b.count:SetText((count and count > 1) and tostring(count) or "")
    local quality = itemID and C_Item.GetItemQualityByID(itemID)
    if quality and quality >= 2 then
        local r, g, bl = C_Item.GetItemQualityColor(quality)
        b.border:SetVertexColor(r or 1, g or 1, bl or 1)
        b.border:Show()
    else
        b.border:Hide()
    end
    Decorate(b, link, quality)
    Fade(b, BW.LinkName(link))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function IsMe() return view.char == nil or view.char == ns:CharKey() end

function BW:Build()
    if win then return win end
    win = CreateFrame("Frame", "HawarysAddonBags", UIParent)
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:Hide()
    tinsert(UISpecialFrames, "HawarysAddonBags")
    local pos = self:Get("pos")
    if pos and pos.point then
        win:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        win:SetPoint("BOTTOMRIGHT", -80, 110)
    end
    win.bg = T.Shape(win, "round", "window", "BACKGROUND", 0)
    win.border = T.Shape(win, "round_line", "line", "BORDER", 0)

    local head = CreateFrame("Frame", nil, win)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", -40, 0)
    head:SetHeight(40)
    head:EnableMouse(true)
    head:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then win:StartMoving() end end)
    head:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        local p, _, rp, x, y = win:GetPoint(1)
        BW:DB().pos = { point = p, relPoint = rp, x = x, y = y }
    end)
    win.logo = head:CreateTexture(nil, "ARTWORK")
    win.logo:SetTexture(ns.media .. "logo")
    win.logo:SetSize(22, 22)
    win.logo:SetPoint("LEFT", PAD, 0)
    win.title = W.Label(head, "", "h2", "text")
    win.title:SetPoint("LEFT", win.logo, "RIGHT", 8, 0)

    win.close = CreateFrame("Button", nil, win)
    win.close:SetSize(24, 24)
    win.close:SetPoint("TOPRIGHT", -8, -8)
    win.close.icon = W.Icon(win.close, "x", 16, "text3")
    win.close.icon:SetPoint("CENTER")
    win.close:SetScript("OnClick", function() win:Hide() end)

    -- Character picker + bank toggle (Bagnon's "see any character's bags")
    win.charDrop = W.Dropdown(win, 150, function()
        local out = {}
        for _, key in ipairs(U.sortedKeys(ns.db.chars)) do
            local rec = ns.db.chars[key]
            if rec.slots or key == ns:CharKey() then out[#out + 1] = { value = key, text = rec.name or key } end
        end
        return out
    end, function() return view.char or ns:CharKey() end, function(v)
        view.char = (v ~= ns:CharKey()) and v or nil
        BW:Layout()
    end)
    win.charDrop:SetPoint("TOPLEFT", PAD, -46)
    win.bankBtn = W.Button(win, L.BW_BANK, "secondary", 70, 22)
    win.bankBtn:SetPoint("LEFT", win.charDrop, "RIGHT", 6, 0)
    win.bankBtn:SetScript("OnClick", function() view.bank = not view.bank; BW:Layout() end)

    win.search = W.EditBox(win, 160, 22)
    win.search:SetPoint("TOPRIGHT", -PAD, -46)
    win.search.edit:SetScript("OnTextChanged", function(self)
        view.search = U.trim(self:GetText() or "")
        BW:Refresh()
    end)
    win.searchHint = W.Label(win.search, L.BW_SEARCH, "small", "text3")
    win.searchHint:SetPoint("LEFT", 8, 0)
    win.search.edit:HookScript("OnEditFocusGained", function() win.searchHint:Hide() end)
    win.search.edit:HookScript("OnEditFocusLost", function(self) win.searchHint:SetShown(self:GetText() == "") end)

    win.grid = CreateFrame("Frame", nil, win)
    win.grid:SetPoint("TOPLEFT", PAD, -HEAD)

    win.money = W.Label(win, "", "body", "text")
    win.money:SetPoint("BOTTOMLEFT", PAD, 14)
    win.free = W.Label(win, "", "small", "text3")
    win.free:SetPoint("LEFT", win.money, "RIGHT", 12, 0)
    win.sort = W.Button(win, L.BW_SORT, "secondary", 70, 22)
    win.sort:SetPoint("BOTTOMRIGHT", -PAD, 10)
    win.sort:SetScript("OnClick", function()
        if ns.InCombat() then return end
        if view.bank and BW.bankOpen then C_Container.SortBankBags() else C_Container.SortBags() end
    end)

    win:SetScript("OnShow", function() BW:Layout() end)
    win:SetScript("OnHide", function()
        win.search:SetText("")
        view.char, view.bank = nil, false
        -- keep Blizzard's "bags are open" state in step with our window
        if BW:Get("replace") and IsBagOpen(0) then CloseAllBags() end
    end)
    return win
end

-- Lay out the grid for the current view. Live slot buttons are only (re)placed out of combat.
function BW:Layout()
    if not (win and win:IsShown()) then return end
    if ns.InCombat() then self.dirty = true; self:Refresh(); return end
    self.dirty = false
    local size, cols = self:Get("size"), self:Get("columns")
    win:SetScale(self:Get("scale"))
    local rec = view.char and ns.db.chars[view.char]
    win.title:SetText((rec and rec.name or UnitName("player")) .. " · " .. (view.bank and L.BW_BANK or L.MOD_BAGS))
    win.sort:SetShown(IsMe() and (not view.bank or self.bankOpen) and true or false)
    win.bankBtn:SetLabel(view.bank and L.MOD_BAGS or L.BW_BANK)

    for _, b in ipairs(offline) do b:Hide() end
    for _, slots in pairs(live) do for _, b in pairs(slots) do b:Hide() end end

    local i = 0
    local useLive = IsMe() and (not view.bank or self.bankOpen) and true or false
    if useLive then
        for _, bag in ipairs(view.bank and BANK or BAGS) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                i = i + 1
                local b = LiveButton(bag, slot)
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", win.grid, "TOPLEFT", BW.GridPos(i, cols, size))
                b:Show()
            end
        end
    else
        local data = CharRecord(view.char).slots[view.bank and "bank" or "bags"] or {}
        for _, bag in ipairs(view.bank and BANK or BAGS) do
            local snap = data[bag]
            for slot = 1, snap and snap.size or 0 do
                i = i + 1
                local b = OfflineButton(i)
                b.entry = snap[slot]
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", win.grid, "TOPLEFT", BW.GridPos(i, cols, size))
                b:Show()
            end
        end
    end
    self.useLive = useLive
    self.slotCount = i
    local rowsN = math.max(1, math.ceil(i / cols))
    local gridW, gridH = cols * (size + GAP) - GAP, rowsN * (size + GAP) - GAP
    win.grid:SetSize(gridW, gridH)
    win:SetSize(math.max(gridW + PAD * 2, 420), gridH + HEAD + FOOT + 6)
    self:Refresh()
end

-- Repaint icons, counts, search fading and the footer (safe in combat).
function BW:Refresh()
    if not (win and win:IsShown()) then return end
    if self.useLive then
        for _, bag in ipairs(view.bank and BANK or BAGS) do
            for slot, b in pairs(live[bag] or {}) do
                if b:IsShown() then UpdateLive(b, bag, slot) end
            end
        end
    else
        for _, b in ipairs(offline) do if b:IsShown() then UpdateOffline(b, b.entry) end end
    end
    local rec = view.char and ns.db.chars[view.char]
    win.money:SetText(U.money(rec and rec.money or GetMoney()))
    if (self.slotCount or 0) == 0 then
        win.free:SetText(L.BW_NO_DATA)
    elseif IsMe() and not view.bank then
        local free, total = 0, 0
        for _, bag in ipairs(BAGS) do
            free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
            total = total + C_Container.GetContainerNumSlots(bag)
        end
        win.free:SetText(L.BW_FREE:format(free, total))
    else
        win.free:SetText(self.useLive and "" or L.BW_OFFLINE)
    end
end

function BW:Toggle()
    if not self.enabled then ns:SetModuleEnabled("bagwindow", true) end
    self:Build()
    win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------------
-- Replace Blizzard's bags: hide their frames and follow their open/closed state
---------------------------------------------------------------------------
local function AnyBagOpen()
    for _, bag in ipairs(BAGS) do if IsBagOpen(bag) then return true end end
    return false
end

local syncQueued = false
local function SyncWithBlizzard()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, function()
        syncQueued = false
        if not (BW.enabled and BW:Get("replace")) then return end
        BW:Build()
        local want = AnyBagOpen()
        if want ~= win:IsShown() then win:SetShown(want) end
    end)
end

local function EachBlizzardBagFrame(fn)
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        if f then fn(f) end
    end
    if ContainerFrameCombinedBags then fn(ContainerFrameCombinedBags) end
end

function BW:HideBlizzardBags()
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame")
        hiddenParent:Hide()
    end
    EachBlizzardBagFrame(function(f)
        if not f.hwOldParent then
            f.hwOldParent = f:GetParent()
            f:SetParent(hiddenParent)
        end
    end)
end

function BW:RestoreBlizzardBags()
    EachBlizzardBagFrame(function(f)
        if f.hwOldParent then f:SetParent(f.hwOldParent); f.hwOldParent = nil end
    end)
end

function BW:ApplyReplace()
    ns:RunOutOfCombat("bagwindow-replace", function()
        if BW.enabled and BW:Get("replace") then BW:HideBlizzardBags() else BW:RestoreBlizzardBags() end
    end)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function BW:OnInitialize()
    for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBackpack", "OpenBackpack",
        "CloseBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
        hooksecurefunc(fn, SyncWithBlizzard)
    end
    ns:RegisterSlash("inv", L.BW_SLASH, function() BW:Toggle() end)
end

function BW:OnEnable()
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        self:SaveBags()
        self:SaveBank()
        self:Layout()
    end)
    self:RegisterEvent("ITEM_LOCK_CHANGED", function() self:Refresh() end)
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() self:Refresh() end)
    self:RegisterEvent("PLAYER_MONEY", function() self:Refresh() end)
    self:RegisterEvent("BANKFRAME_OPENED", function()
        self.bankOpen = true
        C_Timer.After(0.5, function() ns.Safe(BW.SaveBank, BW) end)
        self:Layout()
    end)
    self:RegisterEvent("BANKFRAME_CLOSED", function()
        self.bankOpen = false
        view.bank = false
        self:Layout()
    end)
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() self:SaveBank(); self:Refresh() end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if self.dirty then self:Layout() end end)
    self:Build()
    self:ApplyReplace()
    C_Timer.After(2, function() if self.enabled then ns.Safe(self.SaveBags, self) end end)
end

function BW:OnDisable()
    if win then win:Hide() end
    self:ApplyReplace()
end

function BW:OnSettingChanged(key)
    if key == "replace" then self:ApplyReplace() end
    self:Layout()
end
