local source = [===[
getgenv().knifeBotSettings = getgenv().knifeBotSettings or {
    onlyKillTargetUsernames = false,
    targetUsernames = { -- Name not DisplayName
        "",
    },
	autoSpawn = true,
	noKillProtection = true,
	autoVotekickRandom = true,
	autoHopOnVotekick = true,
	serverHopAfterTime = 10, -- minutes, false to disable
	disableRendering = false,

	-- prolly dont need to mess with these
    maxTeleportStuds = 9.9, -- maximum studs updates can be from each other
    pathfindingInterval = 3, -- raycasting interval (smaller is more laggy but better pathfinding, larger is less laggy but worse pathfinding)
    stayOnGround = true, -- whether or not pathfinding stays on the ground
    playerIgnoreDelay = 1.5, -- how many seconds it should ignore the target for when you get lagged back
    teleportStability = 10, -- how many updates it should send before stabbing
	teleportDelay = 0, -- how many ms to wait between teleports
    spawnStability = 150, -- how many updates to send when spawning
    performance = true, -- better fps and slightly slower knifebot
    pathfindingMaxTime = 1,--0.0833333, -- how long the pathfinding can freeze the game for
	updateSpeedMultiplier = 1, -- force teleporting to be faster, seems to despawnn sometimes
	maxKnifeDistance = 23 -- limit how far the player can be from the target when stabbing
}
function LPH_NO_VIRTUALIZE(fuction)
    return fuction
end
LPH_JIT_MAX = LPH_NO_VIRTUALIZE

if getgenv().unload then
	getgenv().unload()
end

local moduleCache
for i, v in getgc(true) do
	if type(v) == "table" and rawget(v, "ScreenCull") and rawget(v, "NetworkClient") then
		moduleCache = v
		break
	end
end

local modules = {}
for name, data in moduleCache do
	if type(data) == "table" then
		modules[name] = data.module
	end
end

local clientEvents
for i, v in getgc(true) do
	if type(v) == "table" and rawget(v, "died") and rawget(v, "smallaward") then
		clientEvents = v
		break
	end
end

local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local httpService = game:GetService("HttpService")
local teleportService = game:GetService("TeleportService")
--local pathfinding = loadstring(readfile("pathfinding.lua"))()
local pathfinding = loadstring(game:HttpGet("https://raw.githubusercontent.com/iRay888/wapus/refs/heads/main/pathfinding.lua"))() -- i didnt make this

local spawnUpdates = 0
local ignoredPlayers = {}
local currentPosition = nil
local currentTeleport = nil

local function ignorePlayer(player)
    table.insert(ignoredPlayers, player)
    task.delay(getgenv().knifeBotSettings.playerIgnoreDelay, function()
        table.remove(ignoredPlayers, table.find(ignoredPlayers, player))
    end)
end

local despawnCount = 0
local lastCorrection = 0
local correctPosition = clientEvents.correctposition
function clientEvents.correctposition(position)
	despawnCount+=1
	print(despawnCount)
    if currentTeleport then
		local clockTime = os.clock()
		
		if clockTime - lastCorrection < 1 then
        	ignorePlayer(currentTeleport.player)
		end

        currentTeleport = nil
		lastCorrection = clockTime
        print("teleport corrected")
    end

    currentPosition = position
    return correctPosition(position)
end

local lastDespawn = 0
local despawn = clientEvents.despawn
function clientEvents.despawn(data)
	lastDespawn = os.clock()
	return despawn(data)
end

local lastKill = 0
local killCount = 0
local hasKilled = false
local meleeHitConfirm = clientEvents.meleeHitConfirm
function clientEvents.meleeHitConfirm(...)
	lastKill = os.clock()
	killCount += 1
	task.delay(10, function()
		killCount -= 1
	end)

	if not hasKilled and getgenv().knifeBotSettings.autoVotekickRandom and modules.PlayerDataUtils.getPlayerRank(modules.PlayerDataClientInterface.getPlayerData()) >= 25 then
		task.delay(10, function()
			local target
	
			for _, player in players:GetPlayers() do
				if player ~= localPlayer then
					target = player
				end
			end
	
			if target then
				modules.NetworkClient:send("modcmd", "/votekick:" .. target.Name .. ":" .. ({"unfair", "hacker", "hacks", "cheats", "wall hacks"})[math.random(1, 5)])
			end
		end)
	end

	hasKilled = true
	return meleeHitConfirm(...)
end

local lastSpawn = 0
runService.Heartbeat:Connect(function()
	local alive = modules.CharacterInterface.isAlive()
	local clock = os.clock()

    if getgenv().knifeBotSettings.autoSpawn and not alive and clock - lastDespawn > 3.5 then
		modules.CharacterInterface.spawn()
		lastDespawn += 1
	end

    if getgenv().knifeBotSettings.noKillProtection and alive and clock then
		if clock - lastSpawn > 11 and killCount == 0 and clock - lastKill > 10 then
			modules.NetworkClient:send("forcereset")
		end
	end
end)

local function hopServers(min)
	queue_on_teleport("getgenv().knifeBotSettings = game:GetService('HttpService'):JSONDecode( [==[ " .. httpService:JSONEncode(getgenv().knifeBotSettings) .. " ]==] );" .. "task.wait(10);" .. request({Url = "https://raw.githubusercontent.com/iRay888/wapus/refs/heads/main/knifebot.lua", Method = "GET"}).Body)
	local cachedServers = httpService:JSONDecode(readfile("votekick cache/" .. localPlayer.Name .. ".json"))
	local minimum = min or 25

	local cursor
	while true do
		local serverData = httpService:JSONDecode(request({Url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100" .. (cursor and "&cursor=" .. cursor or ""), Method = "GET"}).Body).data
		
		for _, server in serverData do
			if type(server) == "table" and server.maxPlayers - 2 > server.playing and server.id ~= game.JobId and server.playing >= minimum and not table.find(cachedServers, server.id) then
				for i = 1, 3 do
					task.spawn(function()
						teleportService:TeleportToPlaceInstance(game.PlaceId, server.id)
					end)
					task.wait(5)
				end
			end
		end

		cursor = server.nextPageCursor
		
		if not cursor then
			break
		else
			task.wait(2)
		end
	end

	return hopServers(minimum - 1)
end

if not isfolder("votekick cache") then
	makefolder("votekick cache")
end

local fileName = "votekick cache/" .. localPlayer.Name .. ".json"
if not isfile(fileName) then
	writefile(fileName, httpService:JSONEncode({}))
end

if getgenv().knifeBotSettings.serverHopAfterTime then
	task.spawn(function()
		task.wait(getgenv().knifeBotSettings.serverHopAfterTime * 60)
		local oldData = httpService:JSONDecode(readfile(fileName))
		table.insert(oldData, game.JobId)
		writefile(fileName, httpService:JSONEncode(oldData))
		hopServers()
	end)
end

if getgenv().knifeBotSettings.autoHopOnVotekick then
	local console = clientEvents.console
	function clientEvents.console(message)
		local name = string.split(message, " has been kicked out of the server")[1]

		if name == localPlayer.Name then
			local oldData = httpService:JSONDecode(readfile(fileName))
			table.insert(oldData, game.JobId)
			writefile(fileName, httpService:JSONEncode(oldData))
			print("votekick detected")
			hopServers()
		end

		return console(message)
	end
end

if getgenv().knifeBotSettings.disableRendering then
	runService:Set3dRenderingEnabled(false)
end

--[[print(modules.CharacterInterface.step) what the frick
local b = os.clock()
local step = modules.CharacterInterface.step
function modules.CharacterInterface.step(a)
	local c = os.clock()
	print(a)
	print(c - b)
	c = b
	print()

	return step(a)
end]]

local send = modules.NetworkClient.send
--function modules.NetworkClient:send(name, ...)
modules.NetworkClient.send = LPH_NO_VIRTUALIZE(function(self, name, ...)
	if name == "spawn" then
		lastSpawn = os.clock()
    elseif name == "equip" then
        local slot, time = ...
        return send(self, name, 3, time)
    elseif name == "newbullets" or name == "bullethit" or name == "falldamage" or name == "flaguser" or name == "debug" or name == "logmessage" then
        return
    elseif name == "repupdate" then
		for i = 1, math.ceil(getgenv().knifeBotSettings.updateSpeedMultiplier) do
			local position, angles, time = ...

			if spawnUpdates < getgenv().knifeBotSettings.spawnStability then
				spawnUpdates += 1
				return send(self, name, ...)
			end

			if currentTeleport and not currentTeleport.complete and currentPosition then
				if currentTeleport.teleported then
					if not currentTeleport.stability then
						currentTeleport.stability = 0
					else
						currentTeleport.stability += 1

						send(self, name, currentPosition, angles, time)
						if currentTeleport.stability == getgenv().knifeBotSettings.teleportStability then
							currentTeleport.complete = true
							--currentTeleport.currentTime = nil
							--correctPosition(currentPosition)
							local rootPart = modules.CharacterInterface.getCharacterObject():getRealRootPart()
							rootPart.Position = currentPosition
							rootPart.Anchored = true
						end
					end
					
					return
				end

				if currentTeleport.currentTime then
					if currentTeleport.currentTime == 1 then
						currentTeleport.currentTime = nil
						if currentPosition == nil then
							print("despawn                             triggered")
						end
						--return send(self, name, currentPosition, angles, time)
					else
						currentTeleport.currentTime += 1
					end
				else
					if typeof(currentTeleport.path[currentTeleport.node]) == "Vector3" then
						currentPosition = currentTeleport.path[currentTeleport.node]
						send(self, name, currentPosition, angles, time)
					else
						print("type mismatch")
						print(typeof(currentTeleport.path[currentTeleport.node]), currentTeleport.path[currentTeleport.node])
					end
					
					repeat currentTeleport.node += 1 until (typeof(currentTeleport.path[currentTeleport.node]) == "Vector3") or (currentTeleport.node > currentTeleport.lastNode)
					
					if typeof(currentTeleport.path[currentTeleport.node]) == "Vector3" then
						currentPosition = currentTeleport.path[currentTeleport.node]
						send(self, name, currentPosition, angles, time)
						--send(self, name, currentPosition + Vector3.yAxis * 0.01, angles, time + 0.001)
					else
						currentTeleport.teleported = true
					end
					currentTeleport.currentTime = 1 -- time


					if (currentTeleport.node == currentTeleport.lastNode) or (not currentPosition) then
						currentTeleport.teleported = true
					end
				end

				return
			end

			currentPosition = position
			send(self, name, position, angles, time)
		end

		return
    end

    return send(self, name, ...)
end)

local sentSpawn = modules.CharacterInterface.spawn
function modules.CharacterInterface.spawn(player)
	currentPosition = nil
    currentTeleport = nil
    spawnUpdates = 0
	despawnCount = 0
	return sentSpawn(player)
end

local receivedSpawn = clientEvents.spawn
function clientEvents.spawn(position, direction, uniqueIds, loadoutData, attachmentData)
    currentTeleport = nil
    if getgenv().knifeBotSettings.spawnStability == 0 then
	    currentPosition = position
    end

	return receivedSpawn(position, direction, uniqueIds, loadoutData, attachmentData)
end

local function getClosestPlayers(position)
    local closestCharacters
    local characterData

    modules.ReplicationInterface.operateOnAllEntries(function(player, entry)
        local character = entry._thirdPersonObject and entry._thirdPersonObject:getCharacterHash()

        if entry._receivedPosition and entry._velspring.t and character and player.Team ~= localPlayer.Team and character.Head and not table.find(ignoredPlayers, player) then
            if (not getgenv().knifeBotSettings.onlyKillTargetUsernames) or table.find(getgenv().knifeBotSettings.targetUsernames, player.Name) then
                local playerDistance = (character.Head.Position - position).Magnitude
                local playerData = {character, playerDistance}
                
                if not characterData then
                    characterData = {playerData}
                    closestCharacters = {entry}
                else
                    for charIndex = #characterData, 1, -1 do
                        if playerDistance > characterData[charIndex][2] then
                            table.insert(characterData, charIndex + 1, playerData)
                            table.insert(closestCharacters, charIndex + 1, entry)
                            break
                        end
                    end
        
                    if not table.find(characterData, playerData) then
                        table.insert(characterData, 1, playerData)
                        table.insert(closestCharacters, 1, entry)
                    end
                end
            end
        end
    end)

    return closestCharacters
end

function waitHeartbeat()
    return getgenv().knifeBotSettings.performance and runService.Heartbeat:Wait()
end

local lastFinish = 0
local pathfindingParams = {
    step = getgenv().knifeBotSettings.pathfindingInterval,
    trials = 1/0,
    weighting = 400,
    mindist = getgenv().knifeBotSettings.maxKnifeDistance,
    maxtime = getgenv().knifeBotSettings.pathfindingMaxTime,
}
--function knifeBotStep()
local knifeBotStep = LPH_NO_VIRTUALIZE(function()
    local canSkip = false

	if (modules.CharacterInterface.isAlive() or modules.CharacterInterface.isSpawning()) and not modules.RoundSystemClientInterface.roundLock and currentPosition and ((getgenv().knifeBotSettings.teleportDelay == 0) or (os.clock() - lastFinish > getgenv().knifeBotSettings.teleportDelay * 0.001)) then
        local closestEntries = getClosestPlayers(currentPosition)
        local targetEntry
		
        if closestEntries then
            for entryIndex = 1, #closestEntries do
                local entry = closestEntries[entryIndex]
                
                if entry:isAlive() and entry._receivedPosition then
                    local position = entry._receivedPosition
                    local pathfindFunc = getgenv().knifeBotSettings.stayOnGround and pathfinding.floorAStar or pathfinding.vadAStar
					local start = currentPosition
					pathfindingParams.maxtime = 0.25 + math.random() * (getgenv().knifeBotSettings.pathfindingMaxTime - 0.25) -- pro
                    local result, data = pathfindFunc({
                        start = start,
                        goal = position,
                        parameters = pathfindingParams
                    })
					--local result, data = pathfinding.floorBestFirstSearch(origin, target, param)
                    
                    if result == true then
                        print("path found")
                        local movements = pathfinding.optimizePath(data.waypoints, getgenv().knifeBotSettings.maxTeleportStuds)

						if movements then
							--pathfinding.visualizePath(movements, Color3.new(1, 0, 0))
							--unload()
							--table.insert(movements, 1, start)
							targetEntry = entry
							currentTeleport = {
								--currentTime = 1,
								player = entry._player,
								lastNode = #movements,
								path = movements,
								node = 1
							}
							break
						else
							print("no path :(")
							waitHeartbeat()
						end
                    else
                        print("no path :(")
                        waitHeartbeat()
                    end
                end
            end
        end

        if targetEntry then
            canSkip = true
            repeat runService.Heartbeat:Wait() until (not currentTeleport or currentTeleport.complete)
			lastFinish = os.clock()

            if currentTeleport then
                ignorePlayer(targetEntry._player)

                for _ = 1, 2 do
					task.wait(0.05)

					if targetEntry:isAlive() and targetEntry._receivedPosition then
						modules.NetworkClient:send("stab")
						modules.NetworkClient:send("knifehit", targetEntry._player, "Head", targetEntry._receivedPosition, modules.NetworkClient.getTime())
					end
                end
				
				task.wait(0.05)
                local character = modules.CharacterInterface.getCharacterObject()
				if character then
					character:getRealRootPart().Anchored = false
				end
                print("stabbed", targetEntry._player)
                currentTeleport = nil
            end
        end
    end
    
    if canSkip then
        waitHeartbeat()
    else
        runService.Heartbeat:Wait()
    end
end)

local stop = false
getgenv().unload = function()
	clientEvents.correctposition = correctPosition
	modules.NetworkClient.send = send
	modules.CharacterInterface.spawn = sentSpawn
	clientEvents.spawn = receivedSpawn
	stop = true
end

task.spawn(function()
	while true do -- pro
		knifeBotStep()

		if stop then
			break
		end
	end
end)
]===]

Instance.new("Folder", workspace.Ignore).Name = "Farming"
local environment = identifyexecutor and identifyexecutor() or ""
local settingsFixString = ""

if getgenv().knifeBotSettings then
    settingsFixString = "getgenv().knifeBotSettings = game:GetService('HttpService'):JSONDecode([=[" .. game:GetService('HttpService'):JSONEncode(getgenv().knifeBotSettings) .. "]=]);"
end

if getfflag and string.find(string.lower(tostring(getfflag("DebugRunParallelLuaOnMainThread"))), "true") and not executed then
    loadstring(settingsFixString .. source)()
elseif string.find(environment, "AWP") ~= nil and not executed then
    for _, v in getactors() do
        run_on_actor(v, settingsFixString .. [[
            for _, func in getgc(false) do
                if type(func) == "function" and islclosure(func) and debug.getinfo(func).name == "require" and string.find(debug.getinfo(func).source, "ClientLoader") then
                    ]] .. source .. [[
                    break
                end
            end
        ]])
    end
elseif environment == "Wave" and not executed then
    run_on_actor(getdeletedactors()[1], settingsFixString .. source)
elseif environment == "Nihon" and not executed then
    for _, actor in getactorthreads() do
        run_on_thread(actor, settingsFixString .. [[
            for _, func in getgc(false) do
                if type(func) == "function" and islclosure(func) and debug.getinfo(func).name == "require" and string.find(debug.getinfo(func).source, "ClientLoader") then
                    ]] .. source .. [[
                    break
                end
            end
        ]])
    end
else
    queue_on_teleport(game:HttpGet("https://raw.githubusercontent.com/iRay888/wapus/refs/heads/main/hook.lua") .. settingsFixString .. "task.wait(5);" .. source)
    setfflag("DebugRunParallelLuaOnMainThread", "True")
    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId)
end
--getgenv().executed = true
