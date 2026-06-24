## Bloxstrike uses a handshake, and their main AC components are obfuscated with luraph.

How handshakes work:


Usage :
Handshakes main usage is to make sure the client behaves a certain way through server confirmation.

Can be used to detect whenever a certain localscript has been disabled, removed or destroyed.
Can be used to detect whenever a exploiter is trying to yield a RemoteEvent.

You need :
3 Module Scripts,1 ServerScript,1 LocalScript and 1 RemoteEvent (ReplicatedStorage)

(See picture at the end of the thread if struggling to understand)

Server Script Code (Parent of ConfigurationModule and DecodingModule)

 ServerScript
-- // Service variables
local HttpService = game.HttpService
local ReplicatedStorage = game.ReplicatedStorage

-- // Module variables
local Configuration = require(script.Configuration)
local Decoding = require(script.Decoding)

-- // Remote
local RemoteEvent = ReplicatedStorage.RemoteEvent

-- // Player storage variables
local PlayerLastCommunications = {}
local PlayerThreads = {}

game.Players.PlayerAdded:Connect(function(Player)
	
	-- // Create a Player specific thread for each player in the upon join
	PlayerThreads[Player] = task.spawn(function()
		
		-- // Set values of Player specific communications(sent / recieved)
		PlayerLastCommunications[Player] = {
			
			Numbers = {
				Sent = 0,
				Misses = 0,
			},
			
			Strings = {
				GeneratedKey = "",
				CurrentKey = "",
			},
			
		}
		
		while task.wait(Configuration.Numbers.CommunicationSpeed) do

			-- // Timeout detection trigger
			if PlayerLastCommunications[Player].Numbers.Sent and PlayerLastCommunications[Player].Numbers.Misses >= 1 then
				if tick() - PlayerLastCommunications[Player].Numbers.Sent > Configuration.Numbers.TimeoutLimit then
					PlayerLastCommunications[Player].Numbers.Misses += Configuration.Numbers.TimeoutLimit * 2
				end
			end
				
			-- // Timeout punishment
			if PlayerLastCommunications[Player].Numbers.Misses >= Configuration.Numbers.TimeoutLimit then
				Player:Kick("Handshake timeout")
			else
				PlayerLastCommunications[Player].Numbers.Misses = 0
			end
			
			-- // Generate a new key for every player every 1 second
			PlayerLastCommunications[Player].Strings.GeneratedKey = HttpService:GenerateGUID(false)	
			
			-- // Pass a Client the new key
			RemoteEvent:FireClient(Player, PlayerLastCommunications[Player].Strings.GeneratedKey)
			
			-- // Reset 
			PlayerLastCommunications[Player].Numbers.Misses += 1
		end
	end)
end)

RemoteEvent.OnServerEvent:Connect(function(Player, PassedKey)
	
	-- // Type check
	if type(PassedKey) ~= "string" then
		Player:Kick("Key must be string")
	end
	
	-- // Decode key and store it as Player specific
	PlayerLastCommunications[Player].Strings.CurrentKey = Decoding.Decode(PassedKey)
	
	-- // Check if key has changed or not
	if PlayerLastCommunications[Player].Strings.GeneratedKey ~= PlayerLastCommunications[Player].Strings.CurrentKey then
		Player:Kick("Key missmatch")
	end
	
	-- // Timeout reset
	PlayerLastCommunications[Player].Numbers.Sent = tick()
end)

game.Players.PlayerRemoving:Connect(function(Player)
    -- // Clears all Player specific values upon leaving
	PlayerLastCommunications[Player] = nil
	
	task.defer(PlayerThreads[Player])
	PlayerThreads[Player] = nil
end)
ConfigurationModule (Child of ServerScript)

 ConfigurationModule
local ConfigurationModule = {

	Numbers = {
		TimeoutLimit = 3,
		CommunicationSpeed = 1,
	},

}
return ConfigurationModule
DecodingModule (Child of ServerScript)

 DecodingModule
local DecodingModule = {
	Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
}

-- // Base64 decoding [I didn't write this]
DecodingModule.Decode = function(Data)
	Data = string.gsub(Data, '[^'..DecodingModule.Alphabet..'=]', '')
	return (Data:gsub('.', function(x)
		if (x == '=') then return '' end
		local r,f='',(DecodingModule.Alphabet:find(x)-1)
		for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
		return r;
	end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
		if (#x ~= 8) then return '' end
		local c=0
		for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
		return string.char(c)
	end))
end

return DecodingModule
LocalScript (Parent of EncodingModule)

 LocalScript
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- // Variables
local Encoding = require(script.Encoding)
local RemoteEvent = game:GetService("ReplicatedStorage").RemoteEvent

RemoteEvent.OnClientEvent:Connect(function(RecievedKey)
	-- // Upon client receiving key we Encode the Key and pass the newly encoded key to the server
	RecievedKey = Encoding.Encode(RecievedKey)
	RemoteEvent:FireServer(RecievedKey)
end)
EncodingModule (Child of LocalScript)

 EncodingModule
local EncodingModule = {
	Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
}

-- // Base64 encoding [I didn't write this]
EncodingModule.Encode = function(Data)
	return ((Data:gsub('.', function(x) 
		local r,b='',x:byte()
		for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
		return r;
	end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
		if (#x < 6) then return '' end
		local c=0
		for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
		return EncodingModule.Alphabet:sub(c+1,c+1)
	end)..({ '', '==', '=' })[#Data%3+1])
end

return EncodingModule


----------------


Bloxstrike AC detects hooks like _namecall, hookmetamethod and many other things, It insta bans you.







---





Ways to get around it:
By emulating the handshake, with your own data, you can emulate the AC. However bloxstrike has





















## BAC heartbeat - captured beats (collector v3, FireServer fn hook)

Capture mechanism: beats are sent via a DIRECT FireServer function call (NOT a
`:FireServer` namecall), so hookfunction(remote.FireServer) catches them but a
__namecall hook does not. FakeIndex canary keeps the hook alive briefly (~5s,
~4 beats per session before BAC kicks).

Identity for this batch: name=vfdvfdvfd48 userid=11167304872 (f2=22334609744 f4=44669219488)

nonce,seq,digest_hex
42620,5,25a260d5d6d51723d5a6cd1dbd
30627,11,e9985b0bdc0f91d4c0e1f1591f0233112d8c3e
33976,11,0d39636c38b8c1435cc697ecbee745c32d701a
(42620,5 repeated identically -> deterministic)

### Findings
- DETERMINISTIC: same (nonce,seq) -> same digest (identity fixed).
- digest length = seq + 8 bytes  (seq5->13, seq11->19). Keystream length driven by seq.
- seq looks like a channel/type id, not a counter (only 5 and 11 seen; the seq5
  beat repeats with a constant nonce, seq11 beats vary nonce).
- Need MANY more samples (same account) across varying seq to reverse the PRNG/keystream.


## Batch 2 (name=vdsvsdvdsvds6 userid=11167516722)
nonce,seq,digest_hex
1823,1,65c2ff6d2313ab6de534776cf2            (13 bytes)
28685,1,a6d3c01d6dd4978e8185d43b0cefeee42d52f3 (19 bytes)
32014,1,9c08f708d23c4f60b4b0e8219b1214aa2d4a7b (19 bytes)

### Caller chain (who sends the beat)
FireServer(C) <- ReplicatedFirst.DataController (Lua, line 1 = VIRTUALIZED)
=> the heartbeat sender is a script chunknamed "ReplicatedFirst.DataController"
   (NOT the readable ReplicatedStorage.Controllers.DataController). The AC
   reuses that name as a disguise. Need to dump THIS function's upvalues.

### Revised findings
- len=seq+8 was COINCIDENCE. Batch2 has all seq=1 but lengths 13 AND 19.
- Length (13 vs 19) tracks nonce/content, not seq. Likely two beat variants.
- Still deterministic (1823,1 repeats identically).
- seq seen so far: 1, 5, 11.


## Batch 3 (name=KAPTOX4578-ish session) + crash confirmation
nonce,seq,digest_hex
3880,2,8be71e7d1e5067559393ed848542b4632d6859  (19 bytes)
27431,1,94f2473a3d02afb14174c8da5c              (13 bytes)
7203,2,aa21f54d381a4ddce9fde6d15275e9d72d1d59   (19 bytes)

### KEY: sender chunkname ROTATES (impersonation)
This session the beat sender's source = "ReplicatedFirst.CharacterController"
(previously "ReplicatedFirst.DataController"). The AC fakes DIFFERENT legit
ReplicatedFirst.* script names each time. So dump upvalues for ANY ReplicatedFirst/
Controller frame, not a fixed name.

### CRASH CONFIRMED (the "they crash after encryption" mechanism)
Post-detection errors:
  Luraph Script:1045: ReplicatedFirst.CharacterController:1: attempt to index nil with 'Destroy'
  Luraph Script:1295: ReplicatedFirst.CharacterController:1: attempt to index nil with 'FireServer'
=> On detection the AC nils its own remote and crashes at the FireServer call,
   so the encrypted beat never leaves -> server kicks for a MISSING beat.
   Plan: grab the finished encrypted beat off the stack (debug.getstack) before
   the crash and FireServer it ourselves.
