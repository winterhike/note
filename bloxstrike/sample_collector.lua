--[[ BAC v8 - SURGICAL dump: write the encryptor's tables (up1/up4/up6/up9 +
     the named Lua fn constants in up8) to workspace files in Lua-loadable form,
     so we can replay the algorithm offline. Fast: dumps once on first beat,
     then exits the hook quickly.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp                = Players.LocalPlayer

local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("BAC")
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

-- FakeIndex canary
do
    local Old; Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getnamecallmethod() == "FakeIndex" then
            return false, 'FakeIndex is not a valid member of DataModel "Ugc"'
        end
        return Old(self, ...)
    end))
end

-- find the AC ENCRYPTOR frame: a Lua function with many upvalues, holding the
-- BAC remote (often nested in a table) AND at least one big int->int table
-- (the lookup data). The earlier "first holds-remote" match grabbed the
-- FireServer wrapper, which has 1 userdata upvalue - not what we want.
local function looksLikeByteTable(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, v in pairs(t) do
        n += 1
        if type(k) ~= "number" or type(v) ~= "number" then return false end
        if v < 0 or v > 255 or v ~= math.floor(v) then return false end
        if n > 200 then return true end -- early-out for clearly big tables
    end
    return n >= 50
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

local function findSender()
    -- pass 1: prefer a frame with many upvalues and a byte-table (the encryptor)
    for lvl = 2, 30 do
        local ok, info = pcall(debug.getinfo, lvl, "slf")
        if not ok or not info then break end
        if not info.func then break end
        if info.what == "Lua" then
            local okU, ups = pcall(debug.getupvalues, info.func)
            if okU and ups then
                local nups = 0; for _ in pairs(ups) do nups += 1 end
                if nups >= 5 and holdsRemote(ups) then
                    for _, u in pairs(ups) do
                        if looksLikeByteTable(u) then
                            return info.func, lvl, tostring(info.source or "?"), "encryptor"
                        end
                    end
                end
            end
        end
    end
    -- pass 2: any Lua frame holding the remote (last resort)
    for lvl = 2, 30 do
        local ok, info = pcall(debug.getinfo, lvl, "slf")
        if not ok or not info or not info.func then break end
        if info.what == "Lua" then
            local okU, ups = pcall(debug.getupvalues, info.func)
            if okU and ups and holdsRemote(ups) then
                return info.func, lvl, tostring(info.source or "?"), "fallback"
            end
        end
    end
end

local function tableHash(t)
    local n = 0; for _ in pairs(t) do n += 1 end; return n
end

-- serialize a small int->int|str|bool table as Lua source
local function serial(t, name)
    local parts = { "local " .. name .. " = {" }
    local keys = {}; for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local v = t[k]
        local kr = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
        local vr
        if type(v) == "number" or type(v) == "boolean" then vr = tostring(v)
        elseif type(v) == "string" then vr = string.format("%q", v)
        elseif type(v) == "function" then vr = "nil --[[function]]"
        elseif type(v) == "table" then vr = "nil --[[table]]"
        else vr = "nil"
        end
        parts[#parts+1] = "  " .. kr .. " = " .. vr .. ","
    end
    parts[#parts+1] = "}"
    return table.concat(parts, "\n")
end

local dumped = false
local function dumpOnce()
    if dumped then return end; dumped = true
    local fn, lvl, src, why = findSender()
    if not fn then pcall(appendfile, file, "# no sender frame\n"); return end
    pcall(appendfile, file, "\n# --- v8 sender dump ---\n# src=" .. src .. " lvl=" .. tostring(lvl) .. " match=" .. tostring(why) .. "\n")
    local okU, ups = pcall(debug.getupvalues, fn)
    if not okU then pcall(appendfile, file, "# getupvalues failed\n"); return end

    -- write each upvalue's identity
    local meta = { "-- name=" .. lp.Name .. " uid=" .. lp.UserId, "-- src=" .. src, "" }
    for i, u in pairs(ups) do
        local t = type(u)
        if t == "table" then
            local n = tableHash(u)
            -- check if "all int values" (lookup table)
            local allIntV = true
            for _, v in pairs(u) do if type(v) ~= "number" or v ~= math.floor(v) or v < 0 or v > 255 then allIntV = false; break end end
            meta[#meta+1] = string.format("-- up%d = table #%d %s", i, n, allIntV and "(byte array)" or "(mixed)")
            if allIntV and n > 0 then
                pcall(writefile, "bac_up" .. i .. ".lua", serial(u, "BAC_UP" .. i))
                meta[#meta+1] = "--   -> bac_up" .. i .. ".lua"
            elseif n <= 64 then
                pcall(writefile, "bac_up" .. i .. ".lua", serial(u, "BAC_UP" .. i))
                meta[#meta+1] = "--   -> bac_up" .. i .. ".lua (small)"
            end
        elseif t == "number" or t == "string" or t == "boolean" then
            meta[#meta+1] = string.format("-- up%d = %s = %s", i, t, tostring(u):sub(1, 80))
        else
            meta[#meta+1] = string.format("-- up%d = %s", i, t)
        end
    end
    pcall(writefile, "bac_dump.lua", table.concat(meta, "\n"))
    pcall(appendfile, file, "# wrote bac_dump.lua + bac_up*.lua to workspace\n")
    print("[BAC] v8 dump written: bac_dump.lua + bac_up*.lua")
end

local hookfn = hookfunction or replaceclosure
local fs = remote.FireServer
local old; old = hookfn(fs, newcclosure(function(self, ...)
    if self == remote then
        local a1 = (...)
        if type(a1) == "string" and #a1 > 0 then
            pcall(logBeat, a1)
            -- dump INLINE so the AC's stack frame is still on the call stack
            -- (a task.spawn coroutine has its own stack and would miss it).
            if not dumped then pcall(dumpOnce) end
        end
    end
    return old(self, ...)
end))

print("[BAC] v8 collector armed (surgical dump). beats -> " .. file)
