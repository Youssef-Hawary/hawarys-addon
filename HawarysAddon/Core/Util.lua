-- Hawary's Addon: pure helpers (no WoW API here, so tests can load this file directly)
local _, ns = ...

local U = {}
ns.Util = U

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, strbyte, strchar, strsub, strfind, strformat = math.floor, string.byte, string.char, string.sub, string.find, string.format
local tconcat = table.concat

-- Deep copy of plain data tables.
function U.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = U.copy(v) end
    return out
end

-- Fill in keys missing from `target` with copies of `defaults` (recursively).
-- A saved `false` stays false; a value of the wrong type is replaced by the default.
function U.mergeDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for k, def in pairs(defaults) do
        local cur = target[k]
        if cur == nil then
            target[k] = U.copy(def)
        elseif type(def) == "table" then
            if type(cur) ~= "table" then
                target[k] = U.copy(def)
            else
                U.mergeDefaults(cur, def)
            end
        elseif type(cur) ~= type(def) then
            target[k] = def
        end
    end
    return target
end

function U.clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

function U.round(x, decimals)
    local m = 10 ^ (decimals or 0)
    return floor(x * m + 0.5) / m
end

function U.trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split text into lines (handles \r\n).
function U.lines(s)
    local out = {}
    s = (s or ""):gsub("\r\n", "\n")
    for line in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    return out
end

function U.thousands(n)
    local formatted, k = tostring(floor(n)), nil
    repeat
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return formatted
end

-- Copper -> "12g 34s 5c" with WoW coin colors. Plain text when `plain` is true.
function U.money(copper, plain)
    copper = floor(tonumber(copper) or 0)
    local neg = copper < 0
    if neg then copper = -copper end
    local g = floor(copper / 10000)
    local s = floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
    if plain then G, S, C = "g", "s", "c" end
    if g > 0 then parts[#parts + 1] = U.thousands(g) .. G end
    if s > 0 then parts[#parts + 1] = s .. S end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. C end
    return (neg and "-" or "") .. tconcat(parts, " ")
end

-- Hex "38c6f4" -> r, g, b (0..1)
function U.hex(h)
    h = h:gsub("#", "")
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

---------------------------------------------------------------------------
-- Base64 (pure Lua 5.1, no bit library needed)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INV = {}
for i = 1, 64 do B64INV[strbyte(B64, i)] = i - 1 end

function U.base64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = strbyte(data, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(n / 262144) % 64
        local c2 = floor(n / 4096) % 64
        local c3 = floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = strsub(B64, c1 + 1, c1 + 1) .. strsub(B64, c2 + 1, c2 + 1)
            .. (b and strsub(B64, c3 + 1, c3 + 1) or "=")
            .. (c and strsub(B64, c4 + 1, c4 + 1) or "=")
    end
    return tconcat(out)
end

function U.base64decode(text)
    text = text:gsub("[^%w%+/=]", "")
    if #text == 0 or #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local n, pad = 0, 0
        for j = 0, 3 do
            local ch = strbyte(text, i + j)
            local v
            if ch == 61 then -- '='
                v = 0
                pad = pad + 1
            else
                if pad > 0 then return nil end -- data after padding
                v = B64INV[ch]
                if not v then return nil end
            end
            n = n * 64 + v
        end
        local a = floor(n / 65536) % 256
        local b = floor(n / 256) % 256
        local c = n % 256
        if pad == 0 then
            out[#out + 1] = strchar(a, b, c)
        elseif pad == 1 then
            out[#out + 1] = strchar(a, b)
        else
            out[#out + 1] = strchar(a)
        end
    end
    return tconcat(out)
end

---------------------------------------------------------------------------
-- Tiny safe serializer for plain data (strings, numbers, booleans, tables).
-- Never uses loadstring, so an imported string can't run code.
---------------------------------------------------------------------------
local function ser(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "n" .. strformat("%.14g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do
            ser(i, out)
            ser(v[i], out)
        end
        local keys = {}
        for k in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and floor(k) == k) then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            ser(k, out)
            ser(v[k], out)
        end
        out[#out + 1] = "}"
    else
        error("cannot serialize " .. t)
    end
end

function U.serialize(v)
    local out = {}
    ser(v, out)
    return tconcat(out)
end

local function deser(s, pos, depth)
    if depth > 20 then return nil, pos, "too deep" end
    local tag = strsub(s, pos, pos)
    if tag == "s" then
        local colon = strfind(s, ":", pos + 1, true)
        if not colon then return nil, pos, "bad string" end
        local len = tonumber(strsub(s, pos + 1, colon - 1))
        if not len or len < 0 or len ~= floor(len) then return nil, pos, "bad length" end
        local str = strsub(s, colon + 1, colon + len)
        if #str ~= len then return nil, pos, "short string" end
        return str, colon + len + 1
    elseif tag == "n" then
        local semi = strfind(s, ";", pos + 1, true)
        if not semi then return nil, pos, "bad number" end
        local num = tonumber(strsub(s, pos + 1, semi - 1))
        if not num then return nil, pos, "bad number" end
        return num, semi + 1
    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "{" then
        local tbl = {}
        pos = pos + 1
        while strsub(s, pos, pos) ~= "}" do
            if pos > #s then return nil, pos, "unterminated table" end
            local k, v, err
            k, pos, err = deser(s, pos, depth + 1)
            if k == nil then return nil, pos, err or "bad key" end
            v, pos, err = deser(s, pos, depth + 1)
            if v == nil then return nil, pos, err or "bad value" end
            tbl[k] = v
        end
        return tbl, pos + 1
    end
    return nil, pos, "unknown tag"
end

-- Returns value, or nil + error message
function U.deserialize(s)
    if type(s) ~= "string" or s == "" then return nil, "empty" end
    local ok, value, pos, err = pcall(deser, s, 1, 0)
    if not ok then return nil, tostring(value) end
    if value == nil then return nil, err end
    if pos ~= #s + 1 then return nil, "trailing data" end
    return value
end

function U.sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end
