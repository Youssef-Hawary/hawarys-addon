-- Hawary's Addon: Bags (Baganator / Altoholic-style item counts across your characters)
-- Read-only: it remembers what each of your characters carries; it never moves items.
local _, ns = ...
local L, U = ns.L, ns.Util

local Bags = ns:NewModule("bags", {
    title = L.MOD_BAGS,
    desc = L.MOD_BAGS_DESC,
    order = 2,
    defaults = { counts = true },
})

Bags.options = {
    { type = "toggle", key = "counts", label = L.BAGS_COUNTS, desc = L.BAGS_COUNTS_DESC },
}

local bankOpen = false

local function Record()
    local key = ns:CharKey()
    local rec = ns.db.chars[key]
    if not rec then
        rec = { bags = {}, bank = {}, worn = {} }
        ns.db.chars[key] = rec
    end
    local _, classFile = UnitClass("player")
    rec.name = UnitName("player")
    rec.class = classFile
    rec.level = UnitLevel("player")
    rec.money = GetMoney()
    rec.updated = time()
    return rec
end

local function ScanContainers(first, last)
    local counts = {}
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts
end

function Bags:ScanBags()
    local rec = Record()
    rec.bags = ScanContainers(Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag or Enum.BagIndex.Bag_4)
end

function Bags:ScanBank()
    if not bankOpen then return end
    local first, last = Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9
    if not first then return end
    local rec = Record()
    rec.bank = ScanContainers(first, last or first)
end

function Bags:ScanWorn()
    local rec = Record()
    local worn = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then worn[id] = (worn[id] or 0) + 1 end
    end
    rec.worn = worn
end

---------------------------------------------------------------------------
-- Tooltip: one line per character "Name   12 (bags / bank / worn)"
---------------------------------------------------------------------------
local function ClassHex(classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    return c and c:GenerateHexColor():sub(3) or "f2f5f9"
end

local function OnTooltipItem(tooltip)
    if not (Bags.enabled and Bags:Get("counts")) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link or ns.IsSecret(link) then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end

    local me = ns:CharKey()
    local rows, total = {}, 0
    for key, rec in pairs(ns.db.chars) do
        local b = rec.bags and rec.bags[itemID] or 0
        local k = rec.bank and rec.bank[itemID] or 0
        local w = rec.worn and rec.worn[itemID] or 0
        local n = b + k + w
        if n > 0 then
            total = total + n
            rows[#rows + 1] = { me = key == me, name = rec.name or key, class = rec.class, n = n, b = b, k = k, w = w }
        end
    end
    if #rows == 0 then return end
    table.sort(rows, function(a, b)
        if a.me ~= b.me then return a.me end
        return a.n > b.n
    end)
    tooltip:AddLine(" ")
    for _, r in ipairs(rows) do
        tooltip:AddDoubleLine("|cff" .. ClassHex(r.class) .. r.name .. "|r",
            string.format("|cfff2f5f9%d|r |cff77808f(%d / %d / %d)|r", r.n, r.b, r.k, r.w))
    end
    if #rows > 1 then
        tooltip:AddDoubleLine("|cff38c6f4Hawary's|r", "|cff38c6f4" .. L.BAGS_TOTAL:format(total) .. "|r")
    end
    tooltip:Show()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Bags:TotalGold()
    local total = 0
    for _, rec in pairs(ns.db.chars) do total = total + (rec.money or 0) end
    return U.thousands(math.floor(total / 10000)) .. "|cffffd700g|r"
end

function Bags:OnInitialize()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        ns.Safe(OnTooltipItem, tooltip)
    end)
    ns:RegisterStat("gold", L.HOME_GOLD, function() return Bags:TotalGold() end, 10)
end

function Bags:OnEnable()
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        self:ScanBags()
        self:ScanBank()
    end)
    self:RegisterEvent("PLAYER_MONEY", function() Record() end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "ScanWorn")
    self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, Record) end)
    self:RegisterEvent("BANKFRAME_OPENED", function()
        bankOpen = true
        C_Timer.After(0.5, function() ns.Safe(Bags.ScanBank, Bags) end)
    end)
    self:RegisterEvent("BANKFRAME_CLOSED", function() bankOpen = false end)
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "ScanBank")
    C_Timer.After(3, function()
        if self.enabled then
            ns.Safe(self.ScanBags, self)
            ns.Safe(self.ScanWorn, self)
        end
    end)
end
