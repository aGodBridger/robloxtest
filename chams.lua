-- // VisionWare Chams
-- // Syncs with GUI chams toggle and color picker

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local activeHighlights = {}

local HIGHLIGHT_CONFIG = {
	FillTransparency = 0.5,
	OutlineTransparency = 0,
	DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	Enabled = false
}

-- Get current chams state from GUI flags
local function getChamsStateFromGUI()
	if _G.Library and _G.Library.Flags then
		local isEnabled = _G.Library.Flags.ESP_Chams or false
		local color = _G.Library.Flags.ESP_ChamsColor or Color3.fromRGB(255, 255, 255)
		return isEnabled, color
	end
	return false, Color3.fromRGB(255, 255, 255)
end

-- Create highlight for character
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

-- Highlight all current players
local function highlightAllPlayers(color)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			createHighlightForCharacter(player.Character, color)
		end
	end
end

-- Remove highlight from character
local function removeHighlightFromCharacter(character)
	if character and character:IsA("Model") then
		local highlight = character:FindFirstChild("PlayerHighlight")
		if highlight then
			highlight:Destroy()
			activeHighlights[character] = nil
		end
	end
end

-- Update all highlight colors
local function updateAllHighlightColors(color)
	for character, highlight in pairs(activeHighlights) do
		if highlight and character and character:IsA("Model") then
			highlight.FillColor = color
			highlight.OutlineColor = color
		end
	end
end

-- Handle character added
local function onCharacterAdded(character, player)
	task.wait(0.1)
	
	if character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
		local _, color = getChamsStateFromGUI()
		if HIGHLIGHT_CONFIG.Enabled then
			createHighlightForCharacter(character, color)
		end
	end
end

-- Handle character removing
local function onCharacterRemoving(character)
	removeHighlightFromCharacter(character)
end

-- Handle player added
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

-- Handle player removing
local function onPlayerRemoving(player)
	if player.Character then
		removeHighlightFromCharacter(player.Character)
	end
end

-- Initialize existing players
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Main sync loop with GUI
task.spawn(function()
	local lastEnabled = false
	local lastColor = Color3.fromRGB(255, 255, 255)
	
	while true do
		task.wait(0.1)
		
		local isEnabled, currentColor = getChamsStateFromGUI()
		
		-- Handle toggle changes
		if isEnabled ~= lastEnabled then
			HIGHLIGHT_CONFIG.Enabled = isEnabled
			
			if isEnabled then
				highlightAllPlayers(currentColor)
				print("[Chams] Enabled")
			else
				for character, highlight in pairs(activeHighlights) do
					if highlight then
						highlight:Destroy()
					end
				end
				activeHighlights = {}
				print("[Chams] Disabled")
			end
			
			lastEnabled = isEnabled
			lastColor = currentColor
		end
		
		-- Handle color changes
		if isEnabled and currentColor ~= lastColor then
			updateAllHighlightColors(currentColor)
			print("[Chams] Color updated")
			lastColor = currentColor
		end
	end
end)

-- Cleanup orphaned highlights
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

print("[VisionWare] Chams loaded")