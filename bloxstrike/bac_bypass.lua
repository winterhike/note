--[[==================================================================
    BloxStrike BAC - Bypass Toolkit (pure, no cheat features)
    ------------------------------------------------------------------
    Covers every NON-virtualised detection vector found in the AC's constants
    (read live via getgc, read-only):

      1. NAMECALL CANARY   - BAC probes obj:OmgUnvirNamecall() (and other
         invalid members, and WaitForChild with a table arg) and compares the
         error to a clean client EXACTLY. We reproduce the genuine error
         dynamically: "<Method> is not a valid member of <ClassName> \"<Name>\"".
      2. HOOKFUNCTION SPOOF - callable proxy + type/typeof/tostring spoof so a
         table-field function hook passes identity checks.
      3. LOGSERVICE KILL    - BAC reads error tracebacks ("Luraph Script:" +
         :(%d+) line regex) via LogService.MessageOut -> we sever those.
      4. EMULATION          - capture/decode/replay the BAC heartbeat packet
         (identity secret recovered) as a keepalive primitive.

    NOTE: on this game BAC also uses Luraph lph VM-integrity to detect that a
    metamethod was hooked at the VM level - that needs a Volt-class executor
    whose hooks don't lower VM integrity. This toolkit defeats the scriptable
    detection layer; the lph layer is executor-dependent.

    Usage:
        local BAC = loadstring(game:HttpGet(".../bac_bypass.lua"))()
        BAC.init()                       -- installs namecall + logservice
        local orig = BAC.proxyHook(tbl, "Send", function(o, ...) ... end)
        local beats = BAC.captureGenuine(5, 3)
==================================================================--]]

local Bypass = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService        = game:GetService("LogService")
local LocalPlayer       = Players.LocalPlayer

local _hookmetamethod = hookmetamethod
local _hookfunction   = hookfunction or replaceclosure
local _getnamecall    = getnamecallmethod or get_namecall_method
local _newcclosure    = newcclosure or function(f) return f end
local _getconnections = getconnections or get_signal_cons
local _restorefunction= restorefunction or function() end

--==================================================================
-- 1. NAMECALL canary bypass
--==================================================================
local function genuineMemberError(self, method)
    local cls, nm = "Instance", "?"
    pcall(function() cls = self.ClassName; nm = self.Name end)
    return method .. " is not a valid member of " .. cls .. ' "' .. nm .. '"'
end

local function isValidMember(self, method)
    local ok, v = pcall(function() return self[method] end)
    return ok and v ~= nil
end

function Bypass.installNamecallBypass()
    if Bypass._ncInstalled or not _hookmetamethod then return false end
    local Old
    Old = _hookmetamethod(game, "__namecall", _newcclosure(function(self, ...)
        local method = _getnamecall()

        -- WaitForChild with a non-string arg -> genuine argument error
        if method == "WaitForChild" then
            local a1 = ...
            if a1 ~= nil and type(a1) ~= "string" and type(a1) ~= "number" then
                error("invalid argument #1 to 'WaitForChild' (string expected, got " .. typeof(a1) .. ")", 0)
            end
        end

        -- invalid-member probe (OmgUnvirNamecall / FakeIndex / anything fake)
        if method and not isValidMember(self, method) then
            error(genuineMemberError(self, method), 0)
        end

        return Old(self, ...)
    end))
    Bypass._ncInstalled = true
    Bypass._ncOld = Old
    return true
end

--==================================================================
-- 2. HOOKFUNCTION spoof (callable proxy + identity spoof)
--==================================================================
local _spoofed = setmetatable({}, { __mode = "k" })
function Bypass.installIdentitySpoof()
    if Bypass._idInstalled then return end
    Bypass._idInstalled = true
    local _type, _typeof, _tostring = type, typeof, tostring
    getgenv().type     = _newcclosure(function(v) if _type(v)=="table" and _spoofed[v] then return "function" end return _type(v) end)
    getgenv().typeof   = _newcclosure(function(v) if _type(v)=="table" and _spoofed[v] then return "function" end return _typeof(v) end)
    getgenv().tostring = _newcclosure(function(v) if _type(v)=="table" and _spoofed[v] then return _spoofed[v] end return _tostring(v) end)
end

-- Replace tbl[name] with a callable proxy that passes type/typeof/tostring.
function Bypass.proxyHook(tbl, name, hookFn)
    local orig = tbl[name]
    if not orig then return nil end
    Bypass.installIdentitySpoof()
    local str = tostring(orig)
    local proxy = setmetatable({}, {
        __call = function(_, ...)
            local ok, r = pcall(hookFn, orig, ...)
            if ok then return r else return orig(...) end
        end,
        __tostring = function() return str end,
        __metatable = getmetatable(orig),
    })
    _spoofed[proxy] = str
    tbl[name] = proxy
    return orig
end

--==================================================================
-- 3. LOGSERVICE report-vector kill (+ maintenance)
--==================================================================
function Bypass.killLogService()
    if not _getconnections then return 0 end
    local n = 0
    local ok, conns = pcall(_getconnections, LogService.MessageOut)
    if ok and conns then
        for _, c in ipairs(conns) do
            pcall(function() if c.Disable then c:Disable() else c:Disconnect() end end)
            n += 1
        end
    end
    return n
end

--==================================================================
-- 4. EMULATION (BAC heartbeat capture / decode / replay)
--==================================================================
local STATIC_SECRET = "PleaseDontFindThisSenorEhItDoesntReallyMatterTbhItsFineIfYouDo"
local SALT, PARAM = "GuelpBAC", 256

function Bypass.buildIdentity(plr, withParam)
    plr = plr or LocalPlayer
    local uid = plr.UserId
    local s = plr.Name .. "|" .. (uid*2) .. "|" .. (uid*4) .. "|" .. STATIC_SECRET .. "|" .. SALT
    if withParam then s = s .. "|" .. PARAM end
    return s
end

local function escapeByte(b)
    if b == 0x21 or b == 0x2D or b < 0x20 or b > 0x7E then return "!" .. b .. "!" end
    return string.char(b)
end
function Bypass.packBytes(bytes)
    local out = {}; for i = 1, #bytes do out[i] = escapeByte(bytes[i]) end
    return table.concat(out)
end
function Bypass.unpackEscaped(str)
    local bytes, i = {}, 1
    while i <= #str do
        local n = str:match("^!(%d+)!", i)
        if n then bytes[#bytes+1] = tonumber(n); i = i + #n + 2
        else bytes[#bytes+1] = str:byte(i); i = i + 1 end
    end
    return bytes
end
function Bypass.decodePacket(packet)
    local raw = Bypass.unpackEscaped(packet)
    local marks = {}
    for i = 1, #raw do if raw[i] == 0x2D then marks[#marks+1] = i end end
    local function slice(a, b) local t = {} for i = a, b do t[#t+1] = raw[i] end return t end
    local header = slice(1, (marks[1] or #raw + 1) - 1)
    return {
        raw = raw,
        nonce = (header[1] or 0) + (header[2] or 0) * 256,
        seq = header[3],
        reserved = #header - 3,
        digest = marks[1] and slice(marks[1] + 1, (marks[2] or #raw + 1) - 1) or {},
        trailer = marks[2] and slice(marks[2] + 1, #raw) or {},
    }
end
function Bypass.buildPacket(nonce, seq, digestBytes, trailerBytes)
    local header = { nonce % 256, math.floor(nonce / 256) % 256, seq % 256, 0, 0, 0, 0, 0 }
    local parts = { Bypass.packBytes(header), "-", Bypass.packBytes(digestBytes) }
    if trailerBytes then parts[#parts+1] = "-"; parts[#parts+1] = Bypass.packBytes(trailerBytes) end
    return table.concat(parts)
end
function Bypass.findBacRemote()
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "BAC" and d:IsA("RemoteEvent") then return d end
    end
end
function Bypass.captureGenuine(timeout, want)
    local remote = Bypass.findBacRemote()
    if not remote or not _hookfunction then return {} end
    local out, fs, old = {}, remote.FireServer
    local ok = pcall(function()
        old = _hookfunction(fs, function(self, ...)
            local a = table.pack(...)
            if self == remote and type(a[1]) == "string" then out[#out+1] = a[1] end
            return old(self, ...)
        end)
    end)
    if not ok then return {} end
    local t0 = os.clock()
    repeat task.wait() until #out >= (want or 1) or (os.clock() - t0) > (timeout or 6)
    pcall(_restorefunction, fs)
    return out
end
function Bypass.sendPacket(packet)
    local remote = Bypass.findBacRemote()
    if remote then remote:FireServer(packet); return true end
    return false
end

--==================================================================
-- init: install the always-on protections
--==================================================================
function Bypass.init(opts)
    opts = opts or {}
    local report = { ok = true }
    report.namecall  = Bypass.installNamecallBypass()
    report.logKilled = Bypass.killLogService()
    -- maintain LogService kill (BAC may re-add listeners)
    task.spawn(function() while true do pcall(Bypass.killLogService); task.wait(2) end end)
    if opts.identitySpoof then Bypass.installIdentitySpoof() end
    return report
end

getgenv().BAC = Bypass
return Bypass
