-- // VisionWare Chams
-- // Hooks into the main VisionWare GUI (loaded by gui.lua)

local Library = _G.Library or (getgenv and getgenv().Library)
if not Library then
	warn("[VisionWare] gui.lua must be loaded before chams.lua")
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = {
	Enabled = false,
	Color = Color3.fromRGB(255, 88, 166),
}

local activeHighlights = {}

local function createHighlightForCharacter(character)
	if not character or not character:IsA("Model") then return nil end
	if not Config.Enabled then return nil end
	local existing = character:FindFirstChild("VisionWareCham")
	if existing then return existing end

	local highlight = Instance.new("Highlight")
	highlight.Name = "VisionWareCham"
	highlight.FillColor = Config.Color
	highlight.OutlineColor = Config.Color
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = true
	highlight.Adornee = character
	highlight.Parent = character

	activeHighlights[character] = highlight
	return highlight
end

local function highlightAllPlayers()
	if not Config.Enabled then return end
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

local function clearAllHighlights()
	for character, highlight in pairs(activeHighlights) do
		if highlight then highlight:Destroy() end
	end
	activeHighlights = {}
end

local function onCharacterAdded(character)
	task.wait(0.1)
	if Config.Enabled and character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
		createHighlightForCharacter(character)
	end
end

local function onPlayerAdded(player)
	if player.Character then onCharacterAdded(player.Character) end
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(removeHighlightFromCharacter)
end

local function onPlayerRemoving(player)
	if player.Character then removeHighlightFromCharacter(player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
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

-- // Hook into the main GUI's "Visuals" page
local function getVisualsPage()
	for _, page in ipairs(Library.Pages) do
		if page.Name == "Visuals" then
			return page
		end
	end
	-- Fallback: first page
	return Library.Pages[1]
end

local VisualsPage = getVisualsPage()
if not VisualsPage then
	warn("[VisionWare] Could not find a page to attach Chams to")
	return
end

local Section = VisualsPage:Section({
	Name = "Chams",
	side = #VisualsPage.Sections == 0 and "left" or "right",
})

Section:Toggle({
	Name = "Enable Chams",
	Flag = "ChamsEnabled",
	callback = function(State)
		Config.Enabled = State
		if State then
			highlightAllPlayers()
		else
			clearAllHighlights()
		end
	end,
})

Section:Colorpicker({
	Name = "Cham Color",
	Flag = "ChamsColor",
	Default = Config.Color,
	Callback = function(Color)
		Config.Color = Color
		for character, highlight in pairs(activeHighlights) do
			if highlight then
				highlight.FillColor = Color
				highlight.OutlineColor = Color
			end
		end
	end,
})

print("[VisionWare] Chams hooked into GUI successfully!")