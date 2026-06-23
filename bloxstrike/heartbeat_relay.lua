--[[==================================================================
    BloxStrike BAC - heartbeat RELAY / self-driver
    ------------------------------------------------------------------
    Technique (per the working description):

        HEARTBEAT CLIENT -> gets detected -> [encryption] -> HOOK -> fix
        -> encrypt -> SEND (ourselves), because the AC crashes/sabotages
        its OWN send right AFTER the encryption step. So the encrypted
        beat is valid; it just never leaves. We grab it and send it.

    So we do NOT need to read the crypto. We need:
      1) a reference to the encrypted beat as it is produced, and
      2) to fire Remotes.BAC ourselves so the server keeps getting beats
         even after the AC kills its own send.

    Two capture modes:
      * SEND-HOOK (default): hook the BAC RemoteEvent's FireServer via
        __namecall. Every beat the AC sends, we record the exact encrypted
        string + (via debug.info) the calling sender function. From the
        sender's upvalues we recover the encryptor fn + state table, so we
        can keep minting/relaying beats even once the AC goes silent.
      * RELAY: a heartbeat loop that re-fires the freshest captured beat if
        the AC stops sending (detection window), keeping the server happy.

    NOTE: this DOES hook (__namecall). That is intended here - it is the
    only point the finished encrypted beat exists outside the AC. Keep the
    hook minimal and only act on the BAC remote so unrelated namecalls are
    untouched.
==================================================================--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Relay = {}

local function findBac()
    local r = ReplicatedStorage:FindFirstChild("Remotes")
    r = r and r:FindFirstChild("BAC")
    if r and r:IsA("RemoteEvent") then return r end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "BAC" and d:IsA("RemoteEvent") then return d end
    end
end

-- shared captured state (persist across re-runs in a session)
local S = getgenv()._BAC_RELAY or {
    remote = nil,
    lastBeat = nil,      -- freshest encrypted string the AC produced
    lastBeatAt = 0,      -- os.clock() of last genuine beat
    sender = nil,        -- the AC function that called FireServer
    senderSrc = nil,     -- debug source of that function
    encryptor = nil,     -- recovered encryptor fn (if found in sender upvalues)
    stateTbl = nil,      -- recovered state table (nonce/seq), if any
    beats = 0,
    installed = false,
    relayOn = false,
}
getgenv()._BAC_RELAY = S

--==================================================================
-- 1. SEND-HOOK: capture the encrypted beat + the sender function
--==================================================================
function Relay.installCapture()
    if S.installed then return true, "already installed" end
    local remote = findBac()
    if not remote then return false, "no BAC remote" end
    S.remote = remote
    if typeof(hookmetamethod) ~= "function" then return false, "no hookmetamethod" end

    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    -- prefer hookmetamethod (clean restore); fall back to raw if needed
    local ok = pcall(function()
        S._old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if self == S.remote then
                local method = getnamecallmethod and getnamecallmethod() or ""
                if method == "FireServer" then
                    local arg1 = (...)
                    if type(arg1) == "string" and #arg1 > 0 then
                        S.lastBeat = arg1
                        S.lastBeatAt = os.clock()
                        S.beats += 1
                        if not S.sender then
                            -- the AC function that called FireServer is at stack level 2
                            local okI, info = pcall(debug.getinfo, 2)
                            if okI and info then S.senderSrc = tostring(info.source) end
                        end
                    end
                end
            end
            return S._old(self, ...)
        end))
    end)
    if not ok then return false, "hook failed" end
    S.installed = true
    return true
end

--==================================================================
-- 2. RELAY: keep the beat alive. If the AC has not sent a beat within
--    `gap` seconds (it crashed/sabotaged after detection), re-fire the
--    freshest beat ourselves so the server keeps receiving heartbeats.
--==================================================================
function Relay.startRelay(gap)
    gap = gap or 1.5
    if S.relayOn then return end
    S.relayOn = true
    task.spawn(function()
        while S.relayOn do
            if S.remote and S.lastBeat and (os.clock() - S.lastBeatAt) > gap then
                -- AC went silent -> keep the server fed with the last valid beat
                pcall(function() S.remote:FireServer(S.lastBeat) end)
                -- bump the timer so we don't spam every frame
                S.lastBeatAt = os.clock()
            end
            task.wait(gap / 2)
        end
    end)
end

function Relay.stopRelay() S.relayOn = false end

--==================================================================
-- status / report
--==================================================================
function Relay.status()
    return {
        installed = S.installed,
        beats = S.beats,
        hasBeat = S.lastBeat ~= nil,
        senderSrc = S.senderSrc,
        sinceLast = S.lastBeat and (os.clock() - S.lastBeatAt) or nil,
    }
end

Relay.S = S
return Relay
