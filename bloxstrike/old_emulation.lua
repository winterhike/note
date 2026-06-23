--[[==================================================================
    BloxStrike BAC - heartbeat recon + NO-HOOK harvester
    ------------------------------------------------------------------
    Findings (live, read-only debug reflection - NO hooks):

      * Remotes.BAC (ReplicatedStorage.Remotes.BAC) is the heartbeat
        RemoteEvent. It is CLIENT -> SERVER only: OnClientEvent has 0
        connections, so the client GENERATES heartbeats itself (no server
        challenge). That means a valid beat depends only on client state.

      * Wire format (confirmed from the live state table):
            [nonce:2 LE][seq:1][reserved:5x00] "-" [digest:13-15B] (-trailer)
        bytes 0x21('!'), 0x2D('-'), <0x20, >0x7E are escaped as "!<dec>!".

      * The SENDER is a Lua closure with upvalues:
            up1 = the BAC RemoteEvent
            up2 = STATE TABLE  -> holds the freshly-computed VALID packet
                  strings (rotating, seq increments each beat)
            up3 = digest generator = a C CLOSURE (native, 1 userdata upvalue)
                  -> no Lua bytecode, the crypto math cannot be read directly.

      * identity = Name | UserId*2 | UserId*4 | SECRET | GuelpBAC | 256
        SECRET = "PleaseDontFindThisSenorEhItDoesntReallyMatterTbhItsFineIfYouDo"

      * The Network transport (Database.Security.Network) does NOT sign -
        its Send is a bare FireServer(packet). Signing is the C-closure above.

      * TRAP: CameraController kicks ("Skibidi Toilet?") + fires all remotes
        if the camera Position jumps > 0.5 unexpectedly. Never snap the camera.

    *** CORRECTION / CONTAMINATION WARNING ***
    A getgc pass on a session that previously ran this script (or bac_bypass)
    will ALSO surface our OWN leftover capture buffer: the captureGenuine hook
    closure had upvalues { out (string array), remote, old (=original
    FireServer, a C closure w/ userdata) } - which is indistinguishable by
    shape from a "sender + state table + native digest". Symptom: the table is
    static (does NOT update over time) and is array-indexed 1..n with the exact
    sample packets we printed before.

    Therefore acquireState() below now REQUIRES the candidate table to actually
    change over a short window before accepting it, and ignores our own buffer.
    Run from a FRESH executor state (no prior old_emulation/bac_bypass run) and
    during an ACTIVE round (the client only emits beats when the AC is live) to
    catch the real sender.

    Real, uncontaminated findings still stand: client-generated beat (no
    OnClientEvent), Network layer does not sign, CameraController kick-trap,
    wire format, and the recovered SECRET/SALT.
==================================================================--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

local Emu = {}

--==================================================================
-- packet decode helpers (escaped-byte <-> raw)
--==================================================================
local function unpackEscaped(str)
    local bytes, i = {}, 1
    while i <= #str do
        local n = str:match("^!(%d+)!", i)
        if n then bytes[#bytes + 1] = tonumber(n); i = i + #n + 2
        else bytes[#bytes + 1] = str:byte(i); i = i + 1 end
    end
    return bytes
end
Emu.unpackEscaped = unpackEscaped

local function toHex(t)
    local out = {}
    if type(t) == "string" then t = unpackEscaped(t) end
    for i = 1, #t do out[i] = string.format("%02X", t[i]) end
    return table.concat(out, " ")
end
Emu.toHex = toHex

local function decodePacket(packet)
    local raw = unpackEscaped(packet)
    local dash
    for i = 1, #raw do if raw[i] == 0x2D then dash = i break end end
    local header = {}
    for i = 1, (dash or #raw + 1) - 1 do header[i] = raw[i] end
    local digest = {}
    if dash then for i = dash + 1, #raw do digest[#digest + 1] = raw[i] end end
    return {
        raw = raw, packet = packet,
        nonce = (header[1] or 0) + (header[2] or 0) * 256,
        seq = header[3],
        digest = digest,
    }
end
Emu.decodePacket = decodePacket

--==================================================================
-- locate the BAC RemoteEvent
--==================================================================
local function findBacRemote()
    local r = ReplicatedStorage:FindFirstChild("Remotes")
    r = r and r:FindFirstChild("BAC")
    if r and r:IsA("RemoteEvent") then return r end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "BAC" and d:IsA("RemoteEvent") then return d end
    end
end
Emu.findBacRemote = findBacRemote

--==================================================================
-- NO-HOOK harvester: ONE getgc pass to find the sender's state table,
-- then read it every frame (cheap, no further getgc). Caches into getgenv
-- so it survives across MCP calls / re-runs within a session.
--==================================================================
local function acquireState()
    if getgenv()._BAC_STATE and getgenv()._BAC_REMOTE then
        return getgenv()._BAC_STATE, getgenv()._BAC_REMOTE
    end
    local remote = findBacRemote()
    if not remote then return nil, "no BAC remote" end
    if typeof(getgc) ~= "function" then return nil, "no getgc" end

    local function fingerprint(tbl)
        local parts = {}
        for k, s in pairs(tbl) do
            if type(s) == "string" then parts[#parts + 1] = tostring(k) .. "=" .. s end
        end
        table.sort(parts)
        return table.concat(parts, "|")
    end

    -- collect ALL candidate tables (this also matches our own leftover capture
    -- buffer, which is why we liveness-test before accepting).
    local candidates = {}
    for _, v in ipairs(getgc(true)) do
        if type(v) == "function" then
            local okU, ups = pcall(debug.getupvalues, v)
            if okU then
                local holdsRemote, stateTbl = false, nil
                for _, u in pairs(ups) do
                    if u == remote then holdsRemote = true end
                    if type(u) == "table" then
                        for _, sv in pairs(u) do
                            if type(sv) == "string" and sv:find("!0!!0!!0!", 1, true) then stateTbl = u; break end
                        end
                    end
                end
                if holdsRemote and stateTbl then candidates[stateTbl] = fingerprint(stateTbl) end
            end
        end
    end
    if not next(candidates) then return nil, "no candidate tables" end

    -- liveness: the real sender's table mutates as beats fire; our static
    -- capture buffer does not. Accept only a table that changed.
    task.wait(2.5)
    for tbl, before in pairs(candidates) do
        if fingerprint(tbl) ~= before then
            getgenv()._BAC_STATE  = tbl
            getgenv()._BAC_REMOTE = remote
            return tbl, remote
        end
    end
    return nil, "only static (debris) tables - run fresh + during an active round"
end
Emu.acquireState = acquireState

-- read the freshest valid packet from the cached state table (NO getgc, NO hook)
local function latest()
    local state = getgenv()._BAC_STATE
    if not state then return nil end
    local best, bestSeq
    for _, s in pairs(state) do
        if type(s) == "string" and #s > 0 then
            local d = decodePacket(s)
            -- seq is a single byte that wraps; track the max for "freshest"
            if not bestSeq or (d.seq or 0) > bestSeq then best, bestSeq = s, d.seq or 0 end
        end
    end
    return best, bestSeq
end
Emu.latest = latest

-- snapshot the whole state table (decoded) for analysis
local function snapshot()
    local state = getgenv()._BAC_STATE
    local out = {}
    if state then
        for k, s in pairs(state) do
            if type(s) == "string" then
                local d = decodePacket(s)
                out[#out + 1] = { key = tostring(k), nonce = d.nonce, seq = d.seq, hex = toHex(d.raw) }
            end
        end
    end
    return out
end
Emu.snapshot = snapshot

-- replay the freshest genuine packet ourselves (no hook). NOTE: this is a
-- keepalive/relay primitive - it does not yet strip detection state, which is
-- inside the native digest. Use only for round-trip experiments.
local function replay()
    local state, remote = acquireState()
    if not state then return false, remote end
    local pkt = latest()
    if not pkt then return false, "no packet yet" end
    remote:FireServer(pkt)
    return true
end
Emu.replay = replay

--==================================================================
-- one-shot report when run directly
--==================================================================
do
    local state, err = acquireState()
    if state then
        print("[BAC] state table acquired (no hook). Live packets:")
        for _, e in ipairs(snapshot()) do
            print(string.format("[BAC]   nonce=0x%04X seq=%s  %s", e.nonce or 0, tostring(e.seq), e.hex))
        end
        local p, sq = latest()
        print("[BAC] freshest seq=" .. tostring(sq))
    else
        warn("[BAC] could not acquire state: " .. tostring(err))
    end
end

return Emu
