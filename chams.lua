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
		local opacity = _G.Library.Flags.ESP_Opacity or 75
		local visibleOnly = _G.Library.Flags.ESP_VisibleOnly or false
		return isEnabled, color, opacity, visibleOnly
	end
	return false, Color3.fromRGB(255, 255, 255), 75, false
end

local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Raycast check: is the target character visible to the camera?
local function isCharacterVisible(character, visibleOnly)
	if not visibleOnly then return true end
	if not character or not character:IsA("Model") then return true end
	if not Camera then return true end

	local root = character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Head")
		or character:FindFirstChild("Torso")
	if not root then return true end

	local origin = Camera.CFrame.Position
	local target = root.Position

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, target - origin, params)
	if not result then return true end
	if result.Instance and result.Instance:IsDescendantOf(character) then
		return true
	end
	return false
end

-- Create highlight for character
local function createHighlightForCharacter(character, color, opacity)
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
	highlight.FillTransparency = 1 - (opacity / 100)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = HIGHLIGHT_CONFIG.DepthMode
	highlight.Enabled = true
	highlight.Adornee = character
	highlight.Parent = character
	
	activeHighlights[character] = highlight
	
	return highlight
end

-- Update opacity on all active highlights
local function updateAllHighlightOpacity(opacity)
	for character, highlight in pairs(activeHighlights) do
		if highlight and character and character:IsA("Model") then
			highlight.FillTransparency = 1 - (opacity / 100)
		end
	end
end

-- Highlight all current players
local function highlightAllPlayers(color, opacity, visibleOnly)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			local character = player.Character
			if isCharacterVisible(character, visibleOnly) then
				createHighlightForCharacter(character, color, opacity)
			else
				removeHighlightFromCharacter(character)
			end
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
		local isEnabled, color, opacity, visibleOnly = getChamsStateFromGUI()
		if isEnabled and isCharacterVisible(character, visibleOnly) then
			createHighlightForCharacter(character, color, opacity)
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
	local lastOpacity = -1
	local lastVisibleOnly = nil
	
	while true do
		task.wait(0.1)
		
		local isEnabled, currentColor, currentOpacity, currentVisibleOnly = getChamsStateFromGUI()
		
		-- Handle toggle changes
		if isEnabled ~= lastEnabled then
			if isEnabled then
				highlightAllPlayers(currentColor, currentOpacity, currentVisibleOnly)
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
			lastOpacity = currentOpacity
			lastVisibleOnly = currentVisibleOnly
		end
		
		if isEnabled then
			-- Handle color changes
			if currentColor ~= lastColor then
				updateAllHighlightColors(currentColor)
				lastColor = currentColor
			end
			
			-- Handle opacity changes
			if currentOpacity ~= lastOpacity then
				updateAllHighlightOpacity(currentOpacity)
				lastOpacity = currentOpacity
			end
			
			-- Handle visible-only changes (re-evaluate which players are highlighted)
			if currentVisibleOnly ~= lastVisibleOnly then
				highlightAllPlayers(currentColor, currentOpacity, currentVisibleOnly)
				lastVisibleOnly = currentVisibleOnly
			end
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