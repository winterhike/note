--[[ BAC v9 - find the encryptor via getgc fingerprint (NOT the call stack).
     The FireServer call site has no Lua parent frame for the AC sender, so
     debug.getinfo from inside our hook can't reach it. But the encryptor is
     a Lua closure GC-reachable from globals: it has 5+ upvalues, holds the
     BAC RemoteEvent (often nested in a table), AND at least one big int->int
     (0..255) table of >=500 entries (the obfuscator data segment).

     We do ONE getgc pass, score every closure by that fingerprint, dump the
     winner's upvalues to bac_dump.lua + bac_up*.lua. Also keeps the FakeIndex
     canary + beat-capture going.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp                = Players.LocalPlayer

local remote =
 ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("BAC")
if not remote then
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "BAC" and d:IsA("RemoteEvent") then remote = d break end
    end
end
assert(remote, "no BAC remote")

local file = "bac_beats.txt"
pcall(writefile, file, string.format("# name=%s userid=%d f2=%d f4=%d\n# nonce_dec,seq,digest_hex\n",
    lp.Name, lp.UserId, lp.UserId * 2, lp.UserId * 4))

local function logBeat(s)
    local b, i = {}, 1
    while i <= #s do
        local n = s:match("^!(%d+)!", i)
        if n then b[#b+1] = tonumber(n); i = i + #n + 2 else b[#b+1] = s:byte(i); i = i + 1 end
    end
    local nonce = (b[1] or 0) + (b[2] or 0) * 256
    local seq = b[3]
    local dash; for j = 1, #b do if b[j] == 0x2D then dash = j break end end
    local hx = {}; if dash then for j = dash + 1, #b do hx[#hx+1] = string.format("%02x", b[j]) end end
    pcall(appendfile, file, string.format("%d,%s,%s\n", nonce, tostring(seq), table.concat(hx)))
end

-- canary
do
    local Old; Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getnamecallmethod() == "FakeIndex" then
            return false, 'FakeIndex is not a valid member of DataModel "Ugc"'
        end
        return Old(self, ...)
    end))
end

-- beat logger (FireServer hook)
local hookfn = hookfunction or replaceclosure
do
    local fs = remote.FireServer
    local old; old = hookfn(fs, newcclosure(function(self, ...)
        if self == remote then
            local a1 = (...)
            if type(a1) == "string" and #a1 > 0 then pcall(logBeat, a1) end
        end
        return old(self, ...)
    end))
end

-- ===== ENCRYPTOR HUNT (getgc fingerprint, no stack walk) =====
local function isByteTable(t, minN)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, v in pairs(t) do
        if type(k) ~= "number" or type(v) ~= "number" then return false end
        if v < 0 or v > 255 or v ~= math.floor(v) then return false end
        n += 1
        if n >= (minN or 50) then return true end
    end
    return false
end

local function holdsRemote(ups)
    for _, u in pairs(ups) do
        if u == remote then return true end
        if type(u) == "table" then
            for _, vv in pairs(u) do if vv == remote then return true end end
        end
    end
    return false
end

local function serial(t, name)
    local parts = { "local " .. name .. " = {" }
    local keys = {}; for k in pairs(t) do keys[#keys+1] = k end
    -- numeric-first sort
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return tostring(a) < tostring(b) end
        return type(a) == "number"
    end)
    for _, k in ipairs(keys) do
        local v = t[k]
        local kr = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
        local vr
        if type(v) == "number" or type(v) == "boolean" then vr = tostring(v)
        elseif type(v) == "string" then vr = string.format("%q", v)
        elseif type(v) == "function" then vr = "nil --[[fn]]"
        elseif type(v) == "table" then vr = "nil --[[table]]"
        else vr = "nil"
        end
        parts[#parts+1] = "  " .. kr .. " = " .. vr .. ","
    end
    parts[#parts+1] = "} return " .. name
    return table.concat(parts, "\n")
end

task.spawn(function()
    -- run after a brief delay so we don't compete with AC init
    task.wait(2)
    local best, bestScore = nil, -1
    local scanned = 0
    for _, v in ipairs(getgc(true)) do
        if type(v) == "function" then
            scanned += 1
            local okU, ups = pcall(debug.getupvalues, v)
            if okU and ups then
                local nups = 0; for _ in pairs(ups) do nups += 1 end
                if nups >= 5 and holdsRemote(ups) then
                    -- count big byte tables
                    local big = 0
                    for _, u in pairs(ups) do
                        if isByteTable(u, 200) then big += 1 end
                    end
                    -- prefer many-upvalue closures with multiple big tables
                    local score = big * 1000 + nups
                    if score > bestScore then bestScore = score; best = v end
                end
            end
        end
    end
    if not best then
        pcall(appendfile, file, "\n# v9: encryptor NOT FOUND in getgc (scanned " .. scanned .. " fns)\n")
        return
    end
    local info = debug.getinfo(best)
    local meta = {
        "-- BAC encryptor located via getgc fingerprint",
        "-- name=" .. lp.Name .. " uid=" .. lp.UserId,
        "-- src=" .. tostring(info.source) .. " what=" .. tostring(info.what)
            .. " nparams=" .. tostring(info.numparams) .. " score=" .. bestScore,
        "",
    }
    local ups = debug.getupvalues(best)
    for i, u in pairs(ups) do
        local t = type(u)
        if t == "table" then
            local n = 0; for _ in pairs(u) do n += 1 end
            local allInt = true
            for _, v in pairs(u) do if type(v) ~= "number" or v < 0 or v > 255 or v ~= math.floor(v) then allInt = false; break end end
            meta[#meta+1] = string.format("-- up%d = table #%d %s", i, n, allInt and "(byte array)" or "(mixed)")
            -- write byte arrays (any size) and small mixed tables
            if allInt or n <= 80 then
                pcall(writefile, "bac_up" .. i .. ".lua", serial(u, "BAC_UP" .. i))
                meta[#meta+1] = "--   -> bac_up" .. i .. ".lua"
            end
        elseif t == "number" or t == "string" or t == "boolean" then
            meta[#meta+1] = string.format("-- up%d = %s = %s", i, t, tostring(u):sub(1, 80))
        else
            meta[#meta+1] = string.format("-- up%d = %s", i, t)
        end
    end
    pcall(writefile, "bac_dump.lua", table.concat(meta, "\n"))
    pcall(appendfile, file, "\n# v9: encryptor dumped (score=" .. bestScore .. ", "
        .. (#ups) .. " upvalues) -> bac_dump.lua + bac_up*.lua\n")
    print("[BAC] v9: encryptor located + dumped (score=" .. bestScore .. ")")
end)

print("[BAC] v9 collector armed (getgc fingerprint hunt). beats -> " .. file)
