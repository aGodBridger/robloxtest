-- // VisionWare Chams
-- // Run after gui.lua (which exposes getgenv().Library)

local Library = getgenv().Library
if not Library then
	warn("[VisionWare] gui.lua must be loaded before chams.lua")
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HIGHLIGHT_CONFIG = {
	FillColor = Color3.fromRGB(255, 88, 166),
	OutlineColor = Color3.fromRGB(255, 88, 166),
	FillTransparency = 0.5,
	OutlineTransparency = 0,
	DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
}

local activeHighlights = {}
local ChamsEnabled = false

local function createHighlightForCharacter(character)
	if not character or not character:IsA("Model") then return nil end
	if not ChamsEnabled then return nil end

	local existing = character:FindFirstChild("VisionWareCham")
	if existing then return existing end

	local highlight = Instance.new("Highlight")
	highlight.Name = "VisionWareCham"
	highlight.FillColor = HIGHLIGHT_CONFIG.FillColor
	highlight.OutlineColor = HIGHLIGHT_CONFIG.OutlineColor
	highlight.FillTransparency = HIGHLIGHT_CONFIG.FillTransparency
	highlight.OutlineTransparency = HIGHLIGHT_CONFIG.OutlineTransparency
	highlight.DepthMode = HIGHLIGHT_CONFIG.DepthMode
	highlight.Enabled = true
	highlight.Adornee = character
	highlight.Parent = character

	activeHighlights[character] = highlight
	return highlight
end

local function highlightAllPlayers()
	if not ChamsEnabled then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			createHighlightForCharacter(player.Character)
		end
	end
end

local function removeHighlightFromCharacter(character)
	if character and character:IsA("Model") then
		local highlight = character:FindFirstChild("VisionWareCham")
		if highlight then
			highlight:Destroy()
			activeHighlights[character] = nil
		end
	end
end

local function onCharacterAdded(character)
	task.wait(0.1)
	if ChamsEnabled and character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
		createHighlightForCharacter(character)
	end
end

local function onPlayerAdded(player)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(character)
	end)
	player.CharacterRemoving:Connect(function(character)
		removeHighlightFromCharacter(character)
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

RunService.Heartbeat:Connect(function()
	for character, highlight in pairs(activeHighlights) do
		if not character or not character:IsA("Model") or not character:FindFirstChild("Humanoid") then
			if highlight then highlight:Destroy() end
			activeHighlights[character] = nil
		end
	end
end)

-- // Hook into the existing "Visuals" page from gui.lua
local VisualsPage
for _, page in ipairs(Library.Pages) do
	if page.Name == "Visuals" then
		VisualsPage = page
		break
	end
end

if not VisualsPage then
	warn("[VisionWare] Could not find Visuals page")
	return
end

local Section = VisualsPage:Section({
	Name = "Chams",
	side = #VisualsPage.Sections == 0 and "left" or "right",
})

Section:Toggle({
	Name = "Enable Chams",
	flag = "ChamsEnabled",
	callback = function(State)
		ChamsEnabled = State
		if State then
			highlightAllPlayers()
		else
			for character, highlight in pairs(activeHighlights) do
				if highlight then highlight:Destroy() end
			end
			activeHighlights = {}
		end
	end,
})

Section:Colorpicker({
	Name = "Cham Color",
	Flag = "ChamsColor",
	Default = HIGHLIGHT_CONFIG.FillColor,
	Callback = function(Color)
		HIGHLIGHT_CONFIG.FillColor = Color
		HIGHLIGHT_CONFIG.OutlineColor = Color
		for character, highlight in pairs(activeHighlights) do
			if highlight then
				highlight.FillColor = Color
				highlight.OutlineColor = Color
			end
		end
	end,
})

print("[VisionWare] Chams loaded")