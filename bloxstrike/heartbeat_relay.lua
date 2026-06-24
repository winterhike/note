--[[==================================================================
    BAC heartbeat relay - up5[8] live-beat firing
    ------------------------------------------------------------------
    Diagnostic showed up5[8] is the AC's live beat buffer, refreshing
    every ~3s with a fresh nonce. Pure monitoring is undetected (60s+).

    This script:
      1. Locates the encryptor (passive, undetected).
      2. Monitors up5[8] every 0.2s for changes.
      3. When you set getgenv()._BAC_FIRE = true, every NEW up5[8] is
         FireServer'd by us. Stays off by default so you can verify
         monitoring works without sending anything.

    To enable firing once verified, run in console:
        getgenv()._BAC_FIRE = true
    To stop:
        getgenv()._BAC_FIRE = false
==================================================================--]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

-- rconsole shim
local rprint  = rconsoleprint  or printconsole or function(s) print(s) end
local rcreate = rconsolecreate or rconsoleopen or function() end
local rname   = rconsolename   or rconsolesettitle or function() end
pcall(rcreate); pcall(rname, "BAC relay")
local LOGF = "bac_relay.log"
pcall(writefile, LOGF, "")
local function tlog(tag, msg)
    local line = string.format("[%.3f] %s | %s", os.clock(), tag, tostring(msg))
    pcall(rprint, line .. "\n")
    pcall(appendfile, LOGF, line .. "\n")
end

tlog("INIT", string.format("name=%s uid=%d", lp.Name, lp.UserId))

-- locate
local remote = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("BAC")
if not remote then tlog("FATAL", "no BAC"); return end

local function isByteTable(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, v in pairs(t) do
        if type(k) ~= "number" or type(v) ~= "number" then return false end
        if v < 0 or v > 255 or v ~= math.floor(v) then return false end
        n += 1
        if n >= 200 then return true end
    end
    return false
end
local function holdsRemote(ups)
    for _, u in pairs(ups) do
        if u == remote then return true end
        if type(u) == "table" then for _, vv in pairs(u) do if vv == remote then return true end end end
    end
    return false
end

local enc
do
    local best, bestScore = nil, -1
    for _, v in ipairs(getgc(true)) do
        if type(v) == "function" then
            local okU, ups = pcall(debug.getupvalues, v)
            if okU and ups then
                local nups = 0; for _ in pairs(ups) do nups += 1 end
                if nups >= 5 and holdsRemote(ups) then
                    local big = 0
                    for _, u in pairs(ups) do if isByteTable(u) then big += 1 end end
                    local score = big * 1000 + nups
                    if score > bestScore then bestScore = score; best = v end
                end
            end
        end
    end
    enc = best
end
if not enc then tlog("FATAL", "no encryptor"); return end
tlog("ENC", "located. firing is OFF (set getgenv()._BAC_FIRE = true to enable)")

-- decode helper
local function decode(s)
    local b, j = {}, 1
    while j <= #s do
        local n = s:match("^!(%d+)!", j)
        if n then b[#b+1] = tonumber(n); j = j + #n + 2 else b[#b+1] = s:byte(j); j = j + 1 end
    end
    local nonce = (b[1] or 0) + (b[2] or 0) * 256
    local seq = b[3]
    return nonce, seq
end

-- monitor loop
getgenv()._BAC_FIRE = getgenv()._BAC_FIRE or false  -- preserve across re-runs
local prev = nil
local seenCount, firedCount = 0, 0

task.spawn(function()
    while true do
        task.wait(0.15)
        local ok, ups = pcall(debug.getupvalues, enc)
        if ok and ups then
            local up5 = ups[5]
            if type(up5) == "table" then
                local cur = up5[8]
                if type(cur) == "string" and cur ~= prev then
                    prev = cur
                    seenCount += 1
                    local n, s = decode(cur)
                    if getgenv()._BAC_FIRE then
                        local fireOk, fireErr = pcall(function() remote:FireServer(cur) end)
                        firedCount += 1
                        tlog("FIRE", string.format("#%d n=%d s=%s len=%d ok=%s err=%s",
                            firedCount, n, tostring(s), #cur, tostring(fireOk), tostring(fireErr or "")))
                    else
                        tlog("SEEN", string.format("#%d n=%d s=%s len=%d (firing disabled)",
                            seenCount, n, tostring(s), #cur))
                    end
                end
            end
        end
    end
end)

tlog("RELAY", "monitoring. seen=0 fired=0. flip getgenv()._BAC_FIRE to true when ready.")
