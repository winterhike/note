--[[==================================================================
    BAC DIAGNOSTIC - rconsole + file logger (NO interventions)
    ------------------------------------------------------------------
    Passive only: locates the encryptor, snapshots its state, monitors
    for changes and AC log messages. Mirrors everything to rconsole AND
    workspace/bac_diag.log so you can see exactly what changed in the
    seconds leading up to the kick.

    Does NOT call the encryptor. Does NOT FireServer anything. Does NOT
    install __namecall or function hooks. Just reads state every 0.5s.
==================================================================--]]

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local lp         = Players.LocalPlayer

-- rconsole compat shim (potassium API names vary)
local rprint  = rconsoleprint  or printconsole or function(s) print(s) end
local rcreate = rconsolecreate or rconsoleopen or function() end
local rname   = rconsolename   or rconsolesettitle or function() end
local rclear  = rconsoleclear  or function() end
pcall(rcreate)
pcall(rclear)
pcall(rname, "BAC diag")

local LOGF = "bac_diag.log"
pcall(writefile, LOGF, "")

local function tlog(tag, msg)
    local line = string.format("[%.3f] %s | %s", os.clock(), tag, tostring(msg))
    pcall(rprint, line .. "\n")
    pcall(appendfile, LOGF, line .. "\n")
end

tlog("INIT", string.format("name=%s uid=%d  job=%s", lp.Name, lp.UserId, tostring(game.JobId)))

-- locate BAC remote + encryptor
local remote = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("BAC")
if not remote then tlog("FATAL", "no Remotes.BAC"); return end

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

local enc, encScore
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
    enc = best; encScore = bestScore
end
if not enc then tlog("FATAL", "no encryptor"); return end
tlog("ENC", string.format("located src=%s score=%d", tostring(debug.getinfo(enc).source), encScore))

-- snapshot encryptor state (number upvalues + cached beat strings)
local function snap()
    local ok, ups = pcall(debug.getupvalues, enc)
    if not ok then return nil end
    local s = { state = {}, beats = {} }
    for i, u in pairs(ups) do
        if type(u) == "number" then
            s.state[i] = u
        elseif type(u) == "table" then
            for k, v in pairs(u) do
                if type(v) == "string" and v:find("!0!!0!!0!", 1, true) then
                    local b, j = {}, 1
                    while j <= #v do
                        local n = v:match("^!(%d+)!", j)
                        if n then b[#b+1] = tonumber(n); j = j + #n + 2 else b[#b+1] = v:byte(j); j = j + 1 end
                    end
                    local nonce = (b[1] or 0) + (b[2] or 0) * 256
                    local seq = b[3]
                    local dash; for j2 = 1, #b do if b[j2] == 0x2D then dash = j2 break end end
                    local hx = {}; if dash then for j2 = dash + 1, #b do hx[#hx+1] = string.format("%02x", b[j2]) end end
                    s.beats[string.format("up%d[%s]", i, tostring(k))] = string.format("n=%d s=%s len=%d d=%s",
                        nonce, tostring(seq), #v, table.concat(hx):sub(1, 40))
                end
            end
        end
    end
    return s
end

-- initial dump
do
    local s = snap()
    if s then
        for k, v in pairs(s.state) do tlog("STATE0", "up" .. k .. " = " .. v) end
        local kk = {}; for k in pairs(s.beats) do kk[#kk+1] = k end; table.sort(kk)
        for _, k in ipairs(kk) do tlog("BEAT0", k .. " = " .. s.beats[k]) end
    end
end

-- monitor diffs every 0.5s
task.spawn(function()
    local prev = snap()
    while true do
        task.wait(0.5)
        local cur = snap()
        if cur and prev then
            for k, v in pairs(cur.state) do
                if prev.state[k] ~= v then
                    tlog("STATE", string.format("up%d: %s -> %s", k, tostring(prev.state[k]), tostring(v)))
                end
            end
            for k, v in pairs(cur.beats) do
                if prev.beats[k] ~= v then
                    tlog("BEAT", string.format("%s: %s -> %s",
                        k, tostring(prev.beats[k] or "nil"):sub(1, 30), v:sub(1, 60)))
                end
            end
            for k in pairs(prev.beats) do
                if not cur.beats[k] then tlog("BEAT", k .. " REMOVED") end
            end
        end
        prev = cur
    end
end)

-- monitor LogService for AC complaints (read-only via GetLogHistory; no signal hook)
do
    local seen = {}
    task.spawn(function()
        while true do
            task.wait(0.5)
            local ok, hist = pcall(function() return LogService:GetLogHistory() end)
            if ok and hist then
                for _, e in ipairs(hist) do
                    local key = (e.timestamp or 0) .. ":" .. tostring(e.message)
                    if not seen[key] then
                        seen[key] = true
                        local m = e.message or ""
                        if m:find("BAC", 1, true) or m:find("Tamper", 1, true)
                            or m:find("nil with", 1, true) or m:find("Detected", 1, true)
                            or m:find("Luraph", 1, true) or m:find("Namecall", 1, true)
                            or m:find("Function", 1, true) then
                            tlog("LOG", string.format("[%s] %s", tostring(e.messageType and e.messageType.Name or "?"), m:sub(1, 240)))
                        end
                    end
                end
            end
        end
    end)
end

-- catch our own kick attempt (the kick message arrives as a log just before disconnection)
local function watchKick()
    local conn
    conn = LogService.MessageOut:Connect(function(msg, mt)
        if msg and (msg:find("Server Kick", 1, true) or msg:find("BAC Alpha", 1, true)
            or msg:find("kicked", 1, true)) then
            tlog("KICK", msg:sub(1, 240))
            -- final state snapshot before we lose the client
            local s = snap()
            if s then
                for k, v in pairs(s.state) do tlog("KICK_STATE", "up" .. k .. " = " .. v) end
            end
        end
    end)
end
-- NOTE: Connect on LogService is itself something BAC may detect (we saw 5 fns
-- parsing tracebacks in the AC). Skip the kick listener if you want pure passive.
pcall(watchKick)

tlog("READY", "passive diagnostic active. play normally. rconsole window persists past kick. Logs: " .. LOGF)

-- v2: PASSIVELY observe FireServer (never re-fire) to correlate with up5[8] / up3 changes.
-- This tells us WHICH upvalue holds the beat that actually gets fired.
do
    local hookfn = hookfunction or replaceclosure
    if hookfn then
        local fs = remote.FireServer
        local origFire
        origFire = hookfn(fs, newcclosure(function(self, ...)
            if self == remote then
                local a1 = (...)
                if type(a1) == "string" and #a1 > 0 then
                    -- decode and log
                    local b, j = {}, 1
                    while j <= #a1 do
                        local n = a1:match("^!(%d+)!", j)
                        if n then b[#b+1] = tonumber(n); j = j + #n + 2 else b[#b+1] = a1:byte(j); j = j + 1 end
                    end
                    local nonce = (b[1] or 0) + (b[2] or 0) * 256
                    local seq = b[3]
                    local dash; for j2 = 1, #b do if b[j2] == 0x2D then dash = j2 break end end
                    local hx = {}; if dash then for j2 = dash + 1, #b do hx[#hx+1] = string.format("%02x", b[j2]) end end
                    tlog("FIRE", string.format("n=%d s=%s len=%d d=%s",
                        nonce, tostring(seq), #a1, table.concat(hx):sub(1, 40)))
                end
            end
            return origFire(self, ...)
        end))
        tlog("READY", "FireServer passive observer installed")
    else
        tlog("WARN", "no hookfunction - skipping FireServer observer")
    end
end
