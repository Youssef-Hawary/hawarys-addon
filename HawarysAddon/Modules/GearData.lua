-- Hawary's Addon: gear scoring data and math (no WoW API, so it is unit-tested)
local _, ns = ...

local D = {}
ns.GearData = D

-- Item stat keys returned by C_Item.GetItemStats
D.STAT = {
    STR = "ITEM_MOD_STRENGTH_SHORT",
    AGI = "ITEM_MOD_AGILITY_SHORT",
    STA = "ITEM_MOD_STAMINA_SHORT",
    INT = "ITEM_MOD_INTELLECT_SHORT",
    SPI = "ITEM_MOD_SPIRIT_SHORT",
    CRIT = "ITEM_MOD_CRIT_RATING_SHORT",
    HASTE = "ITEM_MOD_HASTE_RATING_SHORT",
    MASTERY = "ITEM_MOD_MASTERY_RATING_SHORT",
    VERS = "ITEM_MOD_VERSATILITY",
    HIT = "ITEM_MOD_HIT_RATING_SHORT",
    AP = "ITEM_MOD_ATTACK_POWER_SHORT",
    SP = "ITEM_MOD_SPELL_POWER_SHORT",
    HEAL = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    MP5 = "ITEM_MOD_MANA_REGENERATION_SHORT",
    DEF = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    DODGE = "ITEM_MOD_DODGE_RATING_SHORT",
    PARRY = "ITEM_MOD_PARRY_RATING_SHORT",
    BLOCK = "ITEM_MOD_BLOCK_RATING_SHORT",
    ARMOR = "RESISTANCE0_NAME",
    DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
}

-- primaryStat values from C_SpecializationInfo.GetSpecializationInfo
D.PRIMARY = { [1] = "STR", [2] = "AGI", [4] = "INT" }

-- Starter weights per class and role. Tunable; /ha stats prints an item's raw keys.
local P = {}
P.WARRIOR = {
    { id = "WARRIOR_DPS", label = "Damage", role = "DAMAGER", stat = "STR",
      w = { STR = 1.0, AGI = 0.5, STA = 0.3, CRIT = 0.8, HIT = 0.9, HASTE = 0.6, MASTERY = 0.5, VERS = 0.5, AP = 0.45, DPS = 3.0, ARMOR = 0.01 } },
    { id = "WARRIOR_TANK", label = "Tank", role = "TANK", stat = "STR",
      w = { STA = 1.0, STR = 0.6, AGI = 0.4, ARMOR = 0.05, DEF = 0.9, DODGE = 0.8, PARRY = 0.8, BLOCK = 0.5, HIT = 0.4, VERS = 0.6, MASTERY = 0.5, DPS = 1.0 } },
}
P.PALADIN = {
    { id = "PALADIN_HOLY", label = "Healer", role = "HEALER", stat = "INT",
      w = { INT = 1.0, SPI = 0.5, STA = 0.2, CRIT = 0.6, HASTE = 0.5, MASTERY = 0.4, VERS = 0.4, SP = 0.8, HEAL = 0.8, MP5 = 1.5 } },
    { id = "PALADIN_TANK", label = "Tank", role = "TANK", stat = "STR",
      w = { STA = 1.0, STR = 0.6, AGI = 0.3, INT = 0.2, ARMOR = 0.05, DEF = 0.9, DODGE = 0.8, PARRY = 0.8, BLOCK = 0.6, HIT = 0.4, VERS = 0.6, DPS = 1.0 } },
    { id = "PALADIN_RET", label = "Damage", role = "DAMAGER", stat = "STR",
      w = { STR = 1.0, AGI = 0.4, INT = 0.2, STA = 0.3, CRIT = 0.8, HIT = 0.9, HASTE = 0.6, AP = 0.45, SP = 0.2, DPS = 3.0, ARMOR = 0.01 } },
}
P.HUNTER = {
    { id = "HUNTER_DPS", label = "Damage", role = "DAMAGER", stat = "AGI",
      w = { AGI = 1.0, INT = 0.2, STA = 0.3, CRIT = 0.8, HIT = 0.9, HASTE = 0.6, MASTERY = 0.5, VERS = 0.5, AP = 0.45, DPS = 2.5, ARMOR = 0.01 } },
}
P.ROGUE = {
    { id = "ROGUE_DPS", label = "Damage", role = "DAMAGER", stat = "AGI",
      w = { AGI = 1.0, STR = 0.3, STA = 0.3, CRIT = 0.8, HIT = 1.0, HASTE = 0.7, MASTERY = 0.5, VERS = 0.5, AP = 0.45, DPS = 3.0, ARMOR = 0.01 } },
}
P.PRIEST = {
    { id = "PRIEST_HEAL", label = "Healer", role = "HEALER", stat = "INT",
      w = { INT = 1.0, SPI = 0.8, SP = 0.8, HEAL = 0.8, MP5 = 1.5, STA = 0.2, CRIT = 0.5, HASTE = 0.5, MASTERY = 0.4, VERS = 0.4 } },
    { id = "PRIEST_SHADOW", label = "Damage", role = "DAMAGER", stat = "INT",
      w = { INT = 1.0, SPI = 0.4, SP = 1.0, HIT = 1.0, CRIT = 0.6, HASTE = 0.7, MASTERY = 0.5, VERS = 0.5, STA = 0.3 } },
}
P.SHAMAN = {
    { id = "SHAMAN_ELE", label = "Caster", role = "DAMAGER", stat = "INT",
      w = { INT = 1.0, SP = 1.0, HIT = 1.0, CRIT = 0.7, HASTE = 0.6, MASTERY = 0.5, SPI = 0.2, STA = 0.3, MP5 = 0.8 } },
    { id = "SHAMAN_ENH", label = "Melee", role = "DAMAGER", stat = "AGI",
      w = { AGI = 0.9, STR = 0.9, INT = 0.3, STA = 0.3, CRIT = 0.8, HIT = 0.9, HASTE = 0.6, AP = 0.45, DPS = 3.0, ARMOR = 0.01 } },
    { id = "SHAMAN_RESTO", label = "Healer", role = "HEALER", stat = "INT",
      w = { INT = 1.0, MP5 = 1.5, SP = 0.8, HEAL = 0.8, SPI = 0.3, CRIT = 0.5, HASTE = 0.5, STA = 0.2 } },
}
P.MAGE = {
    { id = "MAGE_DPS", label = "Damage", role = "DAMAGER", stat = "INT",
      w = { INT = 1.0, SP = 1.0, HIT = 1.0, CRIT = 0.7, HASTE = 0.7, MASTERY = 0.5, VERS = 0.5, SPI = 0.3, STA = 0.3 } },
}
P.WARLOCK = {
    { id = "WARLOCK_DPS", label = "Damage", role = "DAMAGER", stat = "INT",
      w = { INT = 0.9, SP = 1.0, HIT = 1.0, STA = 0.5, CRIT = 0.6, HASTE = 0.7, MASTERY = 0.5, VERS = 0.5, SPI = 0.3 } },
}
P.DRUID = {
    { id = "DRUID_BALANCE", label = "Caster", role = "DAMAGER", stat = "INT",
      w = { INT = 1.0, SP = 1.0, HIT = 1.0, CRIT = 0.7, HASTE = 0.6, MASTERY = 0.5, SPI = 0.4, STA = 0.3 } },
    { id = "DRUID_FERAL", label = "Feral", role = "DAMAGER", stat = "AGI",
      w = { AGI = 1.0, STR = 0.6, STA = 0.3, CRIT = 0.8, HIT = 0.9, HASTE = 0.5, AP = 0.45, DPS = 0.3, ARMOR = 0.01 } },
    { id = "DRUID_BEAR", label = "Tank", role = "TANK", stat = "AGI",
      w = { STA = 1.0, AGI = 0.8, ARMOR = 0.08, DODGE = 0.8, STR = 0.4, DEF = 0.8, HIT = 0.3, DPS = 0.2 } },
    { id = "DRUID_RESTO", label = "Healer", role = "HEALER", stat = "INT",
      w = { INT = 1.0, SPI = 0.9, SP = 0.8, HEAL = 0.8, MP5 = 1.5, STA = 0.2, CRIT = 0.4, HASTE = 0.5 } },
}
D.profiles = P

D.GENERIC = { id = "GENERIC", label = "Balanced", role = "DAMAGER",
    w = { STR = 1.0, AGI = 1.0, INT = 1.0, STA = 0.5, SPI = 0.3, CRIT = 0.6, HASTE = 0.6, MASTERY = 0.5, VERS = 0.5, HIT = 0.6, AP = 0.4, SP = 0.6, DPS = 2.0, ARMOR = 0.01 } }

function D.FindProfile(id)
    for _, list in pairs(P) do
        for _, p in ipairs(list) do if p.id == id then return p end end
    end
    if id == D.GENERIC.id then return D.GENERIC end
end

-- override: profile id or "auto"; role / primaryStatIndex come from the active spec (may be nil)
function D.PickProfile(classFile, role, primaryStatIndex, override)
    if override and override ~= "auto" then
        local p = D.FindProfile(override)
        if p then return p end
    end
    local list = P[classFile]
    if not list then return D.GENERIC end
    local stat = primaryStatIndex and D.PRIMARY[primaryStatIndex]
    if role then
        for _, p in ipairs(list) do
            if p.role == role and (not stat or p.stat == stat) then return p end
        end
        for _, p in ipairs(list) do if p.role == role then return p end end
    end
    -- no spec info (e.g. low level): prefer the damage profile
    for _, p in ipairs(list) do if p.role == "DAMAGER" then return p end end
    return list[1]
end

-- stats: table from C_Item.GetItemStats; profile: from PickProfile
function D.Score(stats, profile)
    if not stats then return nil end
    local total = 0
    for short, weight in pairs(profile.w) do
        local v = stats[D.STAT[short]]
        if type(v) == "number" then total = total + v * weight end
    end
    return total
end

-- Equip location -> inventory slot ids it can go in
D.SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Heaviest armor (Enum.ItemArmorSubclass) a class wears; classic rules switch at level 40.
local ARMOR = {
    WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, HUNTER = { 2, 3 }, SHAMAN = { 2, 3 },
    ROGUE = { 2, 2 }, DRUID = { 2, 2 }, PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 },
}
function D.MaxArmor(classFile, level)
    local a = ARMOR[classFile]
    if not a then return 4 end
    return (level or 1) >= 40 and a[2] or a[1]
end

-- Weapon subclasses (Enum.ItemWeaponSubclass) per class. Unknown classes allow everything.
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE = { 0, 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID = { 4, 5, 6, 10, 13, 15 },
}
local weaponSets = {}
for class, list in pairs(WEAPONS) do
    weaponSets[class] = {}
    for _, sub in ipairs(list) do weaponSets[class][sub] = true end
end

-- classID / subclassID from C_Item.GetItemInfoInstant (2 = weapon, 4 = armor)
function D.CanWear(classFile, level, classID, subclassID)
    if classID == 4 then
        if subclassID >= 1 and subclassID <= 4 then return subclassID <= D.MaxArmor(classFile, level) end
        if subclassID == 6 then -- shield
            return classFile == "WARRIOR" or classFile == "PALADIN" or classFile == "SHAMAN" or WEAPONS[classFile] == nil
        end
        return true
    elseif classID == 2 then
        if subclassID == 20 then return false end -- a fishing pole is never a gear upgrade
        local set = weaponSets[classFile]
        return set == nil or set[subclassID] == true
    end
    return true
end

-- newScore vs the scores of what's equipped in the candidate slots.
-- equipped: list of scores, `false` for an empty slot. Returns kind, pct
-- kind: "empty" | "upgrade" | "same" | "downgrade"
function D.Compare(newScore, equipped)
    if not newScore then return nil end
    local weakest
    for _, s in ipairs(equipped) do
        if s == false then return "empty", 100 end
        if weakest == nil or s < weakest then weakest = s end
    end
    if weakest == nil then return "empty", 100 end
    local base = math.max(weakest, 1)
    local pct = (newScore - weakest) / base * 100
    if pct >= 1 then return "upgrade", pct end
    if pct <= -1 then return "downgrade", pct end
    return "same", 0
end

-- choices: { {index=, kind=, pct=, value=} } -> index, reason ("upgrade" | "value")
function D.BestReward(choices)
    local best, bestPct
    for _, c in ipairs(choices) do
        if c.kind == "upgrade" or c.kind == "empty" then
            local pct = c.kind == "empty" and 1000 or c.pct
            if not bestPct or pct > bestPct then best, bestPct = c.index, pct end
        end
    end
    if best then return best, "upgrade" end
    local bestValue
    for _, c in ipairs(choices) do
        if (c.value or 0) > 0 and (not bestValue or c.value > bestValue) then best, bestValue = c.index, c.value end
    end
    if best then return best, "value" end
    return nil
end
