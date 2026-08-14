-- // VisionWare Complete Loader
-- // Just run this script - it handles EVERYTHING automatically

local Loader = {
	User = "aGodBridger",            -- GitHub username / owner
	Repo = "robloxtest",             -- Repo name
	Branch = "main",                 -- Branch (main or master)
	Files = {
		"gui.lua",
		-- add more files below, e.g. "esp.lua",
	},
	Silent = false,                  -- true = hide "loaded" messages
}

local BaseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(
	Loader.User, Loader.Repo, Loader.Branch
)

assert(#Loader.Files > 0, "No files to load!")

local Success, Errors = 0, {}

-- ===== STEP 1: Load GUI from GitHub =====
for _, FileName in ipairs(Loader.Files) do
	local ok, Source = pcall(game.HttpGet, game, BaseUrl .. FileName)
	if ok and Source then
		local ok2, Loaded = pcall(loadstring, Source)
		if ok2 and Loaded then
			local ok3, run = pcall(Loaded)
			if ok3 then
				Success = Success + 1
				if not Loader.Silent then
					print("[VisionWare] Loaded " .. FileName)
				end
			else
				table.insert(Errors, FileName .. " errored while running: " .. tostring(run))
			end
		else
			table.insert(Errors, FileName .. " failed to compile: " .. tostring(Loaded))
		end
	else
		table.insert(Errors, FileName .. " failed to fetch (check username/repo/branch): " .. tostring(Source))
	end
end

-- ===== STEP 2: Create server script for chams =====
-- This function will be injected into the server
local function createServerChamsScript()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")

	local activeHighlights = {}

	local HIGHLIGHT_CONFIG = {
		FillTransparency = 0.5,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false
	}

	local function getChamsStateFromGUI()
		if _G.Library and _G.Library.Flags then
			local isEnabled = _G.Library.Flags.ESP_Chams or false
			local color = _G.Library.Flags.ESP_ChamsColor or Color3.fromRGB(255, 255, 255)
			return isEnabled, color
		end
		return false, Color3.fromRGB(255, 255, 255)
	end

	local function createHighlightForCharacter(character, color)
		if not character or not character:IsA("Model") then
			return nil
		end
		
		local existingHighlight = character:FindFirstChild("PlayerHighlight")
		if existingHighlight then
			return existingHighlight
		end
		
		local highlight = Instance.new("Highlight")
		highlight.Name = "PlayerHighlight"
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = HIGHLIGHT_CONFIG.FillTransparency
		highlight.OutlineTransparency = HIGHLIGHT_CONFIG.OutlineTransparency
		highlight.DepthMode = HIGHLIGHT_CONFIG.DepthMode
		highlight.Enabled = true
		highlight.Adornee = character
		highlight.Parent = character
		
		activeHighlights[character] = highlight
		
		return highlight
	end

	local function highlightAllPlayers(color)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				createHighlightForCharacter(player.Character, color)
			end
		end
	end

	local function removeHighlightFromCharacter(character)
		if character and character:IsA("Model") then
			local highlight = character:FindFirstChild("PlayerHighlight")
			if highlight then
				highlight:Destroy()
				activeHighlights[character] = nil
			end
		end
	end

	local function updateAllHighlightColors(color)
		for character, highlight in pairs(activeHighlights) do
			if highlight and character and character:IsA("Model") then
				highlight.FillColor = color
				highlight.OutlineColor = color
			end
		end
	end

	local function onCharacterRemoving(character)
		removeHighlightFromCharacter(character)
	end

	local function onCharacterAdded(character, player)
		task.wait(0.1)
		
		if character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
			local _, color = getChamsStateFromGUI()
			if HIGHLIGHT_CONFIG.Enabled then
				createHighlightForCharacter(character, color)
			end
		end
	end

	local function onPlayerAdded(player)
		if player.Character then
			onCharacterAdded(player.Character, player)
		end
		
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(character, player)
		end)
		
		player.CharacterRemoving:Connect(function(character)
			onCharacterRemoving(character)
		end)
	end

	local function onPlayerRemoving(player)
		if player.Character then
			removeHighlightFromCharacter(player.Character)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		local lastEnabled = false
		local lastColor = Color3.fromRGB(255, 255, 255)
		
		while true do
			task.wait(0.1)
			
			local isEnabled, currentColor = getChamsStateFromGUI()
			
			if isEnabled ~= lastEnabled then
				HIGHLIGHT_CONFIG.Enabled = isEnabled
				
				if isEnabled then
					highlightAllPlayers(currentColor)
					print("[Chams] Enabled via GUI")
				else
					for character, highlight in pairs(activeHighlights) do
						if highlight then
							highlight:Destroy()
						end
					end
					activeHighlights = {}
					print("[Chams] Disabled via GUI")
				end
				
				lastEnabled = isEnabled
				lastColor = currentColor
			end
			
			if isEnabled and currentColor ~= lastColor then
				updateAllHighlightColors(currentColor)
				print("[Chams] Color updated via GUI")
				lastColor = currentColor
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		for character, highlight in pairs(activeHighlights) do
			if not character or not character:IsA("Model") or not character:FindFirstChild("Humanoid") then
				if highlight then
					pcall(function() highlight:Destroy() end)
				end
				activeHighlights[character] = nil
			end
		end
	end)

	print("[Chams] Server script initialized")
end

-- ===== STEP 3: Inject server script =====
local function injectServerScript()
	-- Try to place script in ServerScriptService
	local ServerScriptService = game:GetService("ServerScriptService")
	if ServerScriptService then
		local script = Instance.new("LocalScript")
		script.Name = "ChamsServer"
		script.Source = "(" .. tostring(createServerChamsScript) .. ")()"
		script.Parent = ServerScriptService
		print("[VisionWare] Server chams script injected")
		return true
	end
	
	-- Fallback: Try RunService
	return false
end

-- Try to inject the server script
task.wait(0.5) -- Wait for GUI to load first
injectServerScript()

-- ===== Final Status =====
if #Errors > 0 then
	print("[VisionWare] " .. Success .. " loaded, " .. #Errors .. " failed")
	for _, Err in ipairs(Errors) do
		warn("[VisionWare] " .. Err)
	end
else
	print("[VisionWare] Loader finished - " .. Success .. "/" .. #Loader.Files .. " scripts loaded")
	print("[VisionWare] Everything is ready! Toggle 'Chams' in the ESP section")
end