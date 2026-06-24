--[[==================================================================
    BloxStrike BAC - heartbeat emulator (yeno's technique)
    ------------------------------------------------------------------
    "HEARTBEAT CLIENT -> GETS DTCED -> THEIR ENCRYPTION -> HOOK -> FIX
     -> ENCRYPT -> SEND (yourself, as they crash after the encryption)"

    The AC's encryption ALWAYS succeeds. The send step is what gets
    sabotaged on detection (we observed "attempt to index nil with
    'FireServer'" - they nil their own remote ref). So:

      1. Locate the encryptor closure via getgc fingerprint (24 upvalues,
         holds BAC remote, has big byte-table upvalues).
      2. Hook FireServer (only point the encrypted beat exists in clear).
         Use debug.getstack(2) on the encryptor's frame to mirror its
         in-flight registers (the actual stack technique pubmain pointed at).
      3. Cache every captured beat + the AC's own up3 cache (its 5 most
         recent per-channel encrypted beats).
      4. Watchdog: if no beat for >1.5s (AC pipeline crashed), replay
         from cache - cycling through up3 channels for variety.

    We don't decrypt anything. We let the AC encrypt, then send its
    output past its broken send pipeline.
==================================================================--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp                = Players.LocalPlayer

local Relay = {}

--==================================================================
-- 1. Find BAC remote
--==================================================================
local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("BAC")
if not remote then
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "BAC" and d:IsA("RemoteEvent") then remote = d break end
    end
end
assert(remote, "[BAC relay] no BAC RemoteEvent found")

--==================================================================
-- 2. Locate the encryptor closure (one getgc pass, fingerprinted)
--==================================================================
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
        if type(u) == "table" then
            for _, vv in pairs(u) do if vv == remote then return true end end
        end
    end
    return false
end

local encryptor
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
    encryptor = best
    if best then print(string.format("[BAC relay] encryptor located (score=%d)", bestScore))
    else warn("[BAC relay] encryptor NOT found - falling back to FireServer-only capture") end
end
Relay.encryptor = encryptor

--==================================================================
-- 3. Read AC's own per-channel cached beats from encryptor upvalues
--==================================================================
local function readCachedBeats()
    if not encryptor then return {} end
    local ok, ups = pcall(debug.getupvalues, encryptor)
    if not ok then return {} end
    local beats, seen = {}, {}
    for _, u in pairs(ups) do
        if type(u) == "table" then
            for _, v in pairs(u) do
                if type(v) == "string" and #v >= 8 and v:find("!0!!0!!0!!0!", 1, true) and not seen[v] then
                    seen[v] = true
                    beats[#beats + 1] = v
                end
            end
        end
    end
    return beats
end
Relay.readCachedBeats = readCachedBeats

--==================================================================
-- 4. Hook FireServer to capture beats. Uses debug.getstack(2) on the
--    encryptor's stack frame to mirror its in-flight state (the actual
--    "stack" technique - works because at FireServer-call time the
--    encryptor IS at level 2).
--==================================================================
local lastBeat, lastBeatTime
local stackDumped = false
local capturedBeats = 0

local hookfn = hookfunction or replaceclosure
local fs = remote.FireServer
local origFire
origFire = hookfn(fs, newcclosure(function(self, ...)
    if self == remote then
        local a1 = (...)
        if type(a1) == "string" and #a1 > 0 then
            lastBeat = a1
            lastBeatTime = os.clock()
            capturedBeats += 1

            -- one-shot: dump encryptor's stack registers via debug.getstack(2)
            -- so we can see exactly which slot holds the encrypted beat string
            -- + the nonce/seq counters. This is the "use stack" hint from the thread.
            if not stackDumped then
                stackDumped = true
                local out = {
                    "-- encryptor stack at FireServer call (level 2)",
                    "-- name=" .. lp.Name .. " uid=" .. lp.UserId,
                    "",
                }
                for slot = 1, 64 do
                    local ok, val = pcall(debug.getstack, 2, slot)
                    if not ok then break end
                    local desc
                    local t = type(val)
                    if t == "string" then
                        desc = '"' .. val:sub(1, 60):gsub("[^%w%p ]", "?") .. '"'
                    elseif t == "table" then
                        local n = 0; for _ in pairs(val) do n += 1 end
                        desc = "table#" .. n
                    elseif t == "function" then
                        desc = "fn"
                    elseif t == "userdata" then
                        desc = "userdata"
                    else
                        desc = tostring(val)
                    end
                    out[#out + 1] = string.format("-- [%d] %s = %s", slot, t, desc)
                end
                pcall(writefile, "bac_encryptor_stack.lua", table.concat(out, "\n"))
            end
        end
    end
    return origFire(self, ...)
end))

--==================================================================
-- 5. Watchdog: when AC's send pipeline crashes (no beat in >1.5s),
--    replay cached beats - cycle through up3's channels for variety.
--==================================================================
local relayed = 0
task.spawn(function()
    local cycle = 0
    while true do
        task.wait(0.4)
        if lastBeatTime and (os.clock() - lastBeatTime) > 1.5 then
            local cached = readCachedBeats()
            local pkt
            if #cached > 0 then
                cycle = (cycle % #cached) + 1
                pkt = cached[cycle]
            else
                pkt = lastBeat
            end
            if pkt then
                local ok = pcall(function() remote:FireServer(pkt) end)
                if ok then
                    relayed += 1
                    lastBeatTime = os.clock()
                end
            end
        end
    end
end)

--==================================================================
-- 6. Status API
--==================================================================
function Relay.status()
    return {
        encryptor = encryptor ~= nil,
        captured  = capturedBeats,
        relayed   = relayed,
        cached    = #readCachedBeats(),
        secsSinceLastBeat = lastBeatTime and (os.clock() - lastBeatTime) or nil,
    }
end

getgenv().BAC_RELAY = Relay

print("[BAC relay] armed. encryptor=" .. tostring(encryptor ~= nil)
    .. ". hook=FireServer. watchdog=1.5s gap. status: getgenv().BAC_RELAY.status()")

return Relay
